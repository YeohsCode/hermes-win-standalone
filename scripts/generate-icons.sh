#!/bin/bash
# generate-icons.sh - Generate placeholder RGBA PNG icons for Tauri build
# In production, replace with actual brand icons

set -e

ICON_DIR="$(cd "$(dirname "$0")" && pwd)/../tauri-app/src-tauri/icons"
mkdir -p "${ICON_DIR}"

# Use Python to generate valid RGBA PNGs and a proper ICO file
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

def create_ico(png_data_list):
    \"\"\"Create a valid ICO file with embedded PNG images.\"\"\"
    num_images = len(png_data_list)
    # ICO header: reserved(2) + type(2, 1=icon) + count(2)
    header = struct.pack('<HHH', 0, 1, num_images)
    # Each directory entry is 16 bytes
    dir_entries = b''
    image_data = b''
    offset = 6 + (16 * num_images)  # after header + all dir entries

    for size, png_data in png_data_list:
        w = size if size < 256 else 0  # 0 means 256 in ICO format
        h = w
        entry = struct.pack('<BBBBHHII',
            w,              # width
            h,              # height
            0,              # color palette count
            0,              # reserved
            1,              # color planes
            32,             # bits per pixel
            len(png_data),  # image data size
            offset          # offset to image data
        )
        dir_entries += entry
        image_data += png_data
        offset += len(png_data)

    return header + dir_entries + image_data

icon_dir = sys.argv[1]
sizes = {'32x32.png': 32, '128x128.png': 128, '128x128@2x.png': 256, 'icon.png': 256}

png_cache = {}
for name, size in sizes.items():
    png = create_rgba_png(size, size, 74, 144, 217)
    png_cache[size] = png
    with open(os.path.join(icon_dir, name), 'wb') as f:
        f.write(png)

# Create proper ICO file with multiple sizes embedded as PNG
ico_entries = [
    (16, create_rgba_png(16, 16, 74, 144, 217)),
    (32, png_cache[32]),
    (48, create_rgba_png(48, 48, 74, 144, 217)),
    (256, png_cache[256]),
]
ico_data = create_ico(ico_entries)
with open(os.path.join(icon_dir, 'icon.ico'), 'wb') as f:
    f.write(ico_data)

# ICNS placeholder (just use PNG, macOS is not the target)
with open(os.path.join(icon_dir, 'icon.icns'), 'wb') as f:
    f.write(png_cache[256])

print('Icons generated in ' + icon_dir)
" "${ICON_DIR}"
