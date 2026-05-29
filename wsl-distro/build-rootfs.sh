#!/bin/bash
# Build WSL2 rootfs layers for Hermes Windows Standalone
# Requires: Docker
# Usage: ./build-rootfs.sh [--layer core|browser|voice|messaging|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
AGENT_SRC="${AGENT_SRC:-../../ref/hermes-agent}"
WEBUI_SRC="${WEBUI_SRC:-../../ref/hermes-webui}"

LAYER="${1:-all}"

mkdir -p "${OUTPUT_DIR}"

prepare_build_context() {
    local ctx="${SCRIPT_DIR}/.build-context"
    rm -rf "${ctx}"
    mkdir -p "${ctx}"

    echo "Preparing build context..." >&2
    cp -r "${AGENT_SRC}" "${ctx}/hermes-agent"
    cp -r "${WEBUI_SRC}" "${ctx}/hermes-webui"
    cp -r "${SCRIPT_DIR}/scripts" "${ctx}/scripts"

    # Remove unnecessary files to reduce context size
    rm -rf "${ctx}/hermes-agent/.git"
    rm -rf "${ctx}/hermes-agent/website"
    rm -rf "${ctx}/hermes-agent/tests"
    rm -rf "${ctx}/hermes-webui/.git"
    rm -rf "${ctx}/hermes-webui/tests"

    echo "${ctx}"
}

build_core() {
    echo "=== Building core layer ==="
    local ctx
    ctx=$(prepare_build_context)

    docker build \
        -f "${SCRIPT_DIR}/Dockerfile.core" \
        -t hermes-core:latest \
        "${ctx}"

    echo "Exporting core rootfs..."
    local container_id
    container_id=$(docker create hermes-core:latest)
    docker export "${container_id}" | gzip > "${OUTPUT_DIR}/rootfs-core.tar.gz"
    docker rm "${container_id}" > /dev/null

    echo "Core rootfs: ${OUTPUT_DIR}/rootfs-core.tar.gz"
    ls -lh "${OUTPUT_DIR}/rootfs-core.tar.gz"
}

build_layer() {
    local name="$1"
    local dockerfile="$2"

    echo "=== Building ${name} layer ==="

    docker build \
        -f "${SCRIPT_DIR}/${dockerfile}" \
        -t "hermes-${name}:latest" \
        "${SCRIPT_DIR}/.build-context"

    "${SCRIPT_DIR}/export-differential-layer.sh" \
        "hermes-${name}:latest" \
        "hermes-core:latest" \
        "${OUTPUT_DIR}/layer-${name}.tar.gz"
}

cleanup_context() {
    rm -rf "${SCRIPT_DIR}/.build-context"
}

trap cleanup_context EXIT

case "${LAYER}" in
    core)
        build_core
        ;;
    browser)
        build_layer "browser" "Dockerfile.browser"
        ;;
    voice)
        build_layer "voice" "Dockerfile.voice"
        ;;
    messaging)
        build_layer "messaging" "Dockerfile.messaging"
        ;;
    all)
        build_core
        build_layer "browser" "Dockerfile.browser"
        build_layer "voice" "Dockerfile.voice"
        build_layer "messaging" "Dockerfile.messaging"
        ;;
    *)
        echo "Unknown layer: ${LAYER}"
        echo "Usage: $0 [core|browser|voice|messaging|all]"
        exit 1
        ;;
esac

echo ""
echo "=== Build complete ==="
ls -lh "${OUTPUT_DIR}"/*.tar.gz 2>/dev/null || echo "No output files found"
