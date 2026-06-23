param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

if (-not (Test-Path $ConfigPath)) { Write-Error "config.json not found: $ConfigPath"; exit 1 }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$credFolder = Split-Path $ConfigPath

Write-Host "PBIRS Monitor - Credential Setup" -ForegroundColor Yellow
Write-Host "Credentials are encrypted with your Windows account key (DPAPI).`n"

Write-Host "=== PBIRS Portal ===" -ForegroundColor Cyan
$httpCred = Get-Credential -Message "PBIRS Portal credentials"
$httpCred | Export-Clixml -Path (Join-Path $credFolder "cred_http.xml") -Force
Write-Host "Saved." -ForegroundColor Green

Write-Host "`n=== Oracle ($($config.oracleTnsAlias)) ===" -ForegroundColor Cyan
$oraCred = Get-Credential -Message "Oracle credentials"
$oraCred | Export-Clixml -Path (Join-Path $credFolder "cred_oracle.xml") -Force
Write-Host "Saved." -ForegroundColor Green

Write-Host "`nDone. Run monitor.ps1 to test." -ForegroundColor Green
