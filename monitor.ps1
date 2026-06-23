param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class CredMan {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct CREDENTIAL {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    public static string[] Read(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1, 0, out ptr)) return null;
        try {
            CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
            string password = Marshal.PtrToStringUni(cred.CredentialBlob, (int)(cred.CredentialBlobSize / 2));
            return new string[] { cred.UserName, password };
        } finally {
            CredFree(ptr);
        }
    }
}
'@ -ErrorAction SilentlyContinue

function Get-StoredCredential([string]$Target) {
    $result = [CredMan]::Read($Target)
    if ($null -eq $result) { throw "Credential '$Target' not found. Run setup.ps1 first." }
    return $result
}

function Write-Log([string]$LogFolder, [string]$Level, [string]$Message) {
    if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $file = Join-Path $LogFolder "monitor_$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $file -Value "$ts [$Level] $Message" -Encoding UTF8
}

function Remove-OldLogs([string]$LogFolder, [int]$RetentionDays) {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogFolder -Filter "monitor_*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
}

function Test-Url([string]$Url, [string]$User, [string]$Pass) {
    try {
        $cred = New-Object System.Management.Automation.PSCredential(
            $User, (ConvertTo-SecureString $Pass -AsPlainText -Force))
        $r = Invoke-WebRequest -Uri $Url -Credential $cred -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return @{ OK = $true; Status = $r.StatusCode }
    } catch {
        $code = $_.Exception.Response.StatusCode.Value__
        return @{ OK = $false; Status = $(if ($code) { $code } else { "ERR" }); Error = $_.Exception.Message }
    }
}

function Test-Oracle([string]$TnsAlias, [string]$User, [string]$Pass) {
    try {
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
        try {
            $c = New-Object System.Data.Odbc.OdbcConnection("DSN=$TnsAlias;UID=$User;PWD=$Pass;")
            $c.ConnectionTimeout = 15; $c.Open(); $c.Close(); $c.Dispose()
            return @{ OK = $true }
        } catch {
            return @{ OK = $false; Error = $_.Exception.Message }
        }
    }
}

# --- main ---

if (-not (Test-Path $ConfigPath)) { Write-Error "config.json not found: $ConfigPath"; exit 1 }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

try {
    $httpCreds = Get-StoredCredential $config.credentialTarget
    $oraCreds  = Get-StoredCredential $config.oracleCredentialTarget
} catch {
    Write-Log $config.logFolder "ERROR" "Credentials: $($_.Exception.Message)"; exit 1
}

$url = Test-Url $config.url $httpCreds[0] $httpCreds[1]
if ($url.OK) { Write-Log $config.logFolder "OK"    "URL=$($config.url) STATUS=$($url.Status)" }
else         { Write-Log $config.logFolder "ERROR" "URL=$($config.url) STATUS=$($url.Status) MSG=$($url.Error)" }

$ora = Test-Oracle $config.oracleTnsAlias $oraCreds[0] $oraCreds[1]
if ($ora.OK) { Write-Log $config.logFolder "OK"    "ORACLE TNS=$($config.oracleTnsAlias) CONNECT=OK" }
else         { Write-Log $config.logFolder "ERROR" "ORACLE TNS=$($config.oracleTnsAlias) CONNECT=FAIL MSG=$($ora.Error)" }

Remove-OldLogs $config.logFolder $config.logRetentionDays
