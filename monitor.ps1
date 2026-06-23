# monitor.ps1
# PBIRS Synthetic Monitor - one-shot
# Chamado pelo launcher.cmd em loop. Roda uma vez, loga, sai.

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

# ---------------------------------------------------------------------------
# Funcoes
# ---------------------------------------------------------------------------

function Get-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) { Write-Error "config.json nao encontrado: $Path"; exit 1 }
    return Get-Content $Path | ConvertFrom-Json
}

function Get-StoredCredential {
    param([string]$Target)
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class CredMan {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct CREDENTIAL {
        public uint Flags, Type;
        public string TargetName, Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias, UserName;
    }

    public static string[] Read(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1, 0, out ptr)) return null;
        try {
            var cred = Marshal.PtrToStructure<CREDENTIAL>(ptr);
            string password = Marshal.PtrToStringUni(cred.CredentialBlob, (int)(cred.CredentialBlobSize / 2));
            return new string[] { cred.UserName, password };
        } finally { CredFree(ptr); }
    }
}
'@ -ErrorAction SilentlyContinue

    $result = [CredMan]::Read($Target)
    if ($null -eq $result) { throw "Credencial '$Target' nao encontrada. Execute setup.ps1 primeiro." }
    return $result
}

function Write-Log {
    param([string]$LogFolder, [string]$Level, [string]$Message)
    if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $date      = Get-Date -Format "yyyy-MM-dd"
    $line      = "$timestamp [$Level] $Message"
    Add-Content -Path (Join-Path $LogFolder "monitor_$date.log") -Value $line -Encoding UTF8
}

function Remove-OldLogs {
    param([string]$LogFolder, [int]$RetentionDays)
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogFolder -Filter "monitor_*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
}

function Test-Url {
    param([string]$Url, [string]$User, [string]$Pass)
    try {
        $cred     = New-Object System.Management.Automation.PSCredential(
                        $User, (ConvertTo-SecureString $Pass -AsPlainText -Force))
        $response = Invoke-WebRequest -Uri $Url -Credential $cred -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return @{ OK = $true; Status = $response.StatusCode }
    } catch {
        $code = $_.Exception.Response.StatusCode.Value__
        return @{ OK = $false; Status = $(if ($code) { $code } else { "ERR" }); Error = $_.Exception.Message }
    }
}

function Test-OracleConnection {
    param([string]$TnsAlias, [string]$User, [string]$Pass)
    try {
        # Tenta ODP.NET Managed
        $odpPaths = @(
            "${env:ProgramFiles}\Oracle\ODAC\odp.net\managed\common\Oracle.ManagedDataAccess.dll",
            "${env:ProgramFiles(x86)}\Oracle\ODAC\odp.net\managed\common\Oracle.ManagedDataAccess.dll"
        )
        foreach ($p in $odpPaths) { if (Test-Path $p) { Add-Type -Path $p; break } }

        $conn = New-Object Oracle.ManagedDataAccess.Client.OracleConnection(
            "User Id=$User;Password=$Pass;Data Source=$TnsAlias;Connection Timeout=15;")
        $conn.Open(); $conn.Close(); $conn.Dispose()
        return @{ OK = $true }
    } catch {
        # Fallback ODBC
        try {
            $c = New-Object System.Data.Odbc.OdbcConnection("DSN=$TnsAlias;UID=$User;PWD=$Pass;")
            $c.ConnectionTimeout = 15; $c.Open(); $c.Close(); $c.Dispose()
            return @{ OK = $true }
        } catch {
            return @{ OK = $false; Error = $_.Exception.Message }
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$config = Get-Config -Path $ConfigPath

try {
    $httpCreds   = Get-StoredCredential -Target $config.credentialTarget
    $oracleCreds = Get-StoredCredential -Target $config.oracleCredentialTarget
} catch {
    Write-Log $config.logFolder "ERROR" "Credenciais: $($_.Exception.Message)"
    exit 1
}

$urlResult = Test-Url -Url $config.url -User $httpCreds[0] -Pass $httpCreds[1]
if ($urlResult.OK) {
    Write-Log $config.logFolder "OK"    "URL=$($config.url) STATUS=$($urlResult.Status)"
} else {
    Write-Log $config.logFolder "ERROR" "URL=$($config.url) STATUS=$($urlResult.Status) MSG=$($urlResult.Error)"
}

$oraResult = Test-OracleConnection -TnsAlias $config.oracleTnsAlias -User $oracleCreds[0] -Pass $oracleCreds[1]
if ($oraResult.OK) {
    Write-Log $config.logFolder "OK"    "ORACLE TNS=$($config.oracleTnsAlias) CONNECT=OK"
} else {
    Write-Log $config.logFolder "ERROR" "ORACLE TNS=$($config.oracleTnsAlias) CONNECT=FAIL MSG=$($oraResult.Error)"
}

Remove-OldLogs -LogFolder $config.logFolder -RetentionDays $config.logRetentionDays