param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"
$retentionText = $env:LOCAL_LOG_RETENTION_DAYS
$envFile = Join-Path $ProjectDir ".env"
if (-not $retentionText -and (Test-Path -LiteralPath $envFile)) {
    $setting = Get-Content -LiteralPath $envFile |
        Where-Object { $_ -match '^\s*LOCAL_LOG_RETENTION_DAYS\s*=\s*\d+\s*$' } |
        Select-Object -Last 1
    if ($setting) {
        $retentionText = ($setting -split '=', 2)[1].Trim()
    }
}
if (-not $retentionText) { $retentionText = "30" }

$retentionDays = 0
if (-not [int]::TryParse($retentionText, [ref]$retentionDays) -or $retentionDays -lt 1) {
    throw "LOCAL_LOG_RETENTION_DAYS must be a positive integer."
}

$logDir = Join-Path $ProjectDir "logs"
if (-not (Test-Path -LiteralPath $logDir)) { return }
$cutoff = [DateTime]::UtcNow.AddDays(-$retentionDays)
Get-ChildItem -LiteralPath $logDir -File -Filter "*.log" |
    Where-Object { $_.LastWriteTimeUtc -lt $cutoff } |
    Remove-Item -Force
