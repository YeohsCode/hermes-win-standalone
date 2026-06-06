# import-distro.ps1 - Import HermesLinux WSL2 distribution
# Called during installation after WSL2 is confirmed ready.
# Exits non-zero on any critical failure.

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"

$DistroName = "HermesLinux"
$WslDir = Join-Path $InstallDir "wsl"
$DistroDir = Join-Path $InstallDir "wsl-data"
$CoreRootfs = Join-Path $WslDir "rootfs-core.tar.gz"

Write-Host "Setting up HermesLinux WSL2 distribution..." -ForegroundColor Yellow

# --- Step 1: Unregister existing distro ---
$existingDistros = wsl --list --quiet 2>&1
if ($existingDistros -match $DistroName) {
    Write-Host "  HermesLinux already registered, unregistering old version..."
    wsl --unregister $DistroName 2>&1 | Out-Null
}

# --- Step 2: Prepare directories ---
if (-not (Test-Path $DistroDir)) {
    New-Item -ItemType Directory -Path $DistroDir -Force | Out-Null
}

# --- Step 3: Import the core rootfs ---
Write-Host "  Importing core rootfs (this may take a few minutes)..."
if (-not (Test-Path $CoreRootfs)) {
    Write-Host "ERROR: Core rootfs not found at $CoreRootfs" -ForegroundColor Red
    exit 1
}

wsl --import $DistroName $DistroDir $CoreRootfs --version 2
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to import WSL distribution (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

Write-Host "  Core distribution imported successfully" -ForegroundColor Green

# --- Step 4: Verify distro is WSL2 and functional ---
Write-Host "  Verifying distro version and functionality..."

# Parse wsl --list --verbose to check VERSION column
$verbose = wsl --list --verbose 2>&1 | Out-String
$wslVersion = 0
foreach ($line in ($verbose -split "`n")) {
    if ($line -match "$DistroName\s+\w+\s+(\d+)") {
        $wslVersion = [int]$Matches[1]
        break
    }
}

if ($wslVersion -eq 1) {
    Write-Host "  WARNING: HermesLinux was imported as WSL1 — converting to WSL2..." -ForegroundColor Yellow
    wsl --set-version $DistroName 2 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to convert HermesLinux to WSL2. Check VirtualMachinePlatform and WSL kernel." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Converted to WSL2 successfully" -ForegroundColor Green
}
elseif ($wslVersion -ne 2) {
    Write-Host "WARNING: Could not determine WSL version for HermesLinux (parsed=$wslVersion). Proceeding anyway." -ForegroundColor Yellow
}

# Verify the distro boots and has a working userspace
$verifyOut = wsl -d $DistroName --exec cat /etc/os-release 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: HermesLinux imported but cannot start. Output:" -ForegroundColor Red
    Write-Host $verifyOut
    exit 1
}
Write-Host "  Distro boots successfully" -ForegroundColor Green

# --- Step 5: Install optional layers ---
$layers = @("browser", "voice", "messaging")
foreach ($layer in $layers) {
    $layerFile = Join-Path $WslDir "layer-${layer}.tar.gz"
    if (Test-Path $layerFile) {
        Write-Host "  Installing ${layer} layer..."
        if ($layerFile -match '^([A-Za-z]):(.*)') {
            $drive = $Matches[1].ToLower()
            $rest = $Matches[2] -replace '\\', '/'
            $wslPath = "/mnt/${drive}${rest}"
        }

        wsl -d $DistroName -- bash /opt/hermes/scripts/install-layer.sh $layer $wslPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ${layer} layer installed" -ForegroundColor Green
        } else {
            Write-Host "    WARNING: ${layer} layer installation failed (non-fatal)" -ForegroundColor Yellow
        }
    }
}

# --- Step 6: Write wsl.conf and terminate to apply ---
Write-Host "  Configuring wsl.conf..."
wsl -d $DistroName -- bash -c "cat > /etc/wsl.conf << 'WSLEOF'
[user]
default=root

[boot]
systemd=false
WSLEOF"

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Failed to write wsl.conf" -ForegroundColor Yellow
}

# Terminate and restart to ensure wsl.conf takes effect
Write-Host "  Restarting distro to apply wsl.conf..."
wsl --terminate $DistroName 2>&1 | Out-Null
Start-Sleep -Seconds 2

# Quick verification that the distro still boots after terminate
$postTerminate = wsl -d $DistroName --exec whoami 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Distro did not restart cleanly after terminate. Output: $postTerminate" -ForegroundColor Yellow
}
else {
    $user = ($postTerminate | Out-String).Trim()
    if ($user -eq "root") {
        Write-Host "  wsl.conf applied — default user is root" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: default user is '$user' instead of root" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "HermesLinux setup complete!" -ForegroundColor Green
exit 0
