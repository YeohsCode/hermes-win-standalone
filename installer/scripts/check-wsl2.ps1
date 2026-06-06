# check-wsl2.ps1 - Verify WSL2 is properly configured
# Called during installation to validate environment
# Exits non-zero on failure so the installer can abort.

$ErrorActionPreference = "Stop"

function Enable-WindowsFeatureSafe {
    param([string]$FeatureName)
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    if (-not $feature) {
        return @{ Success = $false; Message = "Feature '$FeatureName' not found on this OS." }
    }
    if ($feature.State -eq "Enabled") {
        return @{ Success = $true; Message = "'$FeatureName' is already enabled." }
    }
    Write-Host "Enabling $FeatureName ..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction Stop | Out-Null
    return @{ Success = $true; NeedsReboot = $true; Message = "'$FeatureName' has been enabled (reboot needed)." }
}

function Test-WSL2 {
    $needsReboot = $false

    # --- Step 1: Ensure VirtualMachinePlatform is enabled ---
    $vmp = Enable-WindowsFeatureSafe "VirtualMachinePlatform"
    if (-not $vmp.Success) {
        return @{ Ready = $false; Message = $vmp.Message }
    }
    if ($vmp.NeedsReboot) { $needsReboot = $true }

    # --- Step 2: Ensure Microsoft-Windows-Subsystem-Linux is enabled ---
    $wslFeature = Enable-WindowsFeatureSafe "Microsoft-Windows-Subsystem-Linux"
    if (-not $wslFeature.Success) {
        return @{ Ready = $false; Message = $wslFeature.Message }
    }
    if ($wslFeature.NeedsReboot) { $needsReboot = $true }

    if ($needsReboot) {
        return @{ Ready = $false; NeedsReboot = $true; Message = "Windows features enabled. A reboot is required before WSL2 can be used." }
    }

    # --- Step 3: Verify WSL is functional ---
    try {
        $status = wsl --status 2>&1
        if ($LASTEXITCODE -ne 0) {
            $list = wsl --list --quiet 2>&1
            if ($LASTEXITCODE -ne 0) {
                return @{ Ready = $false; Message = "WSL is installed but not functional. Try running 'wsl --install --no-distribution' manually and reboot." }
            }
        }
    }
    catch {
        return @{ Ready = $false; Message = "WSL command not found. Run 'wsl --install --no-distribution' from an admin PowerShell and reboot." }
    }

    # --- Step 4: Set WSL2 as default ---
    try {
        wsl --set-default-version 2 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return @{
                Ready = $false
                Message = "Failed to set WSL2 as default version (exit code $LASTEXITCODE). Possible causes:`n" +
                          "  - VirtualMachinePlatform is enabled but the WSL2 kernel is not installed.`n" +
                          "  - Run 'wsl --update' from an admin PowerShell and retry."
            }
        }
    }
    catch {
        return @{ Ready = $false; Message = "wsl --set-default-version 2 failed: $_" }
    }

    return @{ Ready = $true; Message = "WSL2 is ready" }
}

# --- Main ---
$result = Test-WSL2

if ($result.Ready) {
    Write-Host "OK: $($result.Message)" -ForegroundColor Green
    exit 0
}
elseif ($result.NeedsReboot) {
    Write-Host "REBOOT REQUIRED: $($result.Message)" -ForegroundColor Yellow
    # Exit 3010 = ERROR_SUCCESS_REBOOT_REQUIRED, a standard Windows installer exit code
    exit 3010
}
else {
    Write-Host "ERROR: $($result.Message)" -ForegroundColor Red
    exit 1
}
