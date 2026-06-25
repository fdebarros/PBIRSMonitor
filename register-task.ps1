# register-task.ps1
# Requires: Run as Administrator
#
# Actions:
#   Register   - registers the task in Task Scheduler (default)
#   Start      - starts the task immediately
#   Stop       - stops the running task
#   Unregister - removes the task from Task Scheduler
#   Status     - shows current task status
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File register-task.ps1 -Action Register
#   powershell.exe -ExecutionPolicy Bypass -File register-task.ps1 -Action Start
#   powershell.exe -ExecutionPolicy Bypass -File register-task.ps1 -Action Stop
#   powershell.exe -ExecutionPolicy Bypass -File register-task.ps1 -Action Unregister
#   powershell.exe -ExecutionPolicy Bypass -File register-task.ps1 -Action Status

param(
    [ValidateSet("Register", "Start", "Stop", "Unregister", "Status")]
    [string]$Action = "Register"
)

$taskName     = "PBIRSMonitor-Launcher"
$launcherPath = "D:\PBIRSMonitor\PBIRSMonitor-Launcher.cmd"

switch ($Action) {

    "Register" {
        $action    = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$launcherPath`""
        $trigger   = New-ScheduledTaskTrigger -AtStartup
        $settings  = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal `
            -UserId $env:USERNAME `
            -LogonType Interactive `
            -RunLevel Highest

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Force | Out-Null

        Write-Host "Task '$taskName' registered." -ForegroundColor Green
    }

    "Start" {
        Start-ScheduledTask -TaskName $taskName
        Write-Host "Task '$taskName' started." -ForegroundColor Green
    }

    "Stop" {
        Stop-ScheduledTask -TaskName $taskName
        Write-Host "Task '$taskName' stopped." -ForegroundColor Yellow
    }

    "Unregister" {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Task '$taskName' removed." -ForegroundColor Yellow
    }

    "Status" {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            Write-Host "Task '$taskName' not found." -ForegroundColor Red
        } else {
            $info = Get-ScheduledTaskInfo -TaskName $taskName
            Write-Host "Task      : $taskName"
            Write-Host "State     : $($task.State)"
            Write-Host "Last Run  : $($info.LastRunTime)"
            Write-Host "Last Result: $($info.LastTaskResult)"
            Write-Host "Next Run  : $($info.NextRunTime)"
        }
    }
}
