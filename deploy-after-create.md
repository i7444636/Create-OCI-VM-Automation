# Deploy after OCI VM creation

This file contains copy/paste commands to run **after** `create-oci-vm.ps1` creates the VM.

Replace these placeholders first:

- `<PUBLIC_IP>`: the public IP printed by `create-oci-vm.ps1`
- `<PRIVATE_KEY_PATH>`: your SSH private key path, for example `$env:USERPROFILE\.ssh\id_ed25519` on Windows PowerShell
- `<LOCAL_ENV_PATH>`: local path to your `.env` file
- `<LOCAL_SERVICE_ACCOUNT_JSON_PATH>`: local path to your `service_account.json` file

## 1. SSH into the VM

```powershell
ssh -i <PRIVATE_KEY_PATH> ubuntu@<PUBLIC_IP>
```

## 2. Manual deployment commands on the server

The PowerShell script already injects cloud-init to run these commands automatically. If you used `-SkipCloudInit`, or if you want to rerun setup manually, SSH into the server and run:

```bash
sudo apt update
sudo apt install git python3-venv python3-pip -y

if [ ! -d "$HOME/inventory-auto/.git" ]; then
  git clone https://github.com/i7444636/inventory-auto.git "$HOME/inventory-auto"
fi

cd "$HOME/inventory-auto"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 3. Upload `.env` and `service_account.json` from Windows PowerShell

Run these commands from your Windows PowerShell, not inside the server:

```powershell
scp -i <PRIVATE_KEY_PATH> <LOCAL_ENV_PATH> ubuntu@<PUBLIC_IP>:/home/ubuntu/inventory-auto/.env
scp -i <PRIVATE_KEY_PATH> <LOCAL_SERVICE_ACCOUNT_JSON_PATH> ubuntu@<PUBLIC_IP>:/home/ubuntu/inventory-auto/service_account.json
```

Example:

```powershell
scp -i $env:USERPROFILE\.ssh\id_ed25519 C:\Users\me\inventory-auto\.env ubuntu@123.123.123.123:/home/ubuntu/inventory-auto/.env
scp -i $env:USERPROFILE\.ssh\id_ed25519 C:\Users\me\inventory-auto\service_account.json ubuntu@123.123.123.123:/home/ubuntu/inventory-auto/service_account.json
```

## 4. Test the batch manually

SSH into the server and run:

```bash
cd /home/ubuntu/inventory-auto
source .venv/bin/activate
python main.py
```

## 5. Cron registration

### Option A: server timezone is Asia/Seoul

The script sets the server timezone to `Asia/Seoul`, so use this cron expression for **21:00 KST every day**:

```bash
sudo timedatectl set-timezone Asia/Seoul
(crontab -l 2>/dev/null | grep -v 'inventory-auto/.venv/bin/python main.py'; echo '0 21 * * * cd /home/ubuntu/inventory-auto && /home/ubuntu/inventory-auto/.venv/bin/python main.py >> /home/ubuntu/inventory-auto/cron.log 2>&1') | crontab -
```

### Option B: server timezone remains UTC

If you keep the server timezone as UTC, 21:00 KST is 12:00 UTC:

```bash
(crontab -l 2>/dev/null | grep -v 'inventory-auto/.venv/bin/python main.py'; echo '0 12 * * * cd /home/ubuntu/inventory-auto && /home/ubuntu/inventory-auto/.venv/bin/python main.py >> /home/ubuntu/inventory-auto/cron.log 2>&1') | crontab -
```

## 6. Check cron and logs

```bash
crontab -l
tail -n 100 /home/ubuntu/inventory-auto/cron.log
```
