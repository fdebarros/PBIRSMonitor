@echo off
REM launcher.cmd
REM Joga na pasta Startup do Windows (shell:startup) sob a conta do servico.
REM Roda o monitor em loop infinito, com intervalo lido do config.json.
REM Janela minimizada, sem interacao.

setlocal

set SCRIPT_DIR=%~dp0
set MONITOR=%SCRIPT_DIR%monitor.ps1
set CONFIG=%SCRIPT_DIR%config.json

REM Le o intervalo do config.json via PowerShell (evita dependencia de jq)
for /f %%i in ('powershell -NoProfile -Command "(Get-Content '%CONFIG%' | ConvertFrom-Json).checkIntervalSeconds"') do set INTERVAL=%%i

:loop
powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "%MONITOR%" -ConfigPath "%CONFIG%"
timeout /t %INTERVAL% /nobreak >nul
goto loop