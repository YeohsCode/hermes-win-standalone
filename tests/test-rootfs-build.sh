#!/bin/bash
# test-rootfs-build.sh - Test that Docker-based rootfs builds successfully
# Can run on any machine with Docker installed (Linux/macOS)
# Usage: ./test-rootfs-build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WSL_DIR="${PROJECT_DIR}/wsl-distro"

echo "=== Hermes Rootfs Build Test ==="
echo ""

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo "SKIP: Docker not available"
    exit 0
fi

echo "[1/4] Checking build context..."
if [ ! -d "${PROJECT_DIR}/../ref/hermes-agent" ]; then
    echo "SKIP: ref/hermes-agent not found (needed for build context)"
    echo "  This test requires the reference sources in ../ref/"
    exit 0
fi

echo "[2/4] Preparing build context..."
export AGENT_SRC="${PROJECT_DIR}/../ref/hermes-agent"
export WEBUI_SRC="${PROJECT_DIR}/../ref/hermes-webui"

# Only build core layer for testing (faster)
echo "[3/4] Building core rootfs..."
cd "${WSL_DIR}"
bash build-rootfs.sh core

echo "[4/4] Verifying output..."
if [ ! -f "${WSL_DIR}/output/rootfs-core.tar.gz" ]; then
    echo "FAIL: rootfs-core.tar.gz not generated"
    exit 1
fi

SIZE=$(du -h "${WSL_DIR}/output/rootfs-core.tar.gz" | cut -f1)
echo ""
echo "=== Test Results ==="
echo "  Core rootfs size: ${SIZE}"
echo "  PASS: rootfs-core.tar.gz generated successfully"
echo ""

# Verify rootfs contents
echo "Verifying rootfs contents..."
TEMP_DIR=$(mktemp -d)
tar xzf "${WSL_DIR}/output/rootfs-core.tar.gz" -C "${TEMP_DIR}" --include='opt/hermes/hermes-agent/pyproject.toml' --include='opt/hermes/hermes-webui/server.py' --include='opt/hermes/scripts/start-services.sh' 2>/dev/null || true

PASS=true
for f in "opt/hermes/hermes-agent/pyproject.toml" "opt/hermes/hermes-webui/server.py" "opt/hermes/scripts/start-services.sh"; do
    if [ -f "${TEMP_DIR}/${f}" ]; then
        echo "  OK: ${f}"
    else
        echo "  MISSING: ${f}"
        PASS=false
    fi
done

rm -rf "${TEMP_DIR}"

if [ "${PASS}" = true ]; then
    echo ""
    echo "All checks passed!"
    exit 0
else
    echo ""
    echo "Some files missing from rootfs!"
    exit 1
fi
