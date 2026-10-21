<#
.SYNOPSIS
    One-click installer for mpv-redesigned.

.DESCRIPTION
    Sets up a complete, tuned mpv installation on Windows 10/11:

      1. Installs mpv if it is not already present
      2. Downloads yt-dlp (YouTube and other network sources)
      3. Backs up any existing mpv configuration
      4. Deploys this configuration to %APPDATA%\mpv
      5. Checks that Node.js is available (full-quality YouTube needs it)
      6. Verifies that the configuration parses without errors

    Run it from a cloned repository:

        powershell -ExecutionPolicy Bypass -File .\install.ps1

    Or straight from the internet, with nothing cloned:

        irm https://raw.githubusercontent.com/ratuuul/mpv-redesigned/main/install.ps1 | iex

.PARAMETER InstallDir
    Where the configuration is deployed. Defaults to %APPDATA%\mpv.

.PARAMETER ConfigOnly
    Skip installing mpv and yt-dlp. Only deploy the configuration.

.PARAMETER Force
    Deploy even if a configuration already exists, without asking.

.PARAMETER NoBackup
    Do not back up the existing configuration. Destructive - use with care.

.PARAMETER NoHistory
    Do not carry over the previous watch_later history and screenshots folder.

.PARAMETER DryRun
    Print every action without changing anything.

.EXAMPLE
    .\install.ps1
    Standard install: mpv + yt-dlp + this configuration.

.EXAMPLE
    .\install.ps1 -ConfigOnly -DryRun
    Show what would be deployed, change nothing.

.NOTES
    Project : https://github.com/ratuuul/mpv-redesigned
    License : MIT (original work) - see THIRD_PARTY_NOTICES.md for bundled components
#>

[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:APPDATA 'mpv'),
    [switch] $ConfigOnly,
    [switch] $Force,
    [switch] $NoBackup,
    [switch] $NoHistory,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Pretty output
# ---------------------------------------------------------------------------
$script:StepNo = 0

function Write-Step([string] $Text) {
    $script:StepNo++
    Write-Host ''
    Write-Host ("  [{0}] {1}" -f $script:StepNo, $Text) -ForegroundColor Cyan
}
function Write-Ok([string] $Text)   { Write-Host "      OK    $Text" -ForegroundColor Green }
function Write-Info([string] $Text) { Write-Host "            $Text" -ForegroundColor DarkGray }
function Write-Warn([string] $Text) { Write-Host "      WARN  $Text" -ForegroundColor Yellow }
function Write-Err([string] $Text)  { Write-Host "      FAIL  $Text" -ForegroundColor Red }

function Invoke-Action([string] $Description, [scriptblock] $Action) {
    if ($DryRun) {
        Write-Info "would: $Description"
        return
    }
    & $Action
}

function Assert-Windows {
    if ($env:OS -ne 'Windows_NT') {
        throw 'mpv-redesigned currently targets Windows only.'
    }
}

function Set-ModernTls {
    # Windows PowerShell 5.1 defaults to TLS 1.0 for some endpoints.
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        # Ignore: newer runtimes negotiate TLS themselves.
    }
}

# ---------------------------------------------------------------------------
#  1. Locate the payload
# ---------------------------------------------------------------------------
function Get-RepoRoot {
    <#
        Returns a directory containing a `config` folder.

        Two modes:
          * local  - the script sits next to config/ (cloned repo)
          * remote - invoked via `irm ... | iex`, so download the archive
    #>
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot 'config'
        if (Test-Path $local) { return $PSScriptRoot }
    }

    $root = Join-Path $env:TEMP ("mpv-redesigned-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip  = Join-Path $root 'src.zip'
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    Write-Info 'Downloading repository archive...'
    $url = 'https://github.com/ratuuul/mpv-redesigned/archive/refs/heads/main.zip'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

    Expand-Archive -Path $zip -DestinationPath $root -Force
    $extracted = Get-ChildItem $root -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'config') } |
        Select-Object -First 1

    if (-not $extracted) { throw 'Could not locate the config folder inside the downloaded archive.' }
    return $extracted.FullName
}

# ---------------------------------------------------------------------------
#  2. mpv
# ---------------------------------------------------------------------------
function Find-Mpv {
    foreach ($name in @('mpv.com', 'mpv')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $local = Join-Path $env:LOCALAPPDATA 'mpv\mpv.com'
    if (Test-Path $local) { return $local }
    return $null
}

function Install-Mpv {
    <#
        Order of preference:
          1. scoop, if present (fast, keeps mpv updatable)
          2. direct download of the latest official Windows build

        winget is deliberately not used: the package id is not stable and it
        has historically resolved to the wrong package.
    #>
    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoop) {
        Write-Info 'scoop detected - installing mpv with scoop'
        Invoke-Action 'scoop install mpv' { & scoop install mpv }
        $found = Find-Mpv
        if ($found) { return $found }
        Write-Warn 'scoop install did not expose mpv on PATH yet; falling back to a direct download.'
    }

    Write-Info 'Downloading the latest official mpv build...'
    $api = 'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest'
    $headers = @{ 'User-Agent' = 'mpv-redesigned-installer' }
    $release = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 60

    # Prefer the plain x86_64 build: the "-v3" variants require AVX2 and will
    # crash on older CPUs.
    $asset = $release.assets |
        Where-Object { $_.name -match '^mpv-x86_64-\d{8}-git-[0-9a-f]+\.7z$' } |
        Select-Object -First 1
    if (-not $asset) { throw 'Could not find a suitable mpv release asset.' }

    $target = Join-Path $env:LOCALAPPDATA 'mpv'
    $archive = Join-Path $env:TEMP $asset.name

    Invoke-Action "download $($asset.name)" {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive -UseBasicParsing
    }
    Invoke-Action "extract to $target" {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        $sevenZip = @(
            'C:\Program Files\7-Zip\7z.exe',
            'C:\Program Files (x86)\7-Zip\7z.exe',
            (Join-Path $env:USERPROFILE 'scoop\apps\7zip\current\7z.exe')
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $sevenZip) {
            $cmd = Get-Command 7z -ErrorAction SilentlyContinue
            if ($cmd) { $sevenZip = $cmd.Source }
        }

        if ($sevenZip) {
            & $sevenZip x -y "-o$target" $archive | Out-Null
        } else {
            # Windows ships bsdtar, which reads 7z through libarchive.
            & tar -xf $archive -C $target
        }
    }

    # Expose it on PATH for future shells.
    if (-not $DryRun) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$target*") {
            [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $target), 'User')
            Write-Info "Added $target to the user PATH (open a new terminal to pick it up)."
        }
        $env:Path = $env:Path + ';' + $target
    }

    return (Find-Mpv)
}

# ---------------------------------------------------------------------------
#  3. yt-dlp
# ---------------------------------------------------------------------------
function Install-YtDlp([string] $Destination) {
    $exe = Join-Path $Destination 'yt-dlp.exe'
    if (Test-Path $exe) {
        Write-Ok 'yt-dlp already present'
        return
    }
    if (-not $DryRun) { Write-Info 'Downloading yt-dlp...' }
    Invoke-Action 'download yt-dlp.exe' {
        $url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    }
}

# ---------------------------------------------------------------------------
#  4. Deploy the configuration
# ---------------------------------------------------------------------------
function Backup-Config([string] $Path) {
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Path-backup-$stamp"
    Write-Info "Backing up $Path -> $backup"
    Invoke-Action "backup existing configuration" { Move-Item -LiteralPath $Path -Destination $backup }
    return $backup
}

function Deploy-Config([string] $Source, [string] $Destination, [string] $BackupPath) {
    Invoke-Action "create $Destination" {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    }
    Invoke-Action "copy configuration to $Destination" {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        # $Source is already the config directory; copy its contents.
        #
        # Runtime state is never deployed. `mpv.log` and `recent.json` are
        # personal: a log holds the machine's own paths, and the recent list
        # holds a playback history with local file names. Shipping them into
        # a fresh install would leak the author's machine to the user, and
        # would overwrite the user's own history on a re-install.
        $skip = @('cache', 'mpv.log', 'recent.json', 'watch_later', 'screenshots', 'subs', 'subtitles', 'temp', 'state')
        Get-ChildItem -LiteralPath $Source -Force | Where-Object {
            $skip -notcontains $_.Name
        } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
        }
    }

    # Directories the player and the skin expect to exist.
    #
    # `subtitles` is not optional: the uosc skin probes the download folder by
    # writing a file into it, and it logs
    # "open_subtitle_downloader: subtitles_directory not writable" and refuses
    # to open the downloader when the folder is missing.
    foreach ($dir in @('cache', 'screenshots', 'subtitles')) {
        Invoke-Action "create $dir" {
            New-Item -ItemType Directory -Force -Path (Join-Path $Destination $dir) | Out-Null
        }
    }

    if (-not $NoHistory -and $BackupPath) {
        foreach ($keep in @('watch_later', 'screenshots')) {
            $from = Join-Path $BackupPath $keep
            if (Test-Path $from) {
                Write-Info "Carrying over $keep"
                Invoke-Action "restore $keep" {
                    Copy-Item -Path $from -Destination (Join-Path $Destination $keep) -Recurse -Force
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
#  5. Verify
# ---------------------------------------------------------------------------
function Test-NodeRuntime {
    <#
        yt-dlp only auto-enables its `deno` JS runtime. Without an enabled
        runtime YouTube's signature and `n` challenges fail, it falls back to
        SABR streaming and the format list comes back unusable. mpv.conf pins
        js-runtimes=node, so Node has to exist - but the installer will not
        install it, because that is a bigger decision than deploying a config.
    #>
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { Write-Ok "Found $($node.Source)"; return }

    Write-Warn 'node was not found on PATH.'
    Write-Info 'YouTube still plays, but the higher-quality formats need a JS runtime:'
    Write-Info 'mpv.conf sets js-runtimes=node, and without Node, yt-dlp cannot'
    Write-Info 'solve YouTube''s signature challenge, so formats come back empty.'
    Write-Info 'Install it with:  winget install OpenJS.NodeJS.LTS'
    Write-Info '           or:    scoop install nodejs-lts'
    Write-Info 'Then open a NEW terminal and start mpv again.'
}

function Test-Config([string] $Mpv, [string] $ConfigDir) {
    if ($DryRun) {
        Write-Info 'would: start mpv once with --vo=null --ao=null and check the log'
        return
    }
    if (-not $Mpv) { Write-Warn 'mpv not found - skipping the parse check.'; return }

    Write-Info 'Starting mpv once to check that the configuration parses...'
    $log = Join-Path $env:TEMP ('mpv-parse-' + [guid]::NewGuid().ToString('N') + '.log')
    $mpvArgs = @(
        '--no-terminal', '--idle=yes', '--vo=null', '--ao=null',
        "--config-dir=$ConfigDir", "--log-file=$log", '--msg-level=all=warn',
        # bg.lua starts downloading an idle photo 1.5 s after startup, which
        # both hits the network and writes to cache/ during a verification run.
        # This per-run override disables it without changing the deployed config.
        '--script-opts=bg-enabled=no'
    )

    $proc = Start-Process -FilePath $Mpv -ArgumentList $mpvArgs -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 4
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }

    if (-not (Test-Path $log)) { Write-Warn 'No log produced - could not verify.'; return }

    # Only real failures count. `--msg-level=all=warn` does not suppress the
    # debug lines that mpv emits while it loads scripts, and those include
    # harmless "script-opts/<x>.conf not found" messages for every bundled
    # script that has no options file. Matching those made a clean install fail.
    $problems = Get-Content $log | Where-Object {
        $_ -match '\[e\]' -or
        $_ -match 'Error parsing option' -or
        $_ -match 'Invalid value' -or
        $_ -match 'Lua error'
    }
    if ($problems) {
        Write-Err 'The configuration produced problems:'
        $problems | Select-Object -First 10 | ForEach-Object { Write-Host "            $_" -ForegroundColor Red }
        Write-Info "Full log: $log"
        return $false
    }

    Write-Ok 'Configuration parsed cleanly'
    return $true
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  mpv-redesigned' -ForegroundColor White
Write-Host '  ------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  A tuned mpv: Liquid Glass skin, full-quality video stack,'
Write-Host '  YouTube quality picker, subtitles, downloads and more.'
Write-Host ''

Assert-Windows
Set-ModernTls

if ($DryRun) { Write-Warn 'DRY RUN - nothing will be changed.' }

# Refuse to stomp a running player: file locks and lost state. A running mpv
# only matters when the directory being replaced is the one it is using, so a
# `-InstallDir` scratch run is allowed while another player is open.
$running = Get-Process -Name 'mpv' -ErrorAction SilentlyContinue
if ($running -and -not $DryRun) {
    $defaultConfigDir = (Join-Path $env:APPDATA 'mpv').TrimEnd('\')
    if ($InstallDir.TrimEnd('\') -ieq $defaultConfigDir) {
        Write-Err "mpv is running ($($running.Count) process(es)). Close it and run the installer again."
        Write-Info 'Its configuration files are in use; replacing them now would lose resume state.'
        exit 1
    }
    Write-Warn "mpv is running ($($running.Count) process(es)), but the target is a custom -InstallDir."
    Write-Info "If that player was started with --config-dir=`"$InstallDir`", close it first."
}

Write-Step 'Locating the configuration payload'
$repo = Get-RepoRoot
$src  = Join-Path $repo 'config'
if (-not (Test-Path $src)) { throw "Configuration payload missing at $src" }
Write-Ok "Using $src"

$mpv = Find-Mpv
if (-not $ConfigOnly) {
    Write-Step 'mpv'
    if ($mpv) {
        Write-Ok "Found $mpv"
    } else {
        $mpv = Install-Mpv
        if ($mpv) { Write-Ok "Installed $mpv" } else { Write-Warn 'mpv was not installed automatically.' }
    }
} else {
    Write-Step 'mpv (skipped: -ConfigOnly)'
}

Write-Step 'Node.js (YouTube format support)'
Test-NodeRuntime

if ($InstallDir -and (Test-Path $InstallDir)) {
    if (-not $Force -and -not $DryRun) {
        Write-Host ''
        Write-Host "  A configuration already exists at:" -ForegroundColor Yellow
        Write-Host "    $InstallDir" -ForegroundColor Yellow
        $answer = Read-Host '  Back it up and replace it? [y/N]'
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host ''
            Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor DarkGray
            exit 0
        }
    }
}

$backup = $null
if ((Test-Path $InstallDir) -and -not $NoBackup) {
    Write-Step 'Backing up the existing configuration'
    $backup = Backup-Config $InstallDir
    if (-not $DryRun) { Write-Ok "Backup: $backup" }
} elseif (Test-Path $InstallDir) {
    Write-Step 'Backup (skipped: -NoBackup)'
    Write-Warn 'The existing configuration will be overwritten with no backup.'
}

Write-Step 'Deploying the configuration'
Deploy-Config -Source $src -Destination $InstallDir -BackupPath $backup
if (-not $DryRun) { Write-Ok "Deployed to $InstallDir" }

if (-not $ConfigOnly) {
    Write-Step 'yt-dlp'
    Install-YtDlp $InstallDir
}

Write-Step 'Verifying'
$parseOk = Test-Config -Mpv $mpv -ConfigDir $InstallDir
if ($parseOk -eq $false) {
    Write-Host ''
    Write-Err 'The files were deployed, but the configuration did not parse cleanly.'
    Write-Info 'Fix the errors listed above before using this install.'
    exit 1
}

Write-Host ''
Write-Host '  ------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
Write-Host '  Open a video:'
Write-Host '    mpv "%USERPROFILE%\Videos\something.mkv"'
Write-Host '    mpv "https://www.youtube.com/watch?v=..."'
Write-Host ''
Write-Host '  Handy keys:' -ForegroundColor White
Write-Host '    Ctrl+d          download the video you are watching'
Write-Host '    Alt+p           mini always-on-top player'
Write-Host '    F               YouTube quality / format picker'
Write-Host '    Alt+s           YouTube subtitle picker'
Write-Host '    Alt+o           search OpenSubtitles for this file'
Write-Host '    V / D           subtitle menu / download subtitles'
Write-Host '    Ctrl+Shift+K    next idle background photo'
Write-Host '    Ctrl+Shift+r    recent files'
Write-Host '    {  }  BS        slower / faster / normal speed'
Write-Host ''
Write-Host '  Full list: docs/KEYBINDINGS.md' -ForegroundColor DarkGray
if ($backup -and -not $DryRun) {
    Write-Host "  Your previous configuration is safe at:" -ForegroundColor DarkGray
    Write-Host "    $backup" -ForegroundColor DarkGray
}
if ($DryRun) {
    Write-Host '  Dry run: nothing was changed.' -ForegroundColor Yellow
}
Write-Host ''
