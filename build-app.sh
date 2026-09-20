#!/bin/bash
# Build MacGlow and assemble a proper .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MacGlow"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Building ($1)..."
swift build -c release

echo "==> Assembling $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Glow</string>
    <key>CFBundleIdentifier</key>
    <string>com.macglow.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so Accessibility permission sticks to a stable identity.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "==> Done: $APP_DIR"
