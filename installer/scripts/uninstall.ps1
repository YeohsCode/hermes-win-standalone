# uninstall.ps1 - Clean uninstall of Hermes
# Removes Hermes configuration and cleans up environment.
# User data at %LOCALAPPDATA%\hermes is preserved by default.

param(
    [string]$InstallDir = ""
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Uninstalling Hermes..." -ForegroundColor Yellow

# Stop any running Hermes processes
Write-Host "  Stopping Hermes processes..."
Get-Process -Name "Hermes" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "hermes*" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "pythonw" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*hermes*" } |
    Stop-Process -Force

# Remove gateway scheduled task if it exists
Write-Host "  Removing scheduled tasks..."
schtasks /Delete /TN "Hermes_Gateway" /F 2>&1 | Out-Null

# Remove autostart registry entry
Write-Host "  Cleaning up registry..."
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Hermes" -ErrorAction SilentlyContinue

# Remove PATH entries
Write-Host "  Cleaning PATH..."
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) {
    $hermesHome = Join-Path $env:LOCALAPPDATA "hermes"
    $venvScripts = Join-Path $hermesHome "hermes-agent\venv\Scripts"
    $gitBinDir = Join-Path $hermesHome "git\bin"

    # Also clean legacy paths from older installs
    $legacyVenv = if ($InstallDir) { Join-Path $InstallDir "hermes\venv\Scripts" } else { "" }
    $legacyGit = if ($InstallDir) { Join-Path $InstallDir "hermes\PortableGit\bin" } else { "" }

    $parts = $userPath -split ";" | Where-Object {
        $_ -ne $venvScripts -and
        $_ -ne $gitBinDir -and
        ($legacyVenv -eq "" -or $_ -ne $legacyVenv) -and
        ($legacyGit -eq "" -or $_ -ne $legacyGit) -and
        $_.Trim() -ne ""
    }
    [Environment]::SetEnvironmentVariable("Path", ($parts -join ";"), "User")
}

# Remove environment variables
[Environment]::SetEnvironmentVariable("HERMES_HOME", $null, "User")
[Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $null, "User")

# Clean up startup folder fallback if any
$startupDir = [Environment]::GetFolderPath("Startup")
Remove-Item -Path (Join-Path $startupDir "Hermes_Gateway*.cmd") -Force -ErrorAction SilentlyContinue

Write-Host "  Note: User data at %LOCALAPPDATA%\hermes has been preserved."
Write-Host "  Delete it manually if you want a complete removal."

Write-Host "Hermes uninstalled successfully" -ForegroundColor Green
