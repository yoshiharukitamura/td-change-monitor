$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir
$settingsFile = Join-Path $scriptDir "local.settings.ps1"
if (Test-Path $settingsFile) { . $settingsFile }
if (-not $UvPath) { $UvPath = (Get-Command uv -ErrorAction Stop).Source }
if ($GitPath) { $env:GIT_EXECUTABLE = $GitPath }
$logDir = Join-Path $projectDir "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
& (Join-Path $scriptDir "cleanup_logs.ps1") -ProjectDir $projectDir
$logFile = Join-Path $logDir ("td_change_monitor_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
$mutex = [System.Threading.Mutex]::new($false, "Global\TDChangeMonitor")
$hasLock = $false
$exitCode = 0
try {
    $hasLock = $mutex.WaitOne(0)
    if (-not $hasLock) {
        "TDChangeMonitor is already running." | Tee-Object -FilePath $logFile
        $exitCode = 10
    }
    else {
        Set-Location $projectDir
        & $UvPath run td-change-monitor 2>&1 | Tee-Object -FilePath $logFile
        $exitCode = $LASTEXITCODE
    }
}
finally {
    if ($hasLock) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
    & (Join-Path $scriptDir "cleanup_logs.ps1") -ProjectDir $projectDir
}
exit $exitCode
