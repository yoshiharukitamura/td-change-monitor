$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir

function Get-DirectoryBytes {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $measurement = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($null -eq $measurement.Sum) { return [int64]0 }
    return [int64]$measurement.Sum
}

$targets = [ordered]@{
    working_tree = $projectDir
    git_history = Join-Path $projectDir ".git"
    current_schemas = Join-Path $projectDir "schemas\current"
    diffs = Join-Path $projectDir "diffs"
    audit_events = Join-Path $projectDir "audit_events"
    state = Join-Path $projectDir "state"
    logs = Join-Path $projectDir "logs"
}

$rows = foreach ($item in $targets.GetEnumerator()) {
    $bytes = Get-DirectoryBytes -Path $item.Value
    [pscustomobject]@{
        Name = $item.Key
        Bytes = $bytes
        MiB = [math]::Round($bytes / 1MB, 3)
        Path = $item.Value
    }
}
$rows | Format-Table -AutoSize
