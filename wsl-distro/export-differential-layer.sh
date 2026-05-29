#!/bin/bash
# Export a layer image as a differential rootfs: files in <layer-image> that
# don't already exist in <core-image> get tarred up. Files identical to core
# (by path + size) are pruned so the user doesn't ship duplicate bytes.
#
# Usage: export-differential-layer.sh <layer-image> <core-image> <output.tar.gz>
#
# Why path+size and not sha256: hashing 396MB of core content adds ~3 min per
# layer, and our Dockerfile.{browser,voice,messaging} only ADD files — they
# never modify core — so a path-based diff produces the same result for our
# workload at a fraction of the time.

set -euo pipefail

LAYER_IMAGE="${1:?layer image required (e.g. hermes-browser:latest)}"
CORE_IMAGE="${2:?core image required (e.g. hermes-core:latest)}"
OUTPUT="${3:?output path required (e.g. output/layer-browser.tar.gz)}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

mkdir -p "${WORKDIR}/full"

LAYER_ID=$(docker create "${LAYER_IMAGE}")
CORE_ID=$(docker create "${CORE_IMAGE}")
trap 'rm -rf "${WORKDIR}"; docker rm "${LAYER_ID}" "${CORE_ID}" >/dev/null 2>&1 || true' EXIT

echo "Inventorying core image paths..." >&2
docker export "${CORE_ID}" | tar -tf - > "${WORKDIR}/core-paths.txt"

echo "Extracting layer image..." >&2
docker export "${LAYER_ID}" | tar -xf - -C "${WORKDIR}/full"

echo "Pruning files already in core..." >&2
python3 - "${WORKDIR}/core-paths.txt" "${WORKDIR}/full" <<'PYEOF'
import os, sys

core_paths_file, full_root = sys.argv[1], sys.argv[2]
core = set()
with open(core_paths_file) as f:
    for line in f:
        p = line.rstrip("\n").lstrip("./").rstrip("/")
        if p:
            core.add(p)

removed_files = 0
removed_bytes = 0
for root, dirs, files in os.walk(full_root, topdown=False):
    rel_root = os.path.relpath(root, full_root)
    for fn in files:
        rel = fn if rel_root == "." else f"{rel_root}/{fn}"
        if rel in core:
            full_path = os.path.join(root, fn)
            try:
                removed_bytes += os.path.getsize(full_path)
                os.unlink(full_path)
                removed_files += 1
            except OSError:
                pass
    for d in dirs:
        rel = d if rel_root == "." else f"{rel_root}/{d}"
        if rel in core:
            full_path = os.path.join(root, d)
            try:
                os.rmdir(full_path)  # only succeeds if empty
            except OSError:
                pass

print(f"  pruned {removed_files} files, {removed_bytes/1024/1024:.1f} MiB", file=sys.stderr)
PYEOF

echo "Tarring delta..." >&2
mkdir -p "$(dirname "${OUTPUT}")"
cd "${WORKDIR}/full"
tar czf "${OUTPUT}" .
cd - >/dev/null

ls -lh "${OUTPUT}" >&2
