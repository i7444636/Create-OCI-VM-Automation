param(
    [string]$ConfigPath = ".\oci-vm-config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $root "try-oci-free-tier-vm.ps1"
$worker = Join-Path $root "run-retry-worker.cmd"
$logs = Join-Path $root "logs"
$pidFile = Join-Path $root "oci-retry.pid"

if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner script not found: $runner"
}

if (-not (Test-Path -LiteralPath $worker)) {
    throw "Worker script not found: $worker"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

if (Test-Path -LiteralPath $pidFile) {
    $oldPid = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    if ($oldPid -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        Write-Host "Retry is already running. PID: $oldPid"
        exit 0
    }
}

New-Item -ItemType Directory -Path $logs -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $logs "oci-retry-$timestamp.log"
$errorLogPath = Join-Path $logs "oci-retry-$timestamp.err.log"
$configFullPath = (Resolve-Path -LiteralPath $ConfigPath).Path

$startProcessArgs = @{
    FilePath               = $worker
    ArgumentList           = @($configFullPath)
    WorkingDirectory       = $root
    WindowStyle            = "Hidden"
    PassThru               = $true
    RedirectStandardOutput = $logPath
    RedirectStandardError  = $errorLogPath
}

$process = Start-Process @startProcessArgs

$process.Id | Set-Content -LiteralPath $pidFile -Encoding ASCII

Write-Host "Background retry started."
Write-Host "PID: $($process.Id)"
Write-Host "Log: $logPath"
Write-Host "Error log: $errorLogPath"
