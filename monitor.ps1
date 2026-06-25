param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

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

function Test-Url([string]$Url, [System.Management.Automation.PSCredential]$Cred) {
    try {
        $r = Invoke-WebRequest -Uri $Url -Credential $Cred -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return @{ OK = $true; Status = $r.StatusCode }
    } catch {
        $code = $_.Exception.Response.StatusCode.Value__
        return @{ OK = $false; Status = $(if ($code) { $code } else { "ERR" }); Error = $_.Exception.Message }
    }
}

function Test-Oracle([string]$TnsAlias, [System.Management.Automation.PSCredential]$Cred) {
    $user = $Cred.UserName
    $pass = $Cred.GetNetworkCredential().Password
    try {
        $odpPaths = @(
            "C:\Program Files\Oracle Client for Microsoft Tools\odp.net\managed\common\Oracle.ManagedDataAccess.dll",
            "${env:ProgramFiles}\Oracle\ODAC\odp.net\managed\common\Oracle.ManagedDataAccess.dll",
            "${env:ProgramFiles(x86)}\Oracle\ODAC\odp.net\managed\common\Oracle.ManagedDataAccess.dll"
        )
        $loaded = $false
        foreach ($p in $odpPaths) {
            if (Test-Path $p) { Add-Type -Path $p -ErrorAction Stop; $loaded = $true; break }
        }
        if (-not $loaded) { throw "Oracle.ManagedDataAccess.dll not found." }

        $conn = New-Object Oracle.ManagedDataAccess.Client.OracleConnection(
            "User Id=$user;Password=$pass;Data Source=$TnsAlias;Connection Timeout=15;")
        $conn.Open(); $conn.Close(); $conn.Dispose()
        return @{ OK = $true }
    } catch {
        return @{ OK = $false; Error = $_.Exception.Message }
    }
}

# --- main ---

if (-not (Test-Path $ConfigPath)) { Write-Error "config.json not found: $ConfigPath"; exit 1 }
$config     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$credFolder = Split-Path $ConfigPath

$httpCredFile = Join-Path $credFolder "cred_http.xml"
$oraCredFile  = Join-Path $credFolder "cred_oracle.xml"

if (-not (Test-Path $httpCredFile) -or -not (Test-Path $oraCredFile)) {
    Write-Error "Credential files not found. Run setup.ps1 first."
    exit 1
}

$httpCred = Import-Clixml -Path $httpCredFile
$oraCred  = Import-Clixml -Path $oraCredFile

$url = Test-Url $config.url $httpCred
if ($url.OK) { Write-Log $config.logFolder "OK"    "URL=$($config.url) STATUS=$($url.Status)" }
else         { Write-Log $config.logFolder "ERROR" "URL=$($config.url) STATUS=$($url.Status) MSG=$($url.Error)" }

$ora = Test-Oracle $config.oracleTnsAlias $oraCred
if ($ora.OK) { Write-Log $config.logFolder "OK"    "ORACLE TNS=$($config.oracleTnsAlias) CONNECT=OK" }
else         { Write-Log $config.logFolder "ERROR" "ORACLE TNS=$($config.oracleTnsAlias) CONNECT=FAIL MSG=$($ora.Error)" }

Remove-OldLogs $config.logFolder $config.logRetentionDays
