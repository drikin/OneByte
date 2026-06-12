#!/bin/bash
# Build DriMacIME and copy to ~/dev/DriMacIME/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/DriMacIME_Build"
APP_NAME="DriMacIME.app"

echo "=== Building DriMacIME ==="

cd "$SCRIPT_DIR"

# Clean build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/Resources"

# Compile
swiftc \
  -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -framework Cocoa \
  -framework InputMethodKit \
  -o "$BUILD_DIR/$APP_NAME/Contents/MacOS/DriMacIME" \
  Sources/DriMacIME/AppDelegate.swift \
  Sources/DriMacIME/DriMacInputController.swift

# Copy icon and Info.plist
cp Sources/DriMacIME/main.tiff "$BUILD_DIR/$APP_NAME/Contents/Resources/"

# Generate Info.plist with resolved values
cat > "$BUILD_DIR/$APP_NAME/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Application is background only</key>
	<true/>
	<key>InputMethodConnectionName</key>
	<string>com.drikin.DriMacIME_Connection</string>
	<key>InputMethodServerControllerClass</key>
	<string>DriMacInputController</string>
	<key>NSPrincipalClass</key>
	<string>DriMacApplication</string>
	<key>tsInputMethodCharacterRepertoireKey</key>
	<array>
		<string>Latn</string>
		<string>Jpan</string>
	</array>
	<key>tsInputMethodIconFileKey</key>
	<string>main.tiff</string>
	<key>CFBundleIdentifier</key>
	<string>com.drikin.DriMacIME</string>
	<key>CFBundleName</key>
	<string>DriMac IME</string>
	<key>CFBundleDisplayName</key>
	<string>DriMac</string>
	<key>CFBundleExecutable</key>
	<string>DriMacIME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

# Copy to project dir for easy access
cp -r "$BUILD_DIR/$APP_NAME" "$SCRIPT_DIR/"

echo ""
echo "=== Build complete ==="
echo "To install: sudo cp -r $SCRIPT_DIR/$APP_NAME /Library/Input\\ Methods/"
echo "Then: System Settings > Keyboard > Input Sources > Add 'DriMac'"
