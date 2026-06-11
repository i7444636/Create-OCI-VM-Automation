param(
    [string]$ConfigPath = ".\oci-vm-config.json",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-Config {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path. Copy oci-vm-config.example.json to oci-vm-config.json and fill it in."
    }

    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed or not on PATH."
    }
}

function Convert-ToFileUri {
    param([string]$Path)

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    "file://$($fullPath.Replace('\', '/'))"
}

function New-LaunchArguments {
    param(
        $Config,
        [string]$MetadataFile,
        [string]$ShapeConfigFile
    )

    $metadataUri = Convert-ToFileUri -Path $MetadataFile

    $args = @(
        "compute", "instance", "launch",
        "--compartment-id", $Config.compartmentId,
        "--availability-domain", $Config.availabilityDomain,
        "--subnet-id", $Config.subnetId,
        "--image-id", $Config.imageId,
        "--shape", $Config.shape,
        "--display-name", $Config.displayName,
        "--metadata", $metadataUri,
        "--profile", $Config.profile,
        "--wait-for-state", "RUNNING"
    )

    if ($Config.shape -like "*.Flex") {
        $shapeConfigUri = Convert-ToFileUri -Path $ShapeConfigFile
        $args += @("--shape-config", $shapeConfigUri)
    }

    if ($Config.assignPublicIp) {
        $args += @("--assign-public-ip", "true")
    }

    $args
}

$config = Read-Config -Path $ConfigPath
Assert-Command -Name "oci"

if (-not (Test-Path -LiteralPath $config.sshPublicKeyPath)) {
    throw "SSH public key file not found: $($config.sshPublicKeyPath)"
}

$sshPublicKey = (Get-Content -LiteralPath $config.sshPublicKeyPath -Raw).Trim()

$runtimeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".runtime"
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$metadataFile = Join-Path $runtimeDir "metadata.json"
$shapeConfigFile = Join-Path $runtimeDir "shape-config.json"

@{ ssh_authorized_keys = $sshPublicKey } |
    ConvertTo-Json -Compress |
    Set-Content -LiteralPath $metadataFile -Encoding ASCII

@{
    ocpus       = [double]$config.ocpus
    memoryInGBs = [double]$config.memoryInGBs
} |
    ConvertTo-Json -Compress |
    Set-Content -LiteralPath $shapeConfigFile -Encoding ASCII

$launchArgs = New-LaunchArguments -Config $config -MetadataFile $metadataFile -ShapeConfigFile $shapeConfigFile

if ($DryRun) {
    Write-Host "oci $($launchArgs -join ' ')"
    exit 0
}

$attempt = 0
$maxAttempts = [int]$config.maxAttempts
$baseDelay = [int]$config.retryDelaySeconds

while ($true) {
    $attempt++
    $startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$startedAt] Attempt $attempt launching $($config.shape) in $($config.availabilityDomain)..."

    try {
        $output = & oci @launchArgs 2>&1
        $exitCode = $LASTEXITCODE
    } catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    }

    if ($exitCode -eq 0) {
        Write-Host "Instance launch succeeded."
        $output
        exit 0
    }

    Write-Host "Launch failed with exit code $exitCode."
    $outputText = ($output | Out-String).Trim()
    if ($outputText) {
        $outputText -split "`r?`n" | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }
    }

    if ($maxAttempts -gt 0 -and $attempt -ge $maxAttempts) {
        throw "Reached maxAttempts=$maxAttempts without a successful launch."
    }

    $jitter = Get-Random -Minimum 0 -Maximum 16
    $delay = $baseDelay + $jitter
    Write-Host "Waiting $delay seconds before retry..."
    Start-Sleep -Seconds $delay
}
