Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $root "oci-retry.pid"

if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Host "Retry is not running. PID file does not exist."
    exit 0
}

$pidValue = (Get-Content -LiteralPath $pidFile -Raw).Trim()
if (-not $pidValue) {
    Remove-Item -LiteralPath $pidFile -Force
    Write-Host "Removed empty PID file."
    exit 0
}

$process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
if ($process) {
    Stop-Process -Id ([int]$pidValue)
    Write-Host "Stopped background retry. PID: $pidValue"
} else {
    Write-Host "No running process found for PID: $pidValue"
}

Remove-Item -LiteralPath $pidFile -Force
