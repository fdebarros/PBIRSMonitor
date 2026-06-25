@echo off
setlocal

set SCRIPT_DIR=%~dp0
set MONITOR=%SCRIPT_DIR%monitor.ps1
set CONFIG=%SCRIPT_DIR%config.json

for /f %%i in ('powershell -NoProfile -File "%SCRIPT_DIR%get-interval.ps1"') do set INTERVAL=%%i

:loop
powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "%MONITOR%" -ConfigPath "%CONFIG%"
timeout /t %INTERVAL% /nobreak >nul
goto loop
