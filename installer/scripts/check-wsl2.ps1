# check-wsl2.ps1 - Verify WSL2 is properly configured
# Called during installation to validate environment

$ErrorActionPreference = "Stop"

function Test-WSL2 {
    try {
        $version = wsl --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @{ Ready = $false; Message = "WSL is not installed" }
        }

        # Check if WSL2 is the default version
        $status = wsl --status 2>&1
        if ($status -match "Default Version: 2" -or $status -match "默认版本: 2") {
            return @{ Ready = $true; Message = "WSL2 is ready" }
        }

        # Try setting WSL2 as default
        wsl --set-default-version 2 2>&1 | Out-Null
        return @{ Ready = $true; Message = "WSL2 configured as default" }
    }
    catch {
        return @{ Ready = $false; Message = "WSL2 check failed: $_" }
    }
}

$result = Test-WSL2

if ($result.Ready) {
    Write-Host "OK: $($result.Message)" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "ERROR: $($result.Message)" -ForegroundColor Red
    exit 1
}
