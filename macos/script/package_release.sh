#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
IDENTITY="${OMASEND_SIGN_IDENTITY:-Developer ID Application: Aayush Pokharel (4538W4A79B)}"
OMASEND_VERSION="${VERSION}" OMASEND_CONFIGURATION=release OMASEND_SIGN_IDENTITY="${IDENTITY}" "${ROOT_DIR}/script/build_and_run.sh" --no-launch

APP="${ROOT_DIR}/dist/OmaSend.app"
DIST="${REPO_DIR}/dist"
mkdir -p "${DIST}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${DIST}/OmaSend_${VERSION}_macOS_arm64.zip"

DMG_STAGE="${ROOT_DIR}/dist/dmg"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP}" "${DMG_STAGE}/OmaSend.app"
ln -s /Applications "${DMG_STAGE}/Applications"
hdiutil create -volname "OmaSend" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DIST}/OmaSend_${VERSION}_macOS_arm64.dmg" >/dev/null
codesign --force --sign "${IDENTITY}" "${DIST}/OmaSend_${VERSION}_macOS_arm64.dmg"

if [[ -n "${OMASEND_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "${DIST}/OmaSend_${VERSION}_macOS_arm64.dmg" --keychain-profile "${OMASEND_NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DIST}/OmaSend_${VERSION}_macOS_arm64.dmg"
fi
