#!/bin/bash
# EnterRemap build script: compiles main.swift into a background-only
# .app bundle (LSUIElement) and installs it to ~/Applications.
set -e

APP_NAME="EnterRemap"
VERSION="1.4.2"
BUILD_NUMBER="8"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
# Install target: /Applications (admin account, no sudo needed)
INSTALL_DIR="/Applications"

echo "=== Step 1: Cleaning previous build ==="
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

echo "=== Step 2: Compiling Swift code ==="
swiftc -sdk "$(xcrun --show-sdk-path)" \
  "$REPO_DIR/main.swift" \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
  -framework Cocoa \
  -framework CoreGraphics

echo "=== Step 3: Creating Info.plist ==="
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.enter-remap</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 kni. All rights reserved.</string>
</dict>
</plist>
EOF

echo "=== Step 4: Code-signing application bundle ==="
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "=== Step 5: Installing to $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"
# Kill a running instance so the new binary takes effect on next launch
killall "$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALL_DIR/$APP_NAME.app"
ditto "$APP_DIR" "$INSTALL_DIR/$APP_NAME.app"

echo "=== Build complete: $INSTALL_DIR/$APP_NAME.app ==="
echo "Next steps (first install only):"
echo "  1. System Settings > Privacy & Security > Accessibility: add $APP_NAME"
echo "  2. System Settings > General > Login Items: add $APP_NAME"
echo "  3. Launch: open $INSTALL_DIR/$APP_NAME.app"
