@echo off
REM  switch-skin.cmd - swap the mpv OSC skin.
REM  Usage:  switch-skin.cmd [modernz|liquidglass]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch-skin.ps1" %*
pause
