#!/bin/bash
# OneByte - Build and Install Script
# Run on your Mac with: bash build-and-install.sh
set -euo pipefail

APP_NAME="OneByte"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/${APP_NAME}_Build"

echo "=== Building ${APP_NAME} ==="

# Create bundle structure
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

# Copy Info.plist
cp "$SRC_DIR/Resources/Info.plist" "$BUILD_DIR/$APP_NAME.app/Contents/"

# Create icon (16x16)
python3 -c "
import struct, zlib
def png(w,h,p):
    def c(t,d): return struct.pack('>I',len(d)) + t + d + struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w): raw += bytes(p[y*w+x])
    return b'\x89PNG\r\n\x1a\n' + c(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0)) + c(b'IDAT',zlib.compress(raw)) + c(b'IEND',b'')
pix = []
for y in range(16):
    for x in range(16):
        if (x in (2,3,4,5,6,7,8) and y in (2,13)) or (x==2 and 3<=y<=12) or (x in (9,10) and y in (3,12)) or (x==11 and 4<=y<=11):
            pix.append((100,180,255,255))
        else:
            pix.append((0,0,0,0))
with open('$BUILD_DIR/$APP_NAME.app/Contents/Resources/main.tiff','wb') as f:
    import subprocess
    with open('/tmp/ob_icon.png','wb') as p: p.write(png(16,16,pix))
" && sips -s format tiff /tmp/ob_icon.png --out "$BUILD_DIR/$APP_NAME.app/Contents/Resources/main.tiff" &>/dev/null

# Compile
swiftc \
  -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -framework Cocoa \
  -framework InputMethodKit \
  -framework SwiftUI \
  -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
  "$SRC_DIR/Sources/OneByte/AppDelegate.swift" \
  "$SRC_DIR/Sources/OneByte/OneByteInputController.swift" \
  "$SRC_DIR/Sources/OneByte/PreferencesController.swift"

echo ""
echo "=== Build successful! ==="
echo ""
echo "To install, run:"
echo "  sudo cp -r \"$BUILD_DIR/$APP_NAME.app\" \"/Library/Input Methods/\""
echo "  sudo chmod -R 755 \"/Library/Input Methods/$APP_NAME.app\""
echo "  sudo xattr -cr \"/Library/Input Methods/$APP_NAME.app\""
echo ""
echo "Then: System Settings > Keyboard > Input Sources > Add 'OneByte'"
echo "Or restart your Mac."
