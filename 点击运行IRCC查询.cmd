@echo off
REM IRCC Tracker Safe Windows v2.4.1 launcher
REM Ensures UTF-8 console output and runs the PowerShell script next to this file.
chcp 65001 >nul
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_FILE=%SCRIPT_DIR%IRCC_Status_Check.ps1"

REM Prefer PowerShell 7 (pwsh) if available; otherwise fall back to Windows PowerShell.
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS_FILE%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_FILE%"
)

echo.
echo Press any key to close this window...
pause >nul
endlocal
