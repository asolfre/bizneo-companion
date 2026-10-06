#!/bin/bash
# Builds BizneoCompanion.app (a menu-bar agent) and ad-hoc code-signs it.
set -euo pipefail
cd "$(dirname "$0")"

BUILD_PATH="${BUILD_PATH:-.build}"
APP_NAME="BizneoCompanion"
APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

# The version lives in Swift so the bundle can't drift from the binary.
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/BizneoCore/AppInfo.swift)"
[ -n "$VERSION" ] || { echo "error: no version found in Sources/BizneoCore/AppInfo.swift" >&2; exit 1; }

# Build identity, read back by AppInfo.displayVersion. Empty = a release built at
# its own tag; otherwise the commit, plus ".dirty" with uncommitted changes.
COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  BUILD=""   # no git (e.g. a source tarball): show the bare version
elif git describe --tags --exact-match --match "v$VERSION" >/dev/null 2>&1 && git diff --quiet HEAD; then
  BUILD=""
else
  BUILD="$(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo .dirty)"
fi
DISPLAY_VERSION="$VERSION${BUILD:++$BUILD}"

echo "▸ Building release…"
swift build -c release --build-path "$BUILD_PATH" 2>/dev/null || swift build -c release --build-path "$BUILD_PATH"

echo "▸ Assembling ${APP_NAME}.app…"
rm -rf "$APP_DIR"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${BUILD_PATH}/release/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Bizneo Companion</string>
  <key>CFBundleDisplayName</key>          <string>Bizneo Companion</string>
  <key>CFBundleExecutable</key>           <string>BizneoCompanion</string>
  <key>CFBundleIdentifier</key>           <string>com.asolfre.bizneocompanion</string>
  <key>CFBundleVersion</key>              <string>${COUNT}</string>
  <key>CFBundleShortVersionString</key>   <string>${VERSION}</string>
  <key>BCBuild</key>                      <string>${BUILD}</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>LSMinimumSystemVersion</key>       <string>13.0</string>
  <key>LSUIElement</key>                  <true/>
  <key>NSHighResolutionCapable</key>      <true/>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code-signing…"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built ${APP_DIR} — ${DISPLAY_VERSION} (build ${COUNT})"
echo "  Run menu-bar app:  open \"${APP_DIR}\""
echo "  Validate in terminal:  \"${CONTENTS}/MacOS/${APP_NAME}\" --probe --dump"
