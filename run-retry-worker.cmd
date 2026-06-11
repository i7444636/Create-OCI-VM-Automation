@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0try-oci-free-tier-vm.ps1" -ConfigPath "%~1"
