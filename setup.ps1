# setup.ps1
# Roda UMA VEZ sob a conta que vai executar o servico.
# Salva as credenciais no Windows Credential Manager dessa conta.
# Nenhuma senha e gravada em disco.

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

function Save-Credential {
    param([string]$Target, [string]$Label)

    Write-Host "`n=== $Label ===" -ForegroundColor Cyan
    $user = Read-Host "Usuario"
    $pass = Read-Host "Senha" -AsSecureString

    # Converte pra BSTR pra usar na Win32 API via cmdkey
    $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    )

    # cmdkey armazena no Credential Manager da conta atual
    $result = cmdkey /add:$Target /user:$user /pass:$plainPass
    $plainPass = $null  # limpa da memoria imediatamente

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Credencial '$Target' salva com sucesso." -ForegroundColor Green
    } else {
        Write-Host "Erro ao salvar '$Target'." -ForegroundColor Red
        Write-Host $result
    }
}

if (-not (Test-Path $ConfigPath)) {
    Write-Host "config.json nao encontrado em: $ConfigPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json

Write-Host "`nPBIRS Monitor - Setup de Credenciais" -ForegroundColor Yellow
Write-Host "As credenciais serao armazenadas no Windows Credential Manager"
Write-Host "desta conta de usuario. Apenas esta conta consegue le-las.`n"

# Credencial HTTP (PBIRS portal)
Save-Credential -Target $config.credentialTarget -Label "PBIRS Portal ($($config.url))"

# Credencial Oracle
Save-Credential -Target $config.oracleCredentialTarget -Label "Oracle ($($config.oracleTnsAlias))"

Write-Host "`nSetup concluido. Execute monitor.ps1 para iniciar o monitor." -ForegroundColor Green