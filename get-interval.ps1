$config = Get-Content "$PSScriptRoot\config.json" -Raw | ConvertFrom-Json
Write-Output $config.checkIntervalSeconds
