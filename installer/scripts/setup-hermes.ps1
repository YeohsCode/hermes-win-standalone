# setup-hermes.ps1 - Configure Hermes Agent after offline installation
# Called by Inno Setup post-install. Sets up PATH, HERMES_HOME, and writes
# the bootstrap-complete marker so the Electron Desktop App skips first-launch
# bootstrap (which would need internet).

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"

$HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
$AgentRoot = Join-Path $HermesHome "hermes-agent"
$VenvScripts = Join-Path $AgentRoot "venv\Scripts"
$GitDir = Join-Path $HermesHome "git"
$GitBinDir = Join-Path $GitDir "bin"
$GitCmdDir = Join-Path $GitDir "cmd"

Write-Host "Configuring Hermes Agent..." -ForegroundColor Yellow

# --- Step 0: Fix venv pyvenv.cfg for portable venv (v3.0.1+) ---
# Build writes `home = python` (relative, points to venv\python\ embedded interpreter).
# That works for hermes.exe, but Scripts\python.exe launcher (a copy of base Python.exe)
# only resolves `home` relative to CWD, not the venv location. So when user runs
# `python` from any non-venv CWD, the launcher fails with "No Python at 'python\python.exe'".
# Fix: rewrite `home` to the absolute embedded-Python path so it works from anywhere.
Write-Host "  Patching venv pyvenv.cfg (portable home path)..."
$VenvRoot = Join-Path $AgentRoot "venv"
$pyvenvCfg = Join-Path $VenvRoot "pyvenv.cfg"
$embeddedPyDir = Join-Path $VenvRoot "python"
if (Test-Path $pyvenvCfg) {
    $cfgLines = Get-Content $pyvenvCfg
    $newCfg = $cfgLines -replace '^(\s*home\s*=\s*).*$', ('$1' + $embeddedPyDir)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($pyvenvCfg, ($newCfg -join "`r`n"), $utf8NoBom)
    Write-Host "    pyvenv.cfg home -> $embeddedPyDir" -ForegroundColor Gray
} else {
    Write-Host "    pyvenv.cfg not found at $pyvenvCfg (skipped)" -ForegroundColor Yellow
}

# --- Step 0b: Relocate uv script launchers (binary path patching) ---
# uv embeds absolute Python paths in console-script .exe trampolines.
# Replace the build-time venv path with the install-time path so hermes.exe
# and friends find python.exe at the new location.
$buildPathMarker = Join-Path $VenvRoot ".build-path"
if (Test-Path $buildPathMarker) {
    $buildVenvPath = (Get-Content $buildPathMarker -Raw).Trim()
    $targetVenvPath = $VenvRoot
    if ($buildVenvPath -ne $targetVenvPath) {
        Write-Host "  Relocating venv script launchers..."
        Write-Host "    from: $buildVenvPath" -ForegroundColor Gray
        Write-Host "    to:   $targetVenvPath" -ForegroundColor Gray
        $buildBytes = [System.Text.Encoding]::UTF8.GetBytes($buildVenvPath)
        $targetBytes = [System.Text.Encoding]::UTF8.GetBytes($targetVenvPath)
        # Pad target with NULs if shorter than build path so the exe size stays the same
        if ($targetBytes.Length -lt $buildBytes.Length) {
            $padded = New-Object byte[] $buildBytes.Length
            [Array]::Copy($targetBytes, $padded, $targetBytes.Length)
            $targetBytes = $padded
        }
        $patched = 0
        Get-ChildItem (Join-Path $VenvRoot "Scripts\*.exe") | ForEach-Object {
            if ($_.Name -match '^(python|pythonw|python3)\.exe$') { return }
            $raw = [System.IO.File]::ReadAllBytes($_.FullName)
            $rawStr = [System.Text.Encoding]::UTF8.GetString($raw)
            if ($rawStr.Contains($buildVenvPath)) {
                $newStr = $rawStr.Replace($buildVenvPath, $targetVenvPath)
                $newBytes = [System.Text.Encoding]::UTF8.GetBytes($newStr)
                [System.IO.File]::WriteAllBytes($_.FullName, $newBytes)
                $patched++
            }
        }
        Write-Host "    Patched $patched script launchers" -ForegroundColor Gray
    } else {
        Write-Host "  Venv paths match build-time path (no relocation needed)"
    }
    Remove-Item $buildPathMarker -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  No .build-path marker found (skipping launcher relocation)" -ForegroundColor Yellow
}

# --- Step 1: Set HERMES_HOME ---
Write-Host "  Setting HERMES_HOME..."
[Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
$env:HERMES_HOME = $HermesHome

# --- Step 2: Add venv Scripts and Git to PATH ---
Write-Host "  Updating PATH..."
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathsToAdd = @($VenvScripts)

if (Test-Path $GitBinDir) {
    $pathsToAdd += $GitBinDir
    $bashExe = Join-Path $GitBinDir "bash.exe"
    if (Test-Path $bashExe) {
        [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $bashExe, "User")
    }
}

foreach ($p in $pathsToAdd) {
    if ($userPath -notlike "*$p*") {
        $userPath = "$p;$userPath"
    }
}
[Environment]::SetEnvironmentVariable("Path", $userPath, "User")

# --- Step 3: Create HERMES_HOME directories ---
Write-Host "  Creating data directories..."
$dirs = @("logs", "sessions", "skills")
foreach ($d in $dirs) {
    $dirPath = Join-Path $HermesHome $d
    if (-not (Test-Path $dirPath)) {
        New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
    }
}

# --- Step 4: Create default config if missing ---
$configFile = Join-Path $HermesHome "config.yaml"
if (-not (Test-Path $configFile)) {
    Write-Host "  Creating default config.yaml..."
    $configContent = @"
# Hermes Agent Configuration
# See https://github.com/NousResearch/hermes-agent for documentation
"@
    [System.IO.File]::WriteAllText($configFile, $configContent, [System.Text.UTF8Encoding]::new($false))
}

$envFile = Join-Path $HermesHome ".env"
if (-not (Test-Path $envFile)) {
    Write-Host "  Creating default .env..."
    $envContent = @"
# Hermes Agent Environment Variables
# Add your API keys and tokens here
# Example:
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
"@
    [System.IO.File]::WriteAllText($envFile, $envContent, [System.Text.UTF8Encoding]::new($false))
}

# --- Step 5: Write bootstrap-complete marker ---
# The Electron Desktop App checks this marker to skip first-launch bootstrap.
# Format must match upstream's writeBootstrapMarker() in electron/main.cjs.
Write-Host "  Writing bootstrap-complete marker..."
$markerPath = Join-Path $AgentRoot ".hermes-bootstrap-complete"

$commitHash = "offline-install"
$gitExe = Join-Path $GitCmdDir "git.exe"
if (Test-Path $gitExe) {
    try {
        $result = & $gitExe -C $AgentRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $result) {
            $commitHash = $result.Trim()
        }
    } catch { }
}

$marker = @{
    schemaVersion = 1
    pinnedCommit = $commitHash
    pinnedBranch = "main"
    completedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
    desktopVersion = "offline-installer"
    offlineInstall = $true
} | ConvertTo-Json -Depth 2

[System.IO.File]::WriteAllText($markerPath, $marker, [System.Text.UTF8Encoding]::new($false))

# --- Step 6: Verify installation ---
Write-Host "  Verifying installation..."
$hermesExe = Join-Path $VenvScripts "hermes.exe"
$mainPy = Join-Path $AgentRoot "hermes_cli\main.py"
$venvPython = Join-Path $VenvScripts "python.exe"

$ok = $true
if (Test-Path $hermesExe) {
    Write-Host "    hermes.exe: OK" -ForegroundColor Green
} else {
    Write-Host "    hermes.exe: MISSING at $hermesExe" -ForegroundColor Yellow
    $ok = $false
}

if (Test-Path $mainPy) {
    Write-Host "    hermes_cli/main.py: OK" -ForegroundColor Green
} else {
    Write-Host "    hermes_cli/main.py: MISSING" -ForegroundColor Yellow
    $ok = $false
}

if (Test-Path $venvPython) {
    Write-Host "    venv python.exe: OK" -ForegroundColor Green
} else {
    Write-Host "    venv python.exe: MISSING" -ForegroundColor Yellow
    $ok = $false
}

if (Test-Path $markerPath) {
    Write-Host "    bootstrap marker: OK" -ForegroundColor Green
} else {
    Write-Host "    bootstrap marker: MISSING" -ForegroundColor Yellow
    $ok = $false
}

Write-Host ""
if ($ok) {
    Write-Host "Hermes Agent setup complete!" -ForegroundColor Green
} else {
    Write-Host "Hermes Agent setup completed with warnings." -ForegroundColor Yellow
    Write-Host "Some components may not have installed correctly." -ForegroundColor Yellow
}
exit 0
