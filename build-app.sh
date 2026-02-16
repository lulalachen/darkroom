#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-debug}"
EXECUTABLE_NAME="DarkroomApp"
APP_NAME="Darkroom"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.darkroom.app}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist/${CONFIG}"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [[ "${CONFIG}" != "debug" && "${CONFIG}" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

echo "Building ${EXECUTABLE_NAME} (${CONFIG})..."
swift build -c "${CONFIG}"

BIN_DIR="$(swift build -c "${CONFIG}" --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/${EXECUTABLE_NAME}"
RESOURCE_BUNDLE_PATH="${BIN_DIR}/darkroom_darkroom.bundle"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "Expected executable not found: ${EXECUTABLE_PATH}"
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -d "${RESOURCE_BUNDLE_PATH}" ]]; then
  # SwiftPM executable resource accessor checks Bundle.main.bundleURL/<bundle>.
  cp -R "${RESOURCE_BUNDLE_PATH}" "${APP_DIR}/darkroom_darkroom.bundle"
fi

ICON_PNG_SOURCE=""
if [[ -f "${PROJECT_ROOT}/Sources/Resources/AppIcon.png" ]]; then
  ICON_PNG_SOURCE="${PROJECT_ROOT}/Sources/Resources/AppIcon.png"
elif [[ -f "${PROJECT_ROOT}/Sources/Resources/AppIcon.icon/Assets/darkroom_appicon_1024_opaque.png" ]]; then
  ICON_PNG_SOURCE="${PROJECT_ROOT}/Sources/Resources/AppIcon.icon/Assets/darkroom_appicon_1024_opaque.png"
fi

if [[ -n "${ICON_PNG_SOURCE}" ]]; then
  cp "${ICON_PNG_SOURCE}" "${RESOURCES_DIR}/AppIcon.png"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.png</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  if ! codesign --force --deep --sign - "${APP_DIR}"; then
    echo "Warning: codesign failed; continuing with unsigned app bundle."
  fi
fi

echo "Built app: ${APP_DIR}"
echo "Launch with: open \"${APP_DIR}\""
