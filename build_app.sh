#!/bin/bash
# Builds BizneoCompanion.app (a menu-bar agent) and ad-hoc code-signs it.
set -euo pipefail
cd "$(dirname "$0")"

BUILD_PATH="${BUILD_PATH:-.build}"
APP_NAME="BizneoCompanion"
APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

echo "▸ Building release…"
swift build -c release --build-path "$BUILD_PATH" 2>/dev/null || swift build -c release --build-path "$BUILD_PATH"

echo "▸ Assembling ${APP_NAME}.app…"
rm -rf "$APP_DIR"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${BUILD_PATH}/release/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Bizneo Companion</string>
  <key>CFBundleDisplayName</key>          <string>Bizneo Companion</string>
  <key>CFBundleExecutable</key>           <string>BizneoCompanion</string>
  <key>CFBundleIdentifier</key>           <string>com.asolfre.bizneocompanion</string>
  <key>CFBundleVersion</key>              <string>1.0</string>
  <key>CFBundleShortVersionString</key>   <string>1.0</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>LSMinimumSystemVersion</key>       <string>13.0</string>
  <key>LSUIElement</key>                  <true/>
  <key>NSHighResolutionCapable</key>      <true/>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code-signing…"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built ${APP_DIR}"
echo "  Run menu-bar app:  open \"${APP_DIR}\""
echo "  Validate in terminal:  \"${CONTENTS}/MacOS/${APP_NAME}\" --probe --dump"
