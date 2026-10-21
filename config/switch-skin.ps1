<#
    switch-skin - swap the mpv OSC skin.

    Usage:
        switch-skin.cmd                 (interactive menu)
        switch-skin.cmd modernz
        switch-skin.cmd liquidglass

    Why folders are moved instead of just pointing at a different file:
    mpv only puts a script's own directory on the Lua module path when the
    script lives in scripts/. The Liquid Glass skin needs `require('lib/std')`
    and friends, so it has to sit in scripts/uosc/ to work at all.

    So the active skin lives in scripts/ and the inactive one is parked in
    skins/. This script swaps them.

    Restart mpv afterwards.
#>

param(
    [Parameter(Position = 0)]
    [string]$Skin = ""
)

$ErrorActionPreference = "Stop"
$cfg     = Join-Path $env:APPDATA "mpv"
$scripts = Join-Path $cfg "scripts"
$skins   = Join-Path $cfg "skins"

# name -> (folder inside scripts\, folder inside skins\)
$map = @{
    "liquidglass" = @{ live = "uosc";          parked = "liquid-glass\uosc" }
    "modernz"     = @{ live = "modernz";       parked = "modernz" }
}

function Show-Menu {
    Write-Host ""
    Write-Host "  Available skins:" -ForegroundColor Cyan
    Write-Host "    liquidglass  - uosc Liquid Glass fork (glass, centred overlays, speedometer)"
    Write-Host "    modernz      - ModernZ (maintained, menus, thumbnails, layouts)"
    Write-Host ""
    $choice = Read-Host "  Skin [liquidglass]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "liquidglass" }
    return $choice.Trim().ToLower()
}

if ([string]::IsNullOrWhiteSpace($Skin)) { $Skin = Show-Menu }
$Skin = $Skin.Trim().ToLower()

if (-not $map.ContainsKey($Skin)) {
    Write-Host "  Unknown skin '$Skin'. Try: liquidglass | modernz" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $scripts)) {
    Write-Host "  mpv scripts dir not found at $scripts" -ForegroundColor Red
    exit 1
}

# Park every skin that is currently live, then bring the wanted one out.
foreach ($name in $map.Keys) {
    $info = $map[$name]
    $live = Join-Path $scripts $info.live
    $parked = Join-Path $skins $info.parked

    if (Test-Path $live) {
        New-Item -ItemType Directory -Force (Split-Path $parked -Parent) | Out-Null
        if (Test-Path $parked) { Remove-Item $parked -Recurse -Force }
        Move-Item $live $parked -Force
        Write-Host "  parked  $($info.live)" -ForegroundColor DarkGray
    }
}

$target = $map[$Skin]
$from   = Join-Path $skins $target.parked
$to     = Join-Path $scripts $target.live

if (-not (Test-Path $from)) {
    Write-Host "  Could not find $from" -ForegroundColor Red
    exit 1
}

Move-Item $from $to -Force
Write-Host "  active  $($target.live)   ($Skin)" -ForegroundColor Green
Write-Host ""
Write-Host "  Restart mpv to apply." -ForegroundColor Yellow
Write-Host ""
