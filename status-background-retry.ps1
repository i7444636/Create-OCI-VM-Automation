Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $root "oci-retry.pid"
$logs = Join-Path $root "logs"

if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Host "Retry is not running. PID file does not exist."
} else {
    $pidValue = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    $process = $null
    if ($pidValue) {
        $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
    }

    if ($process) {
        Write-Host "Retry is running. PID: $pidValue"
        Write-Host "Started: $($process.StartTime)"
    } else {
        Write-Host "Retry is not running. Stale PID file: $pidValue"
    }
}

if (Test-Path -LiteralPath $logs) {
    $latestLog = Get-ChildItem -LiteralPath $logs -Filter "oci-retry-*.log" |
        Where-Object { $_.Name -notlike "*.err.log" } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($latestLog) {
        Write-Host "Latest log: $($latestLog.FullName)"
        Write-Host "Last log lines:"
        Get-Content -LiteralPath $latestLog.FullName -Tail 20
    }

    $latestErrorLog = Get-ChildItem -LiteralPath $logs -Filter "oci-retry-*.err.log" |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($latestErrorLog -and $latestErrorLog.Length -gt 0) {
        Write-Host "Latest error log: $($latestErrorLog.FullName)"
        Write-Host "Last error log lines:"
        Get-Content -LiteralPath $latestErrorLog.FullName -Tail 20
    }
}
