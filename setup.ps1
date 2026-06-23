param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

function Save-Credential([string]$Target, [string]$Label) {
    Write-Host "`n=== $Label ===" -ForegroundColor Cyan
    $user = Read-Host "Username"
    $pass = Read-Host "Password" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
    cmdkey /add:$Target /user:$user /pass:$plain | Out-Null
    $plain = $null
    if ($LASTEXITCODE -eq 0) { Write-Host "Saved '$Target'." -ForegroundColor Green }
    else                      { Write-Host "Failed to save '$Target'." -ForegroundColor Red }
}

if (-not (Test-Path $ConfigPath)) { Write-Error "config.json not found: $ConfigPath"; exit 1 }
$config = Get-Content $ConfigPath | ConvertFrom-Json

Write-Host "PBIRS Monitor - Credential Setup" -ForegroundColor Yellow
Write-Host "Credentials are stored in Windows Credential Manager for this account only.`n"

Save-Credential $config.credentialTarget       "PBIRS Portal ($($config.url))"
Save-Credential $config.oracleCredentialTarget "Oracle ($($config.oracleTnsAlias))"

Write-Host "`nDone. Run monitor.ps1 start the Monitor." -ForegroundColor Green
