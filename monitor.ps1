param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

function Write-DayHeader([string]$LogFile) {
    $date   = Get-Date -Format "yyyy-MM-dd"
    $header = @"
================================================================================
  PBIRS Synthetic Monitor | $date
  TARGET    STATUS    TIME      DETAIL
================================================================================

"@
    Add-Content -Path $LogFile -Value $header -Encoding UTF8
}

function Write-Log([string]$LogFolder, [string]$Level, [string]$UrlLine, [string]$OraLine) {
    if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }

    $date    = Get-Date -Format "yyyy-MM-dd"
    $ts      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = Join-Path $LogFolder "monitor_$date.log"

    # Escreve cabecalho se arquivo e novo
    if (-not (Test-Path $logFile)) { Write-DayHeader $logFile }

    $status  = if ($Level -eq "OK") { "CHECK OK" } else { "CHECK FAILED" }
    $block   = @"
=== $ts | $status ===
$UrlLine
$OraLine

"@
    Add-Content -Path $logFile -Value $block -Encoding UTF8
}

function Remove-OldLogs([string]$LogFolder, [int]$RetentionDays) {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogFolder -Filter "monitor_*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
}

function Test-Url([string]$Url, [System.Management.Automation.PSCredential]$Cred) {
    $result = @{}
    $elapsed = (Measure-Command {
        try {
            $r = Invoke-WebRequest -Uri $Url -Credential $Cred -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $result.OK     = $true
            $result.Status = $r.StatusCode
        } catch {
            $code          = $_.Exception.Response.StatusCode.Value__
            $result.OK     = $false
            $result.Status = if ($code) { $code } else { "ERR" }
            $result.Error  = $_.Exception.Message
        }
    }).TotalMilliseconds
    $result.Ms = [math]::Round($elapsed)
    return $result
}

function Test-Oracle([string]$TnsAlias, [System.Management.Automation.PSCredential]$Cred) {
    $user    = $Cred.UserName
    $pass    = $Cred.GetNetworkCredential().Password
    $result  = @{}
    $elapsed = (Measure-Command {
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
            $result.OK = $true
        } catch {
            $result.OK    = $false
            $result.Error = $_.Exception.Message
        }
    }).TotalMilliseconds
    $result.Ms = [math]::Round($elapsed)
    return $result
}

function Format-Line([string]$Target, [string]$Status, [int]$Ms, [string]$Detail, [string]$Error) {
    $line = "  {0,-8}  {1,-8}  {2,6}ms  {3}" -f $Target, $Status, $Ms, $Detail
    if ($Error) { $line += "  >>  $Error" }
    return $line
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
$ora = Test-Oracle $config.oracleTnsAlias $oraCred

$urlStatus  = if ($url.OK) { $url.Status } else { $url.Status }
$oraStatus  = if ($ora.OK) { "OK" } else { "FAIL" }
$overallLevel = if ($url.OK -and $ora.OK) { "OK" } else { "FAIL" }

$urlLine = Format-Line "URL" $urlStatus $url.Ms $config.url $url.Error
$oraLine = Format-Line "ORACLE" $oraStatus $ora.Ms $config.oracleTnsAlias $ora.Error

Write-Log $config.logFolder $overallLevel $urlLine $oraLine

Remove-OldLogs $config.logFolder $config.logRetentionDays
