#!/bin/bash
# Install an optional layer from a tar.gz archive
# Usage: install-layer.sh <layer-name> <tar-path>
# The tar is expected to contain files rooted at /

set -e

LAYER_NAME="$1"
TAR_PATH="$2"

if [ -z "${LAYER_NAME}" ] || [ -z "${TAR_PATH}" ]; then
    echo "Usage: install-layer.sh <layer-name> <tar-path>"
    exit 1
fi

if [ ! -f "${TAR_PATH}" ]; then
    echo "Error: Layer archive not found: ${TAR_PATH}"
    exit 1
fi

MARKER_DIR="/opt/hermes/.layers"
mkdir -p "${MARKER_DIR}"

if [ -f "${MARKER_DIR}/${LAYER_NAME}.installed" ]; then
    echo "Layer '${LAYER_NAME}' is already installed"
    exit 0
fi

echo "Installing layer: ${LAYER_NAME}..."
tar xzf "${TAR_PATH}" -C /

# Mark as installed
date -Iseconds > "${MARKER_DIR}/${LAYER_NAME}.installed"
echo "Layer '${LAYER_NAME}' installed successfully"
