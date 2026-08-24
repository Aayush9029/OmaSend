#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OmaSend"
BUNDLE_ID="art.aayush.OmaSend"
MIN_SYSTEM_VERSION="15.0"
CONFIGURATION="${OMASEND_CONFIGURATION:-debug}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
cd "${ROOT_DIR}"
swift build -c "${CONFIGURATION}"
BUILD_BINARY="$(swift build -c "${CONFIGURATION}" --show-bin-path)/${APP_NAME}"
BUILD_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BUILD_BINARY}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
if [[ -d "${BUILD_DIR}/OmaSend_OmaSend.bundle" ]]; then
  cp -R "${BUILD_DIR}/OmaSend_OmaSend.bundle" "${RESOURCES_DIR}/OmaSend_OmaSend.bundle"
fi
if [[ -f "${ROOT_DIR}/../assets/AppIcon.icns" ]]; then cp "${ROOT_DIR}/../assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"; fi

cat >"${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>OmaSend</string>
  <key>CFBundleExecutable</key><string>OmaSend</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>OmaSend</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${OMASEND_VERSION:-0.1.0}</string>
  <key>CFBundleVersion</key><string>${OMASEND_BUILD:-1}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_SYSTEM_VERSION}</string>
  <key>LSUIElement</key><true/>
  <key>NSBonjourServices</key><array><string>_omasend._tcp</string></array>
  <key>NSLocalNetworkUsageDescription</key><string>OmaSend finds your paired computers and shares encrypted clipboard items with them.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

SIGN_IDENTITY="${OMASEND_SIGN_IDENTITY:--}"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

open_app() { /usr/bin/open -n "${APP_BUNDLE}"; }
case "${MODE}" in
  run) open_app ;;
  --debug|debug) lldb -- "${MACOS_DIR}/${APP_NAME}" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"${APP_NAME}\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"${BUNDLE_ID}\"" ;;
  --verify|verify) open_app; sleep 2; pgrep -x "${APP_NAME}" >/dev/null; codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" ;;
  --no-launch|no-launch) codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" ;;
  *) printf 'usage: %s [run|--debug|--logs|--telemetry|--verify|--no-launch]\n' "$0" >&2; exit 2 ;;
esac
