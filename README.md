# Create OCI VM Automation

PowerShell automation for creating an Oracle Cloud Always Free `VM.Standard.A1.Flex` instance in `ap-chuncheon-1` and retrying every 5 minutes when capacity is unavailable.

The VM is sized for the Dropbox Excel → Google Sheets inventory sync batch:

- Shape: `VM.Standard.A1.Flex`
- OCPU: `1`
- Memory: `6 GB`
- OS: latest compatible Ubuntu `24.04` or `22.04` ARM image
- Public IP: automatically assigned
- Repository: <https://github.com/i7444636/inventory-auto>
- Daily schedule: 21:00 KST
- Cron log: `/home/ubuntu/inventory-auto/cron.log`

## Files

- `create-oci-vm.ps1`: actual PowerShell script that calls OCI CLI, launches the instance, and retries on capacity/API errors.
- `deploy-after-create.md`: SSH, SCP, deployment, and cron commands to run after creation.
- `README.md`: beginner-friendly usage guide.

## Prerequisites on Windows PowerShell

1. OCI CLI is installed and configured.
2. This command works:

   ```powershell
   oci os ns get --region ap-chuncheon-1
   ```

3. You have an SSH key pair. If not, create one:

   ```powershell
   ssh-keygen -t ed25519 -C "oci-inventory-auto"
   ```

## Hard-coded OCI values

The script uses these requested values directly:

```text
region: ap-chuncheon-1
shape: VM.Standard.A1.Flex
ocpus: 1
memoryInGBs: 6
compartment OCID: ocid1.tenancy.oc1..aaaaaaaaslzlrblrikmktvmqoe2vitfvbpe6yj3ay7peclhzqqkv7kmdjexq
subnet OCID: ocid1.subnet.oc1.ap-chuncheon-1.aaaaaaaamillpdozi5szdmyowlk4seigbagmzs5kn2oleiosx4fjzl3qxmsa
public IP: automatic
```

## Step 1. Run the VM creation script

From this repository directory in Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\create-oci-vm.ps1
```

By default, it tries up to `200` times and waits `300` seconds (5 minutes) between retryable failures.

To change retry count:

```powershell
.\create-oci-vm.ps1 -MaxAttempts 500
```

To use a specific SSH public key:

```powershell
.\create-oci-vm.ps1 -SshPublicKeyPath $env:USERPROFILE\.ssh\id_ed25519.pub
```

To skip automatic cloud-init deployment and only create the VM:

```powershell
.\create-oci-vm.ps1 -SkipCloudInit
```

## Step 2. What the script does

`create-oci-vm.ps1` performs these actions:

1. Finds an availability domain in `ap-chuncheon-1`.
2. Finds the latest Ubuntu 24.04/22.04 ARM image compatible with `VM.Standard.A1.Flex`.
3. Confirms the configured subnet allows public IP assignment.
4. Launches a `1 OCPU / 6 GB` A1.Flex instance with automatic public IP.
5. Retries after 5 minutes when OCI returns capacity/API errors such as:
   - `Out of host capacity`
   - `InternalError`
   - `TooManyRequests`
6. Prints:
   - instance OCID
   - lifecycle state
   - public IP
   - SSH command
7. Unless `-SkipCloudInit` is used, it installs packages, clones the GitHub repository, creates `.venv`, installs requirements, sets timezone to `Asia/Seoul`, and registers cron for 21:00 KST.

## Required OCI lookup commands

These are useful if you want to check or pass values manually.

### Availability domain lookup

```powershell
oci iam availability-domain list `
  --compartment-id ocid1.tenancy.oc1..aaaaaaaaslzlrblrikmktvmqoe2vitfvbpe6yj3ay7peclhzqqkv7kmdjexq `
  --region ap-chuncheon-1 `
  --output table
```

### Ubuntu ARM image OCID lookup

```powershell
oci compute image list `
  --compartment-id ocid1.tenancy.oc1..aaaaaaaaslzlrblrikmktvmqoe2vitfvbpe6yj3ay7peclhzqqkv7kmdjexq `
  --region ap-chuncheon-1 `
  --operating-system "Canonical Ubuntu" `
  --shape VM.Standard.A1.Flex `
  --all `
  --query "data[?contains(\`"display-name\`", 'aarch64') || contains(\`"display-name\`", 'arm')].[\`"display-name\`", id, \`"time-created\`]" `
  --output table
```

If auto image lookup fails, copy a suitable Ubuntu 22.04/24.04 ARM image OCID and pass it manually:

```powershell
.\create-oci-vm.ps1 -ImageId "ocid1.image.oc1.ap-chuncheon-1..."
```

### Subnet check

```powershell
oci network subnet get `
  --subnet-id ocid1.subnet.oc1.ap-chuncheon-1.aaaaaaaamillpdozi5szdmyowlk4seigbagmzs5kn2oleiosx4fjzl3qxmsa `
  --region ap-chuncheon-1 `
  --output table
```

Confirm `prohibit-public-ip-on-vnic` is `false`.

## Step 3. SSH command after success

The script prints the public IP. Connect with:

```powershell
ssh -i <PRIVATE_KEY_PATH> ubuntu@<PUBLIC_IP>
```

Example:

```powershell
ssh -i $env:USERPROFILE\.ssh\id_ed25519 ubuntu@123.123.123.123
```

## Step 4. Upload secret files

`.env` and `service_account.json` are not uploaded to GitHub. Upload them with `scp` after the VM is created:

```powershell
scp -i <PRIVATE_KEY_PATH> <LOCAL_ENV_PATH> ubuntu@<PUBLIC_IP>:/home/ubuntu/inventory-auto/.env
scp -i <PRIVATE_KEY_PATH> <LOCAL_SERVICE_ACCOUNT_JSON_PATH> ubuntu@<PUBLIC_IP>:/home/ubuntu/inventory-auto/service_account.json
```

See `deploy-after-create.md` for complete deployment, cron, and log commands.

## Optional only: E2.1.Micro fallback

This project intentionally does **not** automatically create a larger server or switch shapes. `1 OCPU / 6 GB` on A1.Flex is the target.

If you cannot get A1.Flex capacity for a long time and want a temporary tiny VM, you may manually investigate `VM.Standard.E2.1.Micro`, but it is optional and not included in the script.
