@echo off
setlocal

echo Stopping PBIRS Monitor...

wmic process where "name='powershell.exe' and commandline like '%%monitor.ps1%%'" delete >nul 2>&1
wmic process where "name='cmd.exe' and commandline like '%%PBIRSMonitor-Launcher%%'" delete >nul 2>&1

echo Done.
pause
