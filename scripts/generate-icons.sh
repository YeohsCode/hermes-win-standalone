#!/bin/bash
# generate-icons.sh - Generate placeholder RGBA PNG icons for Tauri build
# In production, replace with actual brand icons

set -e

ICON_DIR="$(cd "$(dirname "$0")" && pwd)/../tauri-app/src-tauri/icons"
mkdir -p "${ICON_DIR}"

# Use Python to generate valid RGBA PNGs (available on all CI runners)
python3 -c "
import struct, zlib, os, sys

def create_rgba_png(width, height, r, g, b, a=255):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            raw += bytes([r, g, b, a])
    idat = zlib.compress(raw)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', ihdr)
    png += chunk(b'IDAT', idat)
    png += chunk(b'IEND', b'')
    return png

icon_dir = sys.argv[1]
sizes = {'32x32.png': 32, '128x128.png': 128, '128x128@2x.png': 256, 'icon.png': 256}

for name, size in sizes.items():
    with open(os.path.join(icon_dir, name), 'wb') as f:
        f.write(create_rgba_png(size, size, 74, 144, 217))

# ICO and ICNS - use 256x256 PNG as placeholder
for name in ['icon.ico', 'icon.icns']:
    with open(os.path.join(icon_dir, name), 'wb') as f:
        f.write(create_rgba_png(256, 256, 74, 144, 217))

print('RGBA PNG icons generated in ' + icon_dir)
" "${ICON_DIR}"
