<#
.SYNOPSIS
  Create an Oracle Cloud Always Free VM.Standard.A1.Flex instance and retry when capacity is unavailable.

.DESCRIPTION
  This script launches a 1 OCPU / 6 GB Ubuntu ARM VM in ap-chuncheon-1 using OCI CLI.
  It automatically looks up an availability domain and the latest Ubuntu 24.04/22.04 aarch64 image
  unless you pass -AvailabilityDomain or -ImageId explicitly.

  It also injects cloud-init that installs git/python packages, clones the GitHub repository,
  creates a Python virtual environment, installs requirements.txt, sets the VM timezone to Asia/Seoul,
  and registers cron to run main.py every day at 21:00 KST.

.PREREQUISITES
  - Run from Windows PowerShell or PowerShell 7 where `oci` already works.
  - A public SSH key exists at ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub,
    or pass -SshPublicKeyPath.
#>

[CmdletBinding()]
param(
    [int]$MaxAttempts = 200,
    [int]$RetryWaitSeconds = 300,
    [string]$AvailabilityDomain = "",
    [string]$ImageId = "",
    [string]$SshPublicKeyPath = "",
    [string]$InstanceName = "inventory-auto-a1-flex",
    [switch]$SkipCloudInit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------
# Hard-coded requested values
# -------------------------
$Region = "ap-chuncheon-1"
$CompartmentId = "ocid1.tenancy.oc1..aaaaaaaaslzlrblrikmktvmqoe2vitfvbpe6yj3ay7peclhzqqkv7kmdjexq"
$SubnetId = "ocid1.subnet.oc1.ap-chuncheon-1.aaaaaaaamillpdozi5szdmyowlk4seigbagmzs5kn2oleiosx4fjzl3qxmsa"
$Shape = "VM.Standard.A1.Flex"
$Ocpus = 1
$MemoryInGBs = 6
$RepoUrl = "https://github.com/i7444636/inventory-auto.git"
$RepoDir = "/home/ubuntu/inventory-auto"
$CronLog = "/home/ubuntu/inventory-auto/cron.log"

function Invoke-OciJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & oci @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $text = ($output | Out-String).Trim()
        throw $text
    }

    $json = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return $json | ConvertFrom-Json
}

function ConvertTo-Base64Utf8 {
    param([Parameter(Mandatory = $true)][string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-DefaultSshPublicKeyPath {
    $candidates = @(
        (Join-Path $HOME ".ssh/id_ed25519.pub"),
        (Join-Path $HOME ".ssh/id_rsa.pub")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "No SSH public key was found. Create one with: ssh-keygen -t ed25519 -C 'oci-inventory-auto'"
}

function Get-AvailabilityDomainName {
    Write-Host "Looking up availability domain in $Region ..."
    $ads = Invoke-OciJson -Arguments @(
        "iam", "availability-domain", "list",
        "--compartment-id", $CompartmentId,
        "--region", $Region,
        "--output", "json"
    )

    if (-not $ads.data -or $ads.data.Count -lt 1) {
        throw "No availability domains returned for compartment $CompartmentId"
    }

    return $ads.data[0].name
}

function Get-UbuntuArmImageId {
    Write-Host "Looking up latest Ubuntu ARM image compatible with $Shape in $Region ..."
    $images = Invoke-OciJson -Arguments @(
        "compute", "image", "list",
        "--compartment-id", $CompartmentId,
        "--region", $Region,
        "--operating-system", "Canonical Ubuntu",
        "--shape", $Shape,
        "--all",
        "--output", "json"
    )

    $selected = $images.data |
        Where-Object {
            $_."display-name" -match "aarch64|arm" -and
            ($_."operating-system-version" -match "^(24\.04|22\.04)" -or $_."display-name" -match "(24\.04|22\.04)")
        } |
        Sort-Object { [datetime]$_."time-created" } -Descending |
        Select-Object -First 1

    if (-not $selected) {
        throw "Could not find an Ubuntu 22.04/24.04 ARM image. Run the image lookup command in README.md and pass -ImageId manually."
    }

    Write-Host ("Selected image: {0} ({1})" -f $selected."display-name", $selected.id)
    return $selected.id
}

function New-CloudInitText {
    @"
#cloud-config
timezone: Asia/Seoul
package_update: true
packages:
  - git
  - python3-venv
  - python3-pip
runcmd:
  - [ bash, -lc, "set -euxo pipefail; if [ ! -d '$RepoDir/.git' ]; then sudo -u ubuntu git clone '$RepoUrl' '$RepoDir'; fi" ]
  - [ bash, -lc, "set -euxo pipefail; cd '$RepoDir'; sudo -u ubuntu python3 -m venv .venv" ]
  - [ bash, -lc, "set -euxo pipefail; cd '$RepoDir'; sudo -u ubuntu .venv/bin/pip install --upgrade pip" ]
  - [ bash, -lc, "set -euxo pipefail; cd '$RepoDir'; if [ -f requirements.txt ]; then sudo -u ubuntu .venv/bin/pip install -r requirements.txt; fi" ]
  - [ bash, -lc, "touch '$CronLog'; chown ubuntu:ubuntu '$CronLog'" ]
  - [ bash, -lc, "printf '0 21 * * * cd $RepoDir && /home/ubuntu/inventory-auto/.venv/bin/python main.py >> $CronLog 2>&1\n' | crontab -u ubuntu -" ]
"@
}

function New-MetadataFile {
    param(
        [Parameter(Mandatory = $true)][string]$SshPublicKey,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $metadata = [ordered]@{
        ssh_authorized_keys = $SshPublicKey
    }

    if (-not $SkipCloudInit) {
        $metadata.user_data = ConvertTo-Base64Utf8 (New-CloudInitText)
    }

    $metadataFile = Join-Path $Directory "oci-metadata.json"
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataFile -Encoding utf8
    return $metadataFile
}

function Test-RetryableOciError {
    param([Parameter(Mandatory = $true)][string]$ErrorText)

    return ($ErrorText -match "Out of host capacity" -or
            $ErrorText -match "InternalError" -or
            $ErrorText -match "TooManyRequests" -or
            $ErrorText -match "LimitExceeded" -or
            $ErrorText -match "ServiceError" -or
            $ErrorText -match "not enough capacity")
}

function Get-PublicIpForInstance {
    param([Parameter(Mandatory = $true)][string]$InstanceId)

    $attachments = Invoke-OciJson -Arguments @(
        "compute", "vnic-attachment", "list",
        "--compartment-id", $CompartmentId,
        "--instance-id", $InstanceId,
        "--region", $Region,
        "--all",
        "--output", "json"
    )

    $attachment = $attachments.data | Select-Object -First 1
    if (-not $attachment) {
        return ""
    }

    $vnic = Invoke-OciJson -Arguments @(
        "network", "vnic", "get",
        "--vnic-id", $attachment."vnic-id",
        "--region", $Region,
        "--output", "json"
    )

    return $vnic.data."public-ip"
}

if (-not (Get-Command oci -ErrorAction SilentlyContinue)) {
    throw "OCI CLI was not found in PATH. Confirm that `oci --version` works in this PowerShell session."
}

if ([string]::IsNullOrWhiteSpace($SshPublicKeyPath)) {
    $SshPublicKeyPath = Get-DefaultSshPublicKeyPath
}

$SshPublicKey = (Get-Content -Path $SshPublicKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($SshPublicKey)) {
    throw "SSH public key file is empty: $SshPublicKeyPath"
}

if ([string]::IsNullOrWhiteSpace($AvailabilityDomain)) {
    $AvailabilityDomain = Get-AvailabilityDomainName
}

if ([string]::IsNullOrWhiteSpace($ImageId)) {
    $ImageId = Get-UbuntuArmImageId
}

Write-Host "Checking subnet ..."
$subnet = Invoke-OciJson -Arguments @(
    "network", "subnet", "get",
    "--subnet-id", $SubnetId,
    "--region", $Region,
    "--output", "json"
)
Write-Host ("Subnet: {0}, prohibit-public-ip-on-vnic={1}" -f $subnet.data."display-name", $subnet.data."prohibit-public-ip-on-vnic")
if ($subnet.data."prohibit-public-ip-on-vnic" -eq $true) {
    throw "The configured subnet prohibits public IPs. Use a public subnet or set prohibit-public-ip-on-vnic=false."
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("oci-a1-create-" + [guid]::NewGuid().ToString("N"))
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
$metadataFile = New-MetadataFile -SshPublicKey $SshPublicKey -Directory $tempDir
$metadataFileForOci = $metadataFile -replace "\\", "/"
$shapeConfig = @{ ocpus = $Ocpus; memoryInGBs = $MemoryInGBs } | ConvertTo-Json -Compress

Write-Host ""
Write-Host "Starting instance creation retries. MaxAttempts=$MaxAttempts, RetryWaitSeconds=$RetryWaitSeconds"
Write-Host "Region=$Region"
Write-Host "AD=$AvailabilityDomain"
Write-Host "Shape=$Shape, OCPUs=$Ocpus, MemoryInGBs=$MemoryInGBs"
Write-Host "ImageId=$ImageId"
Write-Host "SubnetId=$SubnetId"
Write-Host ""

$instance = $null
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $displayName = "$InstanceName-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))"
    Write-Host "[$attempt/$MaxAttempts] Launching $displayName ..."

    try {
        $result = Invoke-OciJson -Arguments @(
            "compute", "instance", "launch",
            "--availability-domain", $AvailabilityDomain,
            "--compartment-id", $CompartmentId,
            "--region", $Region,
            "--shape", $Shape,
            "--shape-config", $shapeConfig,
            "--image-id", $ImageId,
            "--subnet-id", $SubnetId,
            "--assign-public-ip", "true",
            "--display-name", $displayName,
            "--metadata", "file://$metadataFileForOci",
            "--wait-for-state", "RUNNING",
            "--max-wait-seconds", "1800",
            "--output", "json"
        )

        $instance = $result.data
        Write-Host "Instance reached RUNNING state."
        break
    }
    catch {
        $errorText = $_.Exception.Message
        Write-Host "Launch failed:"
        Write-Host $errorText

        if ($attempt -ge $MaxAttempts) {
            throw "Reached MaxAttempts=$MaxAttempts without creating an instance. Last error: $errorText"
        }

        if (Test-RetryableOciError -ErrorText $errorText) {
            Write-Host "Retryable capacity/API error detected. Waiting $RetryWaitSeconds seconds before retrying ..."
            Start-Sleep -Seconds $RetryWaitSeconds
            continue
        }

        throw "Non-retryable OCI error. Fix the issue and run again. Error: $errorText"
    }
}

if (-not $instance) {
    throw "No instance was created."
}

$instanceId = $instance.id
$lifecycleState = $instance."lifecycle-state"
$publicIp = ""

Write-Host "Waiting 20 seconds for VNIC public IP to become visible ..."
Start-Sleep -Seconds 20
for ($i = 1; $i -le 12; $i++) {
    $publicIp = Get-PublicIpForInstance -InstanceId $instanceId
    if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
        break
    }
    Write-Host "Public IP not visible yet. Waiting 10 seconds ..."
    Start-Sleep -Seconds 10
}

Write-Host ""
Write-Host "==================== SUCCESS ===================="
Write-Host "Instance OCID    : $instanceId"
Write-Host "Lifecycle state  : $lifecycleState"
Write-Host "Public IP        : $publicIp"
Write-Host "SSH command      : ssh -i <PRIVATE_KEY_PATH> ubuntu@$publicIp"
Write-Host "Repository       : $RepoDir"
Write-Host "Cron log         : $CronLog"
Write-Host "================================================="
Write-Host ""
Write-Host "Next: upload .env and service_account.json using the scp commands in deploy-after-create.md."
