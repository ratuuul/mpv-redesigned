<#
.SYNOPSIS
    Removes the mpv-redesigned configuration.

.DESCRIPTION
    By default this moves %APPDATA%\mpv to a timestamped backup folder, so
    nothing is lost. Use -Purge to delete it outright.

    mpv and yt-dlp are left in place: mpv is usually installed through a
    package manager, and yt-dlp lives inside the config folder so it goes
    with it.

.PARAMETER InstallDir
    Configuration directory to remove. Defaults to %APPDATA%\mpv.

.PARAMETER Purge
    Delete the configuration instead of backing it up.

.EXAMPLE
    .\uninstall.ps1
    Move the configuration to a backup folder.

.EXAMPLE
    .\uninstall.ps1 -Purge
    Delete it permanently.
#>

[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:APPDATA 'mpv'),
    [switch] $Purge
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  mpv-redesigned - uninstall' -ForegroundColor White
Write-Host '  ------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path $InstallDir)) {
    Write-Host "  Nothing to remove: $InstallDir does not exist." -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

$running = Get-Process -Name 'mpv' -ErrorAction SilentlyContinue
$defaultConfigDir = (Join-Path $env:APPDATA 'mpv').TrimEnd('\')
if ($running -and $InstallDir.TrimEnd('\') -ieq $defaultConfigDir) {
    Write-Host '  mpv is running. Close it first.' -ForegroundColor Red
    exit 1
}
if ($running) {
    Write-Host "  Note: $($running.Count) mpv process(es) are running, but not against this directory." -ForegroundColor DarkGray
}

if ($Purge) {
    $answer = Read-Host "  Delete $InstallDir permanently? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        exit 0
    }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "  Deleted $InstallDir" -ForegroundColor Green
} else {
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$InstallDir-backup-$stamp"
    Move-Item -LiteralPath $InstallDir -Destination $backup
    Write-Host "  Moved to $backup" -ForegroundColor Green
}

Write-Host ''
