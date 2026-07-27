# build-local.ps1 — Local build script for Hermes Windows Offline Installer
#
# Replicates the CI pipeline (build-release.yml) on a local Windows machine.
# Produces: build/HermesSetup-*.exe
#
# Prerequisites: Python 3.11+, Node.js 22+, npm, git
# Auto-installs: uv, Inno Setup 6 (if missing)
#
# Usage:
#   .\scripts\build-local.ps1                     # full build
#   .\scripts\build-local.ps1 -SkipElectron       # skip Electron app build
#   .\scripts\build-local.ps1 -SkipRuntime        # skip runtime bundle build
#   .\scripts\build-local.ps1 -SkipInstaller      # skip Inno Setup packaging
#   .\scripts\build-local.ps1 -AgentVersion v2026.7.20  # override agent version
#   .\scripts\build-local.ps1 -ElectronMirror "https://npmmirror.com/mirrors/electron/"

param(
    [string]$AgentVersion = "v2026.7.20",
    [string]$ElectronMirror = "https://npmmirror.com/mirrors/electron/",
    [switch]$SkipRuntime,
    [switch]$SkipElectron,
    [switch]$SkipInstaller,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "build"

function Write-Step([string]$msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
}

function Assert-Command([string]$cmd, [string]$name) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$name ($cmd) not found in PATH. Please install it first."
    }
}

# ─── Clean ───────────────────────────────────────────────────────────
if ($Clean) {
    Write-Step "Cleaning build directory"
    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
        Write-Ok "Removed $BuildDir"
    } else {
        Write-Ok "Nothing to clean"
    }
}

# ─── Prerequisites ───────────────────────────────────────────────────
Write-Step "Checking prerequisites"

Assert-Command "python" "Python"
$pyVer = python --version 2>&1
Write-Ok "Python: $pyVer"

Assert-Command "node" "Node.js"
$nodeVer = node --version 2>&1
Write-Ok "Node.js: $nodeVer"

Assert-Command "npm" "npm"
$npmVer = npm --version 2>&1
Write-Ok "npm: $npmVer"

Assert-Command "git" "Git"
$gitVer = git --version 2>&1
Write-Ok "Git: $gitVer"

# Install uv if missing
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Step "Installing uv"
    irm https://astral.sh/uv/install.ps1 | iex
    $uvBin = Join-Path $env:USERPROFILE ".local\bin"
    if (Test-Path $uvBin) {
        $env:PATH = "$uvBin;$env:PATH"
    }
    $cargoUvBin = Join-Path $env:USERPROFILE ".cargo\bin"
    if (Test-Path (Join-Path $cargoUvBin "uv.exe")) {
        $env:PATH = "$cargoUvBin;$env:PATH"
    }
    if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
        throw "uv installation failed. Please install manually: https://docs.astral.sh/uv/getting-started/installation/"
    }
}
$uvVer = uv --version 2>&1
Write-Ok "uv: $uvVer"

# Check Inno Setup (needed only for installer step)
$InnoSetupPath = $null
$innoCandidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
)
foreach ($c in $innoCandidates) {
    if (Test-Path $c) {
        $InnoSetupPath = $c
        break
    }
}
if (-not $InnoSetupPath -and -not $SkipInstaller) {
    Write-Warn "Inno Setup 6 not found. Will attempt to install via winget."
    try {
        winget install --id JRSoftware.InnoSetup -e --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        foreach ($c in $innoCandidates) {
            if (Test-Path $c) { $InnoSetupPath = $c; break }
        }
    } catch {}
    if (-not $InnoSetupPath) {
        Write-Warn "Auto-install failed. Please install Inno Setup 6 from https://jrsoftware.org/isinfo.php"
        Write-Warn "Continuing build — installer packaging will be skipped."
        $SkipInstaller = $true
    }
}
if ($InnoSetupPath) {
    Write-Ok "Inno Setup: $InnoSetupPath"
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# ─── Stage 1: Build Runtime Bundle ───────────────────────────────────
if (-not $SkipRuntime) {
    Write-Step "Stage 1/3: Building Runtime Bundle"

    $runtimeDir = Join-Path $BuildDir "runtime-bundle"
    $hermesSrcDir = Join-Path $BuildDir "hermes-src"

    # Download hermes-agent source
    $tarball = Join-Path $BuildDir "agent.tar.gz"
    if (-not (Test-Path $tarball)) {
        Write-Host "  Downloading hermes-agent $AgentVersion..."
        $downloadUrl = "https://github.com/NousResearch/hermes-agent/archive/refs/tags/$AgentVersion.tar.gz"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tarball -UseBasicParsing
        Write-Ok "Downloaded agent source"
    } else {
        Write-Ok "Agent source tarball already exists, skipping download"
    }

    # Extract
    if (Test-Path $hermesSrcDir) { Remove-Item -Recurse -Force $hermesSrcDir }
    New-Item -ItemType Directory -Force -Path $hermesSrcDir | Out-Null
    Write-Host "  Extracting source..."
    tar xzf $tarball -C $hermesSrcDir
    $extracted = Get-ChildItem $hermesSrcDir | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    if ($extracted.Name -ne "hermes-agent") {
        Rename-Item $extracted.FullName "hermes-agent"
    }
    Write-Ok "Extracted to $hermesSrcDir\hermes-agent"

    # Copy source to runtime bundle
    $targetRoot = Join-Path $runtimeDir "hermes-agent"
    if (Test-Path $targetRoot) { Remove-Item -Recurse -Force $targetRoot }
    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
    Copy-Item -Recurse (Join-Path $hermesSrcDir "hermes-agent\*") $targetRoot
    Write-Ok "Copied source tree to runtime bundle"

    # Create venv and install
    Write-Host "  Creating Python venv..."
    uv venv (Join-Path $targetRoot "venv") --python 3.11
    Write-Ok "Created venv"

    Write-Host "  Installing hermes-agent (this may take several minutes)..."
    $installSpec = "${targetRoot}[all,web]"
    uv pip install --python (Join-Path $targetRoot "venv\Scripts\python.exe") `
        $installSpec `
        --no-cache-dir
    Write-Ok "Installed hermes-agent"

    # Verify
    $hermesExe = Join-Path $targetRoot "venv\Scripts\hermes.exe"
    if (Test-Path $hermesExe) {
        $ver = & $hermesExe --version 2>&1
        Write-Ok "hermes.exe verified: $ver"
    } else {
        throw "hermes.exe not found at $hermesExe after install"
    }

    $mainPy = Join-Path $targetRoot "hermes_cli\main.py"
    if (Test-Path $mainPy) {
        Write-Ok "Source root marker (hermes_cli/main.py) present"
    } else {
        throw "hermes_cli/main.py not found — source root detection will fail"
    }

    # Download PortableGit
    $gitDir = Join-Path $runtimeDir "git"
    if (-not (Test-Path (Join-Path $gitDir "bin\git.exe"))) {
        Write-Host "  Downloading PortableGit..."
        $gitExe = Join-Path $BuildDir "PortableGit.exe"
        if (-not (Test-Path $gitExe)) {
            $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/PortableGit-2.47.1-64-bit.7z.exe"
            Invoke-WebRequest -Uri $gitUrl -OutFile $gitExe -UseBasicParsing
        }
        New-Item -ItemType Directory -Force -Path $gitDir | Out-Null
        Write-Host "  Extracting PortableGit (this takes a moment)..."
        Start-Process -FilePath $gitExe -ArgumentList "-o", $gitDir, "-y" -Wait
        Write-Ok "PortableGit installed"
    } else {
        Write-Ok "PortableGit already present, skipping"
    }

    Write-Host "`n  Runtime bundle ready at: $runtimeDir" -ForegroundColor Green
} else {
    Write-Ok "Skipping runtime bundle (--SkipRuntime)"
}

# ─── Stage 2: Build Electron App ─────────────────────────────────────
if (-not $SkipElectron) {
    Write-Step "Stage 2/3: Building Electron Desktop App"

    $electronSrcDir = Join-Path $BuildDir "hermes-agent-electron"
    $electronOutDir = Join-Path $BuildDir "electron-app"

    # Clone upstream repo
    if (-not (Test-Path (Join-Path $electronSrcDir ".git"))) {
        Write-Host "  Cloning hermes-agent repo ($AgentVersion)..."
        if (Test-Path $electronSrcDir) { Remove-Item -Recurse -Force $electronSrcDir }
        git clone --depth 1 --branch $AgentVersion `
            "https://github.com/NousResearch/hermes-agent.git" `
            $electronSrcDir
        Write-Ok "Cloned hermes-agent"
    } else {
        Write-Ok "hermes-agent repo already cloned, skipping"
    }

    # Verify desktop app dir exists
    $desktopDir = Join-Path $electronSrcDir "apps\desktop"
    if (-not (Test-Path $desktopDir)) {
        throw "apps/desktop not found in hermes-agent repo. The upstream may have changed structure."
    }

    # Set Electron mirror to avoid download failures in China
    if ($ElectronMirror) {
        $env:ELECTRON_MIRROR = $ElectronMirror
        Write-Ok "Electron mirror: $ElectronMirror"
    }

    # Install workspace deps from repo root
    Write-Host "  Installing npm workspace dependencies..."
    Push-Location $electronSrcDir
    try {
        # Prefer npm ci for deterministic builds; fall back to npm install if lockfile is stale
        try {
            npm ci 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
            Write-Ok "npm ci complete"
        } catch {
            Write-Warn "npm ci failed, falling back to npm install..."
            npm install 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) { throw "npm install also failed" }
            Write-Ok "npm install complete"
        }
    } finally {
        Pop-Location
    }

    # Build unpacked Electron app
    Write-Host "  Building Electron app (npm run pack)..."
    Push-Location $desktopDir
    try {
        $env:GITHUB_SHA = "local-build"
        $env:GITHUB_REF_NAME = $AgentVersion
        npm run pack 2>&1 | ForEach-Object { Write-Host "    $_" }
        if ($LASTEXITCODE -ne 0) { throw "npm run pack failed" }
        Write-Ok "Electron app built"
    } finally {
        Pop-Location
        Remove-Item Env:\GITHUB_SHA -ErrorAction SilentlyContinue
        Remove-Item Env:\GITHUB_REF_NAME -ErrorAction SilentlyContinue
        Remove-Item Env:\ELECTRON_MIRROR -ErrorAction SilentlyContinue
    }

    # Copy to electron-app output dir
    $winUnpacked = Join-Path $desktopDir "release\win-unpacked"
    if (-not (Test-Path $winUnpacked)) {
        $releaseDir = Join-Path $desktopDir "release"
        Write-Warn "win-unpacked not found at expected path. Scanning release dir:"
        if (Test-Path $releaseDir) {
            Get-ChildItem $releaseDir | ForEach-Object { Write-Host "    $_" }
        }
        throw "Electron app output not found at $winUnpacked"
    }

    if (Test-Path $electronOutDir) { Remove-Item -Recurse -Force $electronOutDir }
    Copy-Item -Recurse $winUnpacked $electronOutDir
    Write-Ok "Electron app copied to $electronOutDir"

    $hermesDesktopExe = Join-Path $electronOutDir "Hermes.exe"
    if (Test-Path $hermesDesktopExe) {
        Write-Ok "Hermes.exe verified"
    } else {
        Write-Warn "Hermes.exe not found — the output exe name may differ from expected"
        Get-ChildItem $electronOutDir -Filter "*.exe" | ForEach-Object { Write-Host "    Found: $($_.Name)" }
    }

    Write-Host "`n  Electron app ready at: $electronOutDir" -ForegroundColor Green
} else {
    Write-Ok "Skipping Electron app build (--SkipElectron)"
}

# ─── Stage 3: Package Installer ──────────────────────────────────────
if (-not $SkipInstaller) {
    Write-Step "Stage 3/3: Packaging Installer with Inno Setup"

    if (-not $InnoSetupPath) {
        throw "Inno Setup not found. Install from https://jrsoftware.org/isinfo.php"
    }

    # Verify required artifacts exist
    $requiredPaths = @(
        (Join-Path $BuildDir "electron-app"),
        (Join-Path $BuildDir "runtime-bundle\hermes-agent"),
        (Join-Path $BuildDir "runtime-bundle\git")
    )
    foreach ($p in $requiredPaths) {
        if (-not (Test-Path $p)) {
            throw "Required artifact missing: $p. Run the full build first."
        }
    }

    # Install ChineseSimplified language file if missing
    $innoLangDir = Split-Path $InnoSetupPath
    $chineseLangFile = Join-Path $innoLangDir "Languages\ChineseSimplified.isl"
    if (-not (Test-Path $chineseLangFile)) {
        Write-Host "  Downloading ChineseSimplified.isl..."
        $langUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/Unofficial/ChineseSimplified.isl"
        Invoke-WebRequest -Uri $langUrl -OutFile $chineseLangFile -UseBasicParsing
        Write-Ok "ChineseSimplified.isl installed"
    }

    # Run Inno Setup compiler (quiet mode to avoid massive per-file log output)
    $issFile = Join-Path $ProjectRoot "installer\hermes-win.iss"
    Write-Host "  Compiling installer (this may take 10-20 minutes)..."
    & $InnoSetupPath /Q $issFile
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
    }

    $installer = Get-ChildItem (Join-Path $BuildDir "HermesSetup-*.exe") -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installer) {
        $sizeMB = [math]::Round($installer.Length / 1MB, 1)
        Write-Ok "Installer created: $($installer.Name) ($sizeMB MB)"
        Write-Host "`n  Output: $($installer.FullName)" -ForegroundColor Green
    } else {
        Write-Warn "Installer .exe not found in $BuildDir — check Inno Setup output above"
    }
} else {
    Write-Ok "Skipping installer packaging (--SkipInstaller)"
}

# ─── Summary ─────────────────────────────────────────────────────────
Write-Step "Build Summary"
Write-Host "  Agent Version:  $AgentVersion"
Write-Host "  Build Dir:      $BuildDir"

$artifacts = @(
    @{ Name = "Runtime Bundle"; Path = (Join-Path $BuildDir "runtime-bundle\hermes-agent\venv\Scripts\hermes.exe") },
    @{ Name = "PortableGit";    Path = (Join-Path $BuildDir "runtime-bundle\git\bin\git.exe") },
    @{ Name = "Electron App";   Path = (Join-Path $BuildDir "electron-app\Hermes.exe") },
    @{ Name = "Installer";      Path = (Join-Path $BuildDir "HermesSetup-*.exe") }
)

foreach ($a in $artifacts) {
    $found = $false
    if ($a.Path -like "*`**") {
        $found = (Get-ChildItem $a.Path -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    } else {
        $found = Test-Path $a.Path
    }
    if ($found) {
        Write-Ok "$($a.Name)"
    } else {
        Write-Warn "$($a.Name) — not built"
    }
}

Write-Host "`nDone!" -ForegroundColor Green
