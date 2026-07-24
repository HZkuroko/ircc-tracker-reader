@echo off
chcp 65001 >nul
cd /d "%~dp0"

where pwsh.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "PS_EXE=pwsh.exe"
    echo [Info] Using PowerShell 7 for modern HTTP compatibility.
) else (
    set "PS_EXE=powershell.exe"
    echo [Info] PowerShell 7 was not found; using Windows PowerShell 5.1.
)

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0IRCC_Status_Check.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXIT_CODE%
