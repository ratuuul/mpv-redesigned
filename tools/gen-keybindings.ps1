<#
.SYNOPSIS
    Regenerates docs/KEYBINDINGS.md from config/input.conf.

.DESCRIPTION
    The key binding reference is generated, never hand-written, so it cannot
    drift away from the configuration that actually runs.

    Two sources are merged:

      1. config/input.conf        parsed line by line, with the section
                                  comments and the per-binding comments used as
                                  the headings and descriptions.
      2. config/scripts/*.lua     scanned for literal mp.add_key_binding()
                                  registrations. A small static table covers the
                                  few scripts that bind a key through a variable
                                  (webm.lua's `keybind` option).

    Bindings that appear in both places are listed once, under their
    input.conf section, because that is the file a user edits.

.PARAMETER Check
    Do not write anything. Exit 1 if docs/KEYBINDINGS.md is out of date, which
    is what CI runs.

.EXAMPLE
    pwsh -File tools/gen-keybindings.ps1

.EXAMPLE
    pwsh -File tools/gen-keybindings.ps1 -Check
#>

[CmdletBinding()]
param(
    [switch] $Check
)

$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
# Nested Join-Path calls: the three-argument form needs PowerShell 6, and this
# runs under Windows PowerShell 5.1 locally and pwsh on the Linux CI runner.
$inputConf  = Join-Path (Join-Path $root 'config') 'input.conf'
$scriptsDir = Join-Path (Join-Path $root 'config') 'scripts'
$outFile    = Join-Path (Join-Path $root 'docs') 'KEYBINDINGS.md'

if (-not (Test-Path $inputConf)) { throw "input.conf not found at $inputConf" }

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
function Format-Inline([string] $s) {
    # Markdown tables break on an unescaped pipe.
    return ($s -replace '\|', '\|').Trim()
}

function Get-HumanCommand([string] $command) {
    # Last-resort description when a binding has no comment above it.
    $c = $command -replace '^repeatable\s+', ''
    if ($c -match 'nav-seek-percent\s+(\d+)$') {
        return ('jump to ' + $Matches[1] + ' % of the duration')
    }
    if ($c -match '^apply-profile\s+(\S+)$') {
        return ('apply the `' + $Matches[1] + '` profile')
    }
    if ($c -match '^script-message-to\s+(\S+)\s+(.+)$') {
        return ('message `' + $Matches[2] + '` to the `' + $Matches[1] + '` script')
    }
    if ($c -match '^script-binding\s+(.+)$') { return ('runs the `' + $Matches[1] + '` command') }
    return ('`' + $c + '`')
}

function Get-NormalKey([string] $key) {
    # mpv key names are case-insensitive for the modifier part; shifted letters
    # collapse (Ctrl+Shift+S arrives as Ctrl+s), so compare loosely.
    return ($key.ToLowerInvariant() -replace '\s', '')
}

# Keys that a script registers through a variable or an option default, and
# therefore cannot be found by scanning for a literal string.
$dynamic = @(
    [pscustomobject]@{
        Key    = 'W'
        Script = 'webm.lua'
        Name   = 'display-webm-encoder'
        Note   = 'default of the `keybind` option in `script-opts/webm.conf`'
    }
)

# ---------------------------------------------------------------------------
#  Pass 1: input.conf
# ---------------------------------------------------------------------------
$lines    = Get-Content -LiteralPath $inputConf -Encoding UTF8
$sections = New-Object System.Collections.ArrayList
$current  = $null
$pending  = New-Object System.Collections.ArrayList
$inHeader = $true

# Section banners look like:
#   # ---------------- name ----
#   # ================ name ==
# The leading '#' has already been stripped before this runs.
$headerRe = '^[=\-]{3,}\s*(?<name>.+?)\s*[=\-]{2,}\s*$'

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()

    if ($line -eq '') { $pending.Clear(); continue }

    if ($line.StartsWith('#')) {
        $body = $line.TrimStart('#').Trim()

        if ($body -match $headerRe) {
            $name = $Matches['name'].Trim()
            # The banner lines at the top of the file produce an empty name.
            if ($name -ne '' -and $name -match '[A-Za-z]') {
                $current = [pscustomobject]@{
                    Name     = $name
                    Bindings = New-Object System.Collections.ArrayList
                }
                [void]$sections.Add($current)
                $inHeader = $false
            }
            $pending.Clear()
            continue
        }

        if (-not $inHeader) {
            [void]$pending.Add($body)
            if ($pending.Count -gt 3) { $pending.RemoveAt(0) }
        }
        continue
    }

    # Not a comment and not blank: a binding.
    if ($null -eq $current) {
        $current = [pscustomobject]@{
            Name     = 'General'
            Bindings = New-Object System.Collections.ArrayList
        }
        [void]$sections.Add($current)
    }

    $body = $line
    $trailing = ''
    $hash = $body.IndexOf('#')
    if ($hash -gt 0 -and $body[$hash - 1] -eq ' ') {
        $trailing = $body.Substring($hash + 1).Trim()
        $body = $body.Substring(0, $hash).Trim()
    }

    $parts = $body -split '\s+', 2
    $key = $parts[0]
    $cmd = ''
    if ($parts.Count -gt 1) { $cmd = $parts[1].Trim() }

    if ($trailing -ne '') {
        $desc = $trailing
    } elseif ($pending.Count -gt 0) {
        # The first line of the comment block is the summary; the lines below it
        # are usually caveats. Using the summary keeps the table readable and
        # the full note still lives in input.conf.
        $desc = $pending[0] -replace '\s+', ' '
    } else {
        $desc = Get-HumanCommand $cmd
    }

    if ($desc -match '^NOTE:') {
        if ($pending.Count -gt 1) { $desc = $pending[1] -replace '\s+', ' ' }
        else { $desc = Get-HumanCommand $cmd }
    }

    [void]$current.Bindings.Add([pscustomobject]@{
        Key  = $key
        Cmd  = $cmd
        Desc = $desc
    })
    $pending.Clear()
}

# ---------------------------------------------------------------------------
#  Pass 2: what the scripts register themselves
# ---------------------------------------------------------------------------
$registered = New-Object System.Collections.ArrayList

if (Test-Path $scriptsDir) {
    foreach ($file in (Get-ChildItem -LiteralPath $scriptsDir -Filter '*.lua' -File | Sort-Object Name)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $pattern = 'add_(?:forced_)?key_binding\s*\(\s*[''"]([^''"]+)[''"]\s*,\s*[''"]([^''"]+)[''"]'
        foreach ($m in [regex]::Matches($text, $pattern)) {
            [void]$registered.Add([pscustomobject]@{
                Key    = $m.Groups[1].Value
                Script = $file.Name
                Name   = $m.Groups[2].Value
                Note   = ''
            })
        }
    }
}
foreach ($d in $dynamic) { [void]$registered.Add($d) }

# ---------------------------------------------------------------------------
#  Render
# ---------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
function Add-Line([string] $text) { [void]$sb.AppendLine($text) }

$bindingsSeen = @{}
foreach ($s in $sections) {
    foreach ($b in $s.Bindings) { $bindingsSeen[(Get-NormalKey $b.Key)] = $true }
}

Add-Line '# Key bindings'
Add-Line ''
Add-Line '<!-- Generated by tools/gen-keybindings.ps1 from config/input.conf. Do not edit by hand. -->'
Add-Line ''
Add-Line 'Everything here comes from [`config/input.conf`](../config/input.conf), plus the'
Add-Line 'keys that the bundled scripts register for themselves. Anything not listed'
Add-Line 'keeps the default mpv binding - run `mpv --input-cmdlist` for the full set,'
Add-Line 'or press `g-b` in a running player to see the live list.'
Add-Line ''
Add-Line 'Navigation is routed through `scripts/nav_shim.lua`, which detects the active'
Add-Line 'skin. With Liquid Glass you get its centred macOS-style seek/volume/speed'
Add-Line 'overlays; with ModernZ the same keys perform the action natively and the skin'
Add-Line 'draws its own feedback. The keymap does not change when you switch skins.'
Add-Line ''

foreach ($s in $sections) {
    if ($s.Bindings.Count -eq 0) { continue }
    Add-Line ("## " + $s.Name.Substring(0, 1).ToUpperInvariant() + $s.Name.Substring(1))
    Add-Line ''
    Add-Line '| Key | Action | mpv command |'
    Add-Line '|---|---|---|'
    foreach ($b in $s.Bindings) {
        $k = Format-Inline $b.Key
        $d = Format-Inline $b.Desc
        $c = Format-Inline $b.Cmd
        Add-Line "| ``$k`` | $d | ``$c`` |"
    }
    Add-Line ''
}

$extra = @()
foreach ($r in $registered) {
    if ($bindingsSeen.ContainsKey((Get-NormalKey $r.Key))) { continue }
    $extra += $r
}

if ($extra.Count -gt 0) {
    Add-Line '## Registered by the scripts themselves'
    Add-Line ''
    Add-Line 'These keys are registered at load time by the script named here, so they'
    Add-Line 'are not in `input.conf`. Rebind them by editing the script option or the'
    Add-Line '`input.conf` entry noted below.'
    Add-Line ''
    Add-Line '| Key | Script | Binding | Notes |'
    Add-Line '|---|---|---|---|'
    foreach ($e in ($extra | Sort-Object Key)) {
        $k = Format-Inline $e.Key
        $n = Format-Inline $e.Note
        $base = $e.Script -replace '\.lua$', ''
        Add-Line "| ``$k`` | ``$($e.Script)`` | ``$base/$($e.Name)`` | $n |"
    }
    Add-Line ''
}

Add-Line '## Script bindings used in `input.conf`'
Add-Line ''
Add-Line 'For reference, these are the `script-binding` targets the keymap calls. They'
Add-Line 'are provided by the scripts in `config/scripts/`, not by mpv itself.'
Add-Line ''
Add-Line '| Binding | Provided by |'
Add-Line '|---|---|'
$providers = [ordered]@{
    'uosc/'         = 'Liquid Glass skin (`scripts/uosc`)'
    'quality_menu/' = '`scripts/quality-menu.lua`'
    'recentmenu/'   = '`scripts/recentmenu.lua`'
    'ytsubs/'       = '`scripts/ytsubs.lua`'
    'bg/'           = '`scripts/bg.lua`'
    'select/'       = 'mpv''s bundled `select.lua`'
    'stats/'        = 'mpv''s bundled `stats.lua`'
}
$used = @{}
foreach ($s in $sections) {
    foreach ($b in $s.Bindings) {
        if ($b.Cmd -match 'script-binding\s+(\S+)') { $used[$Matches[1]] = $true }
    }
}
foreach ($name in ($used.Keys | Sort-Object)) {
    $from = 'unknown'
    foreach ($prefix in $providers.Keys) {
        if ($name.StartsWith($prefix)) { $from = $providers[$prefix]; break }
    }
    Add-Line "| ``$name`` | $from |"
}
Add-Line ''

$text = $sb.ToString()

if ($Check) {
    if (-not (Test-Path $outFile)) {
        Write-Host 'docs/KEYBINDINGS.md is missing. Run tools/gen-keybindings.ps1.' -ForegroundColor Red
        exit 1
    }
    $existing = [IO.File]::ReadAllText($outFile)
    $a = $existing -replace "`r`n", "`n"
    $b = $text     -replace "`r`n", "`n"
    if ($a -ne $b) {
        Write-Host 'docs/KEYBINDINGS.md is out of date. Run tools/gen-keybindings.ps1 and commit the result.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'docs/KEYBINDINGS.md is up to date.' -ForegroundColor Green
    exit 0
}

$dir = Split-Path -Parent $outFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[IO.File]::WriteAllText($outFile, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outFile" -ForegroundColor Green
