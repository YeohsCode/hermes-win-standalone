# test-install.ps1 - End-to-end installation test
# Run on a clean Windows 11 machine with WSL2 enabled
# Usage: powershell -ExecutionPolicy Bypass -File test-install.ps1

param(
    [string]$InstallerPath = "",
    [switch]$SkipUninstall
)

$ErrorActionPreference = "Stop"
$TestResults = @()

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "`n[$Name]" -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "  PASS" -ForegroundColor Green
        $script:TestResults += @{ Name = $Name; Status = "PASS" }
    }
    catch {
        Write-Host "  FAIL: $_" -ForegroundColor Red
        $script:TestResults += @{ Name = $Name; Status = "FAIL"; Error = $_.ToString() }
    }
}

Write-Host "=== Hermes Windows Standalone - E2E Test ===" -ForegroundColor Yellow
Write-Host ""

# Test 1: WSL2 prerequisite
Test-Step "WSL2 Available" {
    $result = wsl --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw "WSL2 not available" }
}

# Test 2: Run installer (silent mode)
if ($InstallerPath) {
    Test-Step "Run Installer" {
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList "/SILENT /SUPPRESSMSGBOXES" -Wait -PassThru
        if ($proc.ExitCode -ne 0) { throw "Installer exited with code $($proc.ExitCode)" }
    }
}

# Test 3: Verify HermesLinux distro registered
Test-Step "HermesLinux Distro Registered" {
    $distros = wsl --list --quiet 2>&1
    if ($distros -notmatch "HermesLinux") { throw "HermesLinux not found in WSL distros" }
}

# Test 4: Verify core files in distro
Test-Step "Core Files Present" {
    $result = wsl -d HermesLinux -- ls /opt/hermes/hermes-agent/pyproject.toml 2>&1
    if ($LASTEXITCODE -ne 0) { throw "hermes-agent not found in distro" }

    $result = wsl -d HermesLinux -- ls /opt/hermes/hermes-webui/server.py 2>&1
    if ($LASTEXITCODE -ne 0) { throw "hermes-webui not found in distro" }
}

# Test 5: Verify Python venv
Test-Step "Python Venv Working" {
    $result = wsl -d HermesLinux -- /opt/hermes/venv/bin/python --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Python venv not working" }
    Write-Host "  Python version: $result"
}

# Test 6: Verify hermes-agent importable
Test-Step "Hermes Agent Importable" {
    $result = wsl -d HermesLinux -- /opt/hermes/venv/bin/python -c "from run_agent import AIAgent; print('OK')" 2>&1
    if ($result -notmatch "OK") { throw "Cannot import AIAgent: $result" }
}

# Test 7: Start services
Test-Step "Start Services" {
    wsl -d HermesLinux -- bash /opt/hermes/scripts/start-services.sh 8787
    if ($LASTEXITCODE -ne 0) { throw "Failed to start services" }
    Start-Sleep -Seconds 5
}

# Test 8: WebUI responds
Test-Step "WebUI Health Check" {
    $maxRetries = 10
    $success = $false
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8787/health" -TimeoutSec 5 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                $success = $true
                break
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
    if (-not $success) { throw "WebUI did not respond after $maxRetries retries" }
}

# Test 9: Stop services
Test-Step "Stop Services" {
    wsl -d HermesLinux -- bash /opt/hermes/scripts/stop-services.sh
    if ($LASTEXITCODE -ne 0) { throw "Failed to stop services" }
}

# Test 10: Uninstall
if (-not $SkipUninstall) {
    Test-Step "Uninstall Clean" {
        wsl --unregister HermesLinux 2>&1 | Out-Null
        $distros = wsl --list --quiet 2>&1
        if ($distros -match "HermesLinux") { throw "HermesLinux still registered after uninstall" }
    }
}

# Summary
Write-Host "`n=== Test Results ===" -ForegroundColor Yellow
$passed = 0
$failed = 0
foreach ($result in $TestResults) {
    $color = if ($result.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  [$($result.Status)] $($result.Name)" -ForegroundColor $color
    if ($result.Status -eq "PASS") { $passed++ } else { $failed++ }
}
Write-Host "`nTotal: $($TestResults.Count) | Passed: $passed | Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) { exit 1 }
exit 0
