# test-install.ps1 - End-to-end installation test for Hermes Windows Offline Installer
# Run on a clean Windows 10/11 machine.
# Usage: powershell -ExecutionPolicy Bypass -File test-install.ps1 -InstallerPath .\HermesSetup.exe

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

Write-Host "=== Hermes Windows Offline Installer - E2E Test ===" -ForegroundColor Yellow
Write-Host ""

# Test 1: Run installer (silent mode)
if ($InstallerPath) {
    Test-Step "Run Installer" {
        if (-not (Test-Path $InstallerPath)) { throw "Installer not found: $InstallerPath" }
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList "/SILENT /SUPPRESSMSGBOXES" -Wait -PassThru
        if ($proc.ExitCode -ne 0) { throw "Installer exited with code $($proc.ExitCode)" }
    }
}

# Test 2: Verify Electron Desktop App installed
Test-Step "Hermes Desktop App Installed" {
    $exePath = Join-Path $env:ProgramFiles "Hermes\Hermes.exe"
    if (-not (Test-Path $exePath)) {
        $exePath = Join-Path ${env:ProgramFiles(x86)} "Hermes\Hermes.exe"
    }
    if (-not (Test-Path $exePath)) { throw "Hermes.exe not found in Program Files" }
    Write-Host "  Found at: $exePath"
}

# Test 3: Verify HERMES_HOME set
Test-Step "HERMES_HOME Set" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    if (-not $hermesHome) { throw "HERMES_HOME not set" }
    Write-Host "  HERMES_HOME = $hermesHome"
}

# Test 4: Verify hermes-agent source root
Test-Step "Agent Source Root Present" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $mainPy = Join-Path $hermesHome "hermes-agent\hermes_cli\main.py"
    if (-not (Test-Path $mainPy)) { throw "hermes_cli/main.py not found" }
}

# Test 5: Verify Python venv
Test-Step "Python Venv Working" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $python = Join-Path $hermesHome "hermes-agent\venv\Scripts\python.exe"
    if (-not (Test-Path $python)) { throw "venv python.exe not found" }
    $version = & $python --version 2>&1
    Write-Host "  Python version: $version"
}

# Test 6: Verify hermes CLI
Test-Step "Hermes CLI Available" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $hermes = Join-Path $hermesHome "hermes-agent\venv\Scripts\hermes.exe"
    if (-not (Test-Path $hermes)) { throw "hermes.exe not found in venv" }
    $version = & $hermes --version 2>&1
    Write-Host "  Hermes version: $version"
}

# Test 7: Verify bootstrap-complete marker
Test-Step "Bootstrap Marker Present" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $marker = Join-Path $hermesHome "hermes-agent\.hermes-bootstrap-complete"
    if (-not (Test-Path $marker)) { throw "Bootstrap marker not found" }
    $content = Get-Content $marker -Raw | ConvertFrom-Json
    if ($content.schemaVersion -ne 1) { throw "Invalid marker schema version" }
    Write-Host "  Marker OK (commit: $($content.pinnedCommit))"
}

# Test 8: Verify PortableGit
Test-Step "PortableGit Available" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $git = Join-Path $hermesHome "git\cmd\git.exe"
    if (-not (Test-Path $git)) { throw "git.exe not found" }
    $version = & $git --version 2>&1
    Write-Host "  Git version: $version"
}

# Test 9: Verify PATH entries
Test-Step "PATH Entries Set" {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $venvScripts = Join-Path $hermesHome "hermes-agent\venv\Scripts"
    if ($userPath -notlike "*$venvScripts*") { throw "Venv Scripts not in PATH" }
    Write-Host "  PATH includes venv Scripts"
}

# Test 10: Start hermes dashboard (quick smoke test)
Test-Step "Dashboard Starts" {
    $hermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    $hermes = Join-Path $hermesHome "hermes-agent\venv\Scripts\hermes.exe"
    $proc = Start-Process -FilePath $hermes -ArgumentList "dashboard", "--no-open", "--port", "9199" -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 10

    $success = $false
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:9199/api/status" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                $success = $true
                break
            }
        } catch {}
        Start-Sleep -Seconds 2
    }

    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not $success) { throw "Dashboard did not respond on port 9199" }
    Write-Host "  Dashboard responded OK"
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
