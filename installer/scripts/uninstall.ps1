# uninstall.ps1 - Clean uninstall of Hermes
# Removes WSL distribution and all associated data

$ErrorActionPreference = "SilentlyContinue"

$DistroName = "HermesLinux"

Write-Host "Uninstalling Hermes..." -ForegroundColor Yellow

# Stop any running services first
Write-Host "  Stopping services..."
wsl -d $DistroName -- bash /opt/hermes/scripts/stop-services.sh 2>&1 | Out-Null

# Terminate the WSL distribution
Write-Host "  Terminating WSL distribution..."
wsl --terminate $DistroName 2>&1 | Out-Null

# Unregister the distribution (deletes all data)
Write-Host "  Removing HermesLinux distribution..."
wsl --unregister $DistroName 2>&1 | Out-Null

# Remove autostart registry entry if exists
Write-Host "  Cleaning up registry..."
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Hermes" -ErrorAction SilentlyContinue

Write-Host "Hermes uninstalled successfully" -ForegroundColor Green
