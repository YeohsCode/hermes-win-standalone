# import-distro.ps1 - Import HermesLinux WSL2 distribution
# Called during installation after WSL2 is confirmed ready

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

# Check if distro already exists
$existingDistros = wsl --list --quiet 2>&1
if ($existingDistros -match $DistroName) {
    Write-Host "  HermesLinux already registered, unregistering old version..."
    wsl --unregister $DistroName 2>&1 | Out-Null
}

# Create directory for WSL data
if (-not (Test-Path $DistroDir)) {
    New-Item -ItemType Directory -Path $DistroDir -Force | Out-Null
}

# Import the core rootfs as a new WSL distribution
Write-Host "  Importing core rootfs (this may take a few minutes)..."
if (-not (Test-Path $CoreRootfs)) {
    Write-Host "ERROR: Core rootfs not found at $CoreRootfs" -ForegroundColor Red
    exit 1
}

wsl --import $DistroName $DistroDir $CoreRootfs
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to import WSL distribution" -ForegroundColor Red
    exit 1
}

Write-Host "  Core distribution imported successfully" -ForegroundColor Green

# Install optional layers if present
$layers = @("browser", "voice", "messaging")
foreach ($layer in $layers) {
    $layerFile = Join-Path $WslDir "layer-${layer}.tar.gz"
    if (Test-Path $layerFile) {
        Write-Host "  Installing ${layer} layer..."
        # Convert Windows path to WSL path for the tar file
        $wslPath = $layerFile -replace '\\', '/'
        $wslPath = $wslPath -replace '^([A-Z]):', '/mnt/$1'.ToLower()
        # Fix: properly convert drive letter
        if ($layerFile -match '^([A-Za-z]):(.*)') {
            $drive = $Matches[1].ToLower()
            $rest = $Matches[2] -replace '\\', '/'
            $wslPath = "/mnt/${drive}${rest}"
        }

        wsl -d $DistroName -- bash /opt/hermes/scripts/install-layer.sh $layer $wslPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ${layer} layer installed" -ForegroundColor Green
        } else {
            Write-Host "    WARNING: ${layer} layer installation failed" -ForegroundColor Yellow
        }
    }
}

# Set default user to root (hermes services run as root)
wsl -d $DistroName -- bash -c "echo '[user]' > /etc/wsl.conf && echo 'default=root' >> /etc/wsl.conf"

Write-Host ""
Write-Host "HermesLinux setup complete!" -ForegroundColor Green
exit 0
