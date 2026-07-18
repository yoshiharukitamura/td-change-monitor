param([string]$TaskName = "TDChangeMonitor", [string]$At = "08:00")
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir
$runner = Join-Path $scriptDir "run_td_change_monitor.ps1"
$uvPath = (Get-Command uv -ErrorAction Stop).Source
$gitPath = (Get-Command git -ErrorAction Stop).Source
@"
`$UvPath = '$($uvPath.Replace("'", "''"))'
`$GitPath = '$($gitPath.Replace("'", "''"))'
`$ProjectDir = '$($projectDir.Replace("'", "''"))'
"@ | Set-Content -Path (Join-Path $scriptDir "local.settings.ps1") -Encoding UTF8
$atTime = [DateTime]::ParseExact($At, "HH:mm", $null)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runner`""
$trigger = New-ScheduledTaskTrigger -Daily -At $atTime
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Treasure Data table change monitor" -Force | Out-Null
Write-Host "Registered: $TaskName at $At"
Write-Host "Git: $gitPath"
Write-Host "Test: Start-ScheduledTask -TaskName `"$TaskName`""
