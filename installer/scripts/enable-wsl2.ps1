# enable-wsl2.ps1 - Enable WSL2 feature on Windows
# Requires administrator privileges

$ErrorActionPreference = "Stop"

Write-Host "Enabling WSL2..." -ForegroundColor Yellow

try {
    # Enable WSL feature
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Host "  Enabling Windows Subsystem for Linux..."
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    }

    # Enable Virtual Machine Platform
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if ($vmFeature.State -ne "Enabled") {
        Write-Host "  Enabling Virtual Machine Platform..."
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    }

    # Set WSL2 as default
    wsl --set-default-version 2 2>&1 | Out-Null

    Write-Host "WSL2 enabled successfully." -ForegroundColor Green
    Write-Host "A system restart is required to complete the setup." -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host "Failed to enable WSL2: $_" -ForegroundColor Red
    exit 1
}
