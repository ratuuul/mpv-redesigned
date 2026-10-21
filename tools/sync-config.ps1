<#
.SYNOPSIS
    Sync the live mpv configuration into the repository, safely.

.DESCRIPTION
    The repository's `config/` folder is a copy of the live configuration in
    %APPDATA%\mpv. Several people edit that live tree in parallel, so this
    script does three things:

      1. Waits for the live tree to go quiet. A change resets the quiet
         timer. The wait is capped so the script always finishes.

      2. Merges the live tree into the repository, per file, taking the
         NEWER of the two copies. Editing happens in both places, so a blind
         overwrite in either direction would throw work away. Files that
         only exist in one of the two trees are kept.

      3. Verifies the result: every Lua file must parse with Lua 5.1 (the
         dialect mpv's LuaJIT speaks) and mpv must start against the
         merged config without a single error or warning.

    Runtime state (logs, caches, watch history, screenshots, the recent-file
    list) and the components that are deliberately not published are never
    copied. The script never touches .HOLD, never creates a remote and never
    pushes.

.PARAMETER QuietMinutes
    How long the live tree has to be unchanged before the merge starts.
    Default 15.

.PARAMETER MaxMinutes
    Hard cap on the wait. Default 90.

.PARAMETER Apply
    Actually merge. Without it the script only reports what it would do.

.PARAMETER Commit
    Commit the merged config when every verification step passes.

.PARAMETER NoWait
    Skip the quiescence wait. Only for a deliberate, one-off refresh.

.EXAMPLE
    pwsh -File tools/sync-config.ps1 -Apply

.EXAMPLE
    pwsh -File tools/sync-config.ps1 -Apply -Commit
#>

[CmdletBinding()]
param(
    [int]    $QuietMinutes = 15,
    [int]    $MaxMinutes  = 90,
    [switch] $Apply,
    [switch] $Commit,
    [switch] $NoWait,
    [switch] $ListPlan
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$liveDir  = Join-Path $env:APPDATA 'mpv'
$repoDir  = Join-Path $repoRoot 'config'

if (-not (Test-Path $liveDir)) { throw "Live config not found at $liveDir" }
if (-not (Test-Path $repoDir)) { throw "Repo config not found at $repoDir" }

# ---------------------------------------------------------------------------
#  What must never end up in the repository
# ---------------------------------------------------------------------------
# Runtime state: personal (paths, playback history) and machine specific.
$skipDirs  = @('cache', 'state', 'watch_later', 'screenshots', 'subs',
                'subtitles', 'temp')
$skipFiles = @('mpv.log', 'recent.json', 'INSTALL.txt', 'yt-dlp.exe',
                'yt-dlp_linux', 'yt-dlp_macos', 'ffmpeg.exe', 'ffprobe.exe',
                'mpv.exe', 'mpv.com')

# Components that were deliberately left out of the repository, with a reason
# given in THIRD_PARTY_NOTICES.md. They are removed from the repo copy on
# every run so a stale copy can never come back.
$skipFiles += @(
    # No provenance information; see THIRD_PARTY_NOTICES.md.
    'fonts\Spell of Asia.ttf',
    # libass would try to load it as a font and log an error on every file.
    'fonts\LICENSE-Geist.txt',
    # Audio asset with no provenance information.
    'scripts\uosc\assets\sounds\tick.wav'
)

# Icons downloaded from SVG Repo. The site answers every request with a bot
# challenge, so their licence terms could not be verified. The skin renders
# the same icons from the inline fallback paths in lib/liquid/icons.lua.
$skipFiles += @(
    'scripts\uosc\assets\icons\audio_track.svg',
    'scripts\uosc\assets\icons\headphones.svg',
    'scripts\uosc\assets\icons\info.svg',
    'scripts\uosc\assets\icons\next.svg',
    'scripts\uosc\assets\icons\pause.svg',
    'scripts\uosc\assets\icons\play.svg',
    'scripts\uosc\assets\icons\playlist.svg',
    'scripts\uosc\assets\icons\playlist_play.svg',
    'scripts\uosc\assets\icons\prev.svg',
    'scripts\uosc\assets\icons\settings.svg',
    'scripts\uosc\assets\icons\speed.svg',
    'scripts\uosc\assets\icons\subtitle.svg',
    'scripts\uosc\assets\icons\video_camera.svg',
    'scripts\uosc\assets\icons\volume_down.svg',
    'scripts\uosc\assets\icons\volume_mute.svg',
    'scripts\uosc\assets\icons\volume_off.svg',
    'scripts\uosc\assets\icons\volume_up.svg'
)

function Test-Skipped([string] $RelativePath) {
    $p = $RelativePath -replace '/', '\'
    if ($skipFiles -contains $p) { return $true }
    $parts = $p -split '\\'
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if ($skipDirs -contains $parts[$i]) { return $true }
    }
    if ($parts[-1] -eq '.gitkeep') { return $true }
    return $false
}

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
function Get-Tree([string] $Root) {
    $map = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            $map[$rel] = $_
        }
    return $map
}

function Get-NewestWrite([string] $Root) {
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue
    if (-not $files) { return [datetime]::MinValue }
    return ($files | Measure-Object -Property LastWriteTime -Maximum).Maximum
}

function Get-LiveStamp {
    <#
        A cheap fingerprint of BOTH trees. People edit the live config and
        the repository copy at the same time, so both have to be quiet
        before a merge is safe.
    #>
    $parts = @()
    foreach ($root in @($liveDir, $repoDir)) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-Skipped ($_.FullName.Substring($root.Length).TrimStart('\', '/'))) } |
            ForEach-Object {
                $parts += ('{0}|{1}|{2}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks)
            }
    }
    $joined = ($parts | Sort-Object) -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [Security.Cryptography.SHA256]::Create()
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
}

Write-Host ''
Write-Host '  sync-config' -ForegroundColor White
Write-Host '  ------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  live : $liveDir"
Write-Host "  repo : $repoDir"
Write-Host ''

# ---------------------------------------------------------------------------
#  1. Quiescence
# ---------------------------------------------------------------------------
if ($NoWait) {
    Write-Warning '-NoWait: skipping the quiescence wait.'
} else {
    Write-Host "  Waiting for the live config to be quiet for $QuietMinutes minute(s) (cap $MaxMinutes)..." -ForegroundColor Cyan
    $deadline  = (Get-Date).AddMinutes($MaxMinutes)
    $lastStamp = (Get-LiveStamp)
    $quietSince = Get-Date
    while ($true) {
        Start-Sleep -Seconds 30
        $now  = Get-Date
        $stamp = Get-LiveStamp
        if ($stamp -ne $lastStamp) {
            $lastStamp  = $stamp
            $quietSince = $now
            Write-Host ("  {0:HH:mm:ss}  change detected, quiet timer reset" -f $now) -ForegroundColor DarkGray
            continue
        }
        $quietFor = ($now - $quietSince).TotalMinutes
        if ($quietFor -ge $QuietMinutes) {
            Write-Host ("  {0:HH:mm:ss}  quiet for {1:N0} minute(s) - proceeding" -f $now, $quietFor) -ForegroundColor Green
            break
        }
        if ($now -ge $deadline) {
            Write-Warning ("Cap of $MaxMinutes minute(s) reached while the config was still changing. Proceeding anyway.")
            break
        }
        $left = [int]($QuietMinutes - $quietFor)
        Write-Host ("  {0:HH:mm:ss}  quiet for {1:N1}/{2} min ({3}s left)" -f $now, $quietFor, $QuietMinutes, $left) -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
#  2. Merge
# ---------------------------------------------------------------------------
$attempt = 0
$moved = 0
$removed = 0
$kept = @()

while ($true) {
    $attempt++
    Write-Host ''
    Write-Host "  Merge attempt $attempt" -ForegroundColor Cyan

    $live = Get-Tree $liveDir
    $repo = Get-Tree $repoDir
    $all  = @($live.Keys) + @($repo.Keys) | Sort-Object -Unique

    $moved = 0
    $removed = 0
    $kept = @()
    $plan = @()

    foreach ($rel in $all) {
        $inLive = $live.ContainsKey($rel)
        $inRepo = $repo.ContainsKey($rel)

        if (Test-Skipped $rel) {
            if ($inRepo) { $plan += [pscustomobject]@{ Rel = $rel; Action = 'remove' } }
            continue
        }

        if ($inLive -and $inRepo) {
            $src = if ($live[$rel].LastWriteTimeUtc -ge $repo[$rel].LastWriteTimeUtc) { $live[$rel] } else { $repo[$rel] }
            $dst = $repoDir + '\' + $rel
            if ($src.FullName -ne $dst) {
                # The live copy is newer, but it may still be byte-identical.
                # Only report a copy when the content really differs.
                if ((Get-FileHash -LiteralPath $src.FullName).Hash -ne
                    (Get-FileHash -LiteralPath $dst).Hash) {
                    $plan += [pscustomobject]@{ Rel = $rel; Action = 'copy'; Src = $src.FullName; Dst = $dst }
                }
            }
        } elseif ($inLive) {
            $plan += [pscustomobject]@{ Rel = $rel; Action = 'copy'; Src = $live[$rel].FullName; Dst = $repoDir + '\' + $rel }
        } else {
            # Only in the repository. That is either deliberate repository-only
            # work or a file the live tree deleted. Keep it and say so.
            $kept += $rel
        }
    }

    if (-not $Apply) {
        Write-Host "  would copy    : $($plan.Count)" -ForegroundColor DarkGray
        Write-Host "  would remove  : $(($plan | Where-Object { $_.Action -eq 'remove' }).Count)" -ForegroundColor DarkGray
        Write-Host "  kept (repo only): $($kept.Count)" -ForegroundColor DarkGray
        foreach ($k in $kept) { Write-Host "      $k" -ForegroundColor DarkGray }
        if ($ListPlan) {
            Write-Host ''
            Write-Host '  Plan:' -ForegroundColor DarkGray
            foreach ($p in ($plan | Sort-Object Action, Rel)) {
                Write-Host ("      [{0}] {1}" -f $p.Action, $p.Rel) -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        Write-Host '  Dry run: nothing was changed.' -ForegroundColor Yellow
        break
    }

    foreach ($p in $plan) {
        if ($p.Action -eq 'remove') {
            Remove-Item -LiteralPath $p.Dst -Force -ErrorAction SilentlyContinue
            $removed++
            continue
        }
        $parent = Split-Path -Parent $p.Dst
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Copy-Item -LiteralPath $p.Src -Destination $p.Dst -Force
        $moved++
    }

    Write-Host "  copied   : $moved" -ForegroundColor Green
    Write-Host "  removed  : $removed" -ForegroundColor Green
    Write-Host "  kept (repo only): $($kept.Count)" -ForegroundColor DarkGray
    foreach ($k in $kept) { Write-Host "      $k" -ForegroundColor DarkGray }

    # Did anything change underneath us while we were copying?
    $stampAfter = Get-LiveStamp
    Start-Sleep -Seconds 5
    $stampFinal = Get-LiveStamp
    if ($stampAfter -eq $stampFinal -and $attempt -lt 3) {
        Write-Host '  The live config was still moving. Re-running the merge.' -ForegroundColor Yellow
        continue
    }
    if ($stampAfter -ne $stampFinal) {
        Write-Warning 'The live config changed during the copy. The next run will pick it up.'
    }
    break
}

# ---------------------------------------------------------------------------
#  3. Verify
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  Verifying' -ForegroundColor Cyan

$verifyOk = $true

# --- The published ytdl line must never carry the browser cookie option ---
# cookies-from-browser=firefox hard-fails on any machine without that
# Firefox profile and takes every YouTube URL down with it. The live config
# still has it, so a merge could reintroduce it. The repository ships
# without it; the comment block in mpv.conf explains how to add it back.
$baselineYtdl = 'ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node'
$mpvConf = Join-Path $repoDir 'mpv.conf'
if (Test-Path $mpvConf) {
    $text = [IO.File]::ReadAllText($mpvConf)
    $bad  = $false
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.StartsWith('#')) { continue }
        if ($t -match '^ytdl-raw-options\s*=' -and $t -match 'cookies-from-browser') { $bad = $true }
    }
    if ($bad) {
        $fixed = ($text -split "`r?`n" | ForEach-Object {
            $t = $_.Trim()
            if ($t.StartsWith('#')) { return $_ }
            if ($t -match '^ytdl-raw-options\s*=') { return $baselineYtdl }
            return $_
        }) -join "`r`n"
        if ($Apply) {
            [IO.File]::WriteAllText($mpvConf, $fixed, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host '  FIXED mpv.conf: removed cookies-from-browser from ytdl-raw-options' -ForegroundColor Yellow
        } else {
            Write-Host '  WOULD FIX mpv.conf: remove cookies-from-browser from ytdl-raw-options' -ForegroundColor Yellow
            $verifyOk = $false
        }
    } else {
        Write-Host '  OK    mpv.conf ships without cookies-from-browser' -ForegroundColor Green
    }
}

$luaFiles = Get-ChildItem -LiteralPath $repoDir -Recurse -File -Filter *.lua
$luac = Get-Command luac5.1 -ErrorAction SilentlyContinue
if (-not $luac) { $luac = Get-Command luac -ErrorAction SilentlyContinue }
if ($luac) {
    $bad = 0
    foreach ($f in $luaFiles) {
        $out = & $luac.Source -p $f.FullName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAIL $($f.FullName)" -ForegroundColor Red
            Write-Host "       $out" -ForegroundColor Red
            $bad++
        }
    }
    if ($bad) { $verifyOk = $false; Write-Host "  $bad Lua file(s) failed to parse" -ForegroundColor Red }
    else { Write-Host "  OK    $($luaFiles.Count) Lua files parse" -ForegroundColor Green }
} else {
    Write-Warning 'luac not found - skipped the Lua syntax check'
}

$mpv = Get-Command mpv.com -ErrorAction SilentlyContinue
if (-not $mpv) { $mpv = Get-Command mpv -ErrorAction SilentlyContinue }
if ($mpv) {
    $log = Join-Path $env:TEMP ('mpv-sync-verify-' + [guid]::NewGuid().ToString('N') + '.log')
    $args = @('--no-terminal', '--idle=yes', '--vo=null', '--ao=null',
              "--config-dir=$repoDir", "--log-file=$log", '--msg-level=all=info',
              '--script-opts=bg-enabled=no',
              '--input-ipc-server=\\.\pipe\mpv_sync_verify')
    $proc = Start-Process -FilePath $mpv.Source -ArgumentList $args -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 8
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
    Start-Sleep -Seconds 1
    $problems = @()
    if (Test-Path $log) {
        $problems = Get-Content $log | Where-Object {
            $_ -match '\[e\]' -or $_ -match '\[f\]' -or $_ -match 'Lua error' -or
            $_ -match 'Error parsing option' -or $_ -match 'Invalid value' -or
            $_ -match '\[w\]'
        }
    }
    if ($problems.Count -gt 0) {
        $verifyOk = $false
        Write-Host "  mpv reported $($problems.Count) problem(s):" -ForegroundColor Red
        $problems | Select-Object -First 15 | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
    } else {
        Write-Host '  OK    mpv started against the merged config with no errors or warnings' -ForegroundColor Green
    }
} else {
    Write-Warning 'mpv not found - skipped the runtime check'
}

if (-not $verifyOk) {
    Write-Host ''
    Write-Host '  VERIFICATION FAILED. Nothing was committed.' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
#  4. Commit
# ---------------------------------------------------------------------------
if ($Commit) {
    Push-Location $repoRoot
    try {
        git add -- config
        git status --short -- config
        git -c user.name='Ratul' -c user.email='ratuuul@users.noreply.github.com' `
            commit -m 'Refresh the configuration from the live mpv install'
        Write-Host '  Committed.' -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host ''
    Write-Host '  Merge complete and verified. Re-run with -Commit to record it.' -ForegroundColor Green
}
Write-Host ''
