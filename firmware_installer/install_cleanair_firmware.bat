@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_cleanair_firmware.ps1"
echo.
pause
