#!/bin/bash
# EnterRemap build script: compiles main.swift into a background-only
# .app bundle (LSUIElement) and installs it to /Applications.
#
# Usage:
#   ./build.sh                       ad-hoc signed, local install (default)
#   ./build.sh release               Developer ID signed, notarized,
#                                     stapled, and packaged as a
#                                     distribution zip in build/
#
# Release mode notarizes via an App Store Connect API key (same method
# as cooViewer), not a Keychain Profile. Provide:
#   NOTARY_KEY_ID       App Store Connect API key ID
#   NOTARY_ISSUER_ID    App Store Connect API issuer ID
# as environment variables, or as the 2nd/3rd positional args to
# `release`. The private key itself is expected at the standard
# notarytool search path and is never read from or written to this repo:
#   ~/.appstoreconnect/private_keys/AuthKey_<NOTARY_KEY_ID>.p8
set -e

APP_NAME="EnterRemap"
VERSION="1.6.2"
BUILD_NUMBER="15"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
# Install target: /Applications (admin account, no sudo needed)
INSTALL_DIR="/Applications"
DEVELOPER_ID_IDENTITY="Developer ID Application: Kuniharu Nishimura (87B58V226A)"

MODE="${1:-adhoc}"

echo "=== Step 1: Cleaning previous build ==="
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "=== Step 2: Compiling Swift code ==="
swiftc -sdk "$(xcrun --show-sdk-path)" \
  "$REPO_DIR/main.swift" \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
  -framework Cocoa \
  -framework CoreGraphics

echo "=== Step 3: Building app icon ==="
ICON_PNG="$REPO_DIR/Assets/AppIcon.png"
if [ -f "$ICON_PNG" ]; then
    ICONSET_DIR="$BUILD_DIR/icon.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -s format png -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -s format png -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -s format png -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -s format png -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/$APP_NAME.icns"
    rm -rf "$ICONSET_DIR"
    echo "App icon generated from Assets/AppIcon.png."
else
    echo "WARNING: $ICON_PNG not found; building without an app icon."
fi

echo "=== Step 4: Creating Info.plist ==="
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.kni.EnterRemap</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 kni. All rights reserved.</string>
</dict>
</plist>
EOF

if [ "$MODE" = "release" ]; then
    NOTARY_KEY_ID="${2:-$NOTARY_KEY_ID}"
    NOTARY_ISSUER_ID="${3:-$NOTARY_ISSUER_ID}"
    NOTARY_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${NOTARY_KEY_ID}.p8"
    if [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER_ID" ]; then
        echo "ERROR: notarization requires an App Store Connect API key."
        echo "Usage: ./build.sh release <key-id> <issuer-id>"
        echo "(or set \$NOTARY_KEY_ID / \$NOTARY_ISSUER_ID). The private key must"
        echo "already exist at:"
        echo "  ~/.appstoreconnect/private_keys/AuthKey_<key-id>.p8"
        exit 1
    fi
    if [ ! -f "$NOTARY_KEY_PATH" ]; then
        echo "ERROR: API key file not found at $NOTARY_KEY_PATH"
        exit 1
    fi

    echo "=== Step 5: Code-signing with Developer ID ==="
    codesign --force --deep --options runtime --sign "$DEVELOPER_ID_IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"

    echo "=== Step 6: Notarizing (key ID: $NOTARY_KEY_ID) ==="
    NOTARY_ZIP="$BUILD_DIR/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
      --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
    rm -f "$NOTARY_ZIP"

    echo "=== Step 7: Stapling notarization ticket ==="
    xcrun stapler staple "$APP_DIR"

    echo "=== Step 8: Verifying Gatekeeper acceptance ==="
    spctl -a -vv "$APP_DIR"

    echo "=== Step 9: Packaging distribution zip ==="
    DIST_ZIP="$BUILD_DIR/${APP_NAME}-v${VERSION}.zip"
    rm -f "$DIST_ZIP"
    ditto -c -k --keepParent "$APP_DIR" "$DIST_ZIP"
    echo "Distribution zip: $DIST_ZIP"
else
    echo "=== Step 5: Code-signing application bundle (ad-hoc) ==="
    codesign --force --deep --sign - "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"
fi

echo "=== Step 10: Installing to $INSTALL_DIR ==="
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
