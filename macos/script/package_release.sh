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

NOTARY_TEMP=""
cleanup() {
  if [[ -n "${NOTARY_TEMP}" && -d "${NOTARY_TEMP}" ]]; then rm -rf "${NOTARY_TEMP}"; fi
}
trap cleanup EXIT

notary_args=()
if [[ -n "${OMASEND_NOTARY_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "${OMASEND_NOTARY_PROFILE}")
elif [[ -n "${OMASEND_NOTARY_KEY_BASE64_FILE:-}" && -n "${OMASEND_NOTARY_KEY_ID:-}" && -n "${OMASEND_NOTARY_ISSUER:-}" ]]; then
  NOTARY_TEMP="$(mktemp -d)"
  base64 --decode < "${OMASEND_NOTARY_KEY_BASE64_FILE}" > "${NOTARY_TEMP}/AuthKey.p8"
  chmod 600 "${NOTARY_TEMP}/AuthKey.p8"
  notary_args=(
    --key "${NOTARY_TEMP}/AuthKey.p8"
    --key-id "${OMASEND_NOTARY_KEY_ID}"
    --issuer "${OMASEND_NOTARY_ISSUER}"
  )
fi

if (( ${#notary_args[@]} > 0 )); then
  APP_NOTARY_ZIP="${ROOT_DIR}/dist/OmaSend-notarization.zip"
  ditto -c -k --keepParent "${APP}" "${APP_NOTARY_ZIP}"
  xcrun notarytool submit "${APP_NOTARY_ZIP}" "${notary_args[@]}" --wait
  xcrun stapler staple "${APP}"
  rm -f "${APP_NOTARY_ZIP}"
fi

ditto -c -k --sequesterRsrc --keepParent "${APP}" "${DIST}/OmaSend_${VERSION}_macOS_arm64.zip"

DMG="${DIST}/OmaSend_${VERSION}_macOS_arm64.dmg"
DMG_BACKGROUND="${ROOT_DIR}/dmg-assets/dmg-bg@2x.jpg"
CREATE_DMG="$(command -v create-dmg || true)"
if [[ -z "${CREATE_DMG}" && -x /opt/homebrew/bin/create-dmg ]]; then
  CREATE_DMG=/opt/homebrew/bin/create-dmg
fi
[[ -x "${CREATE_DMG}" ]] || { printf 'create-dmg is required\n' >&2; exit 1; }
[[ -f "${DMG_BACKGROUND}" ]] || { printf 'DMG background is missing\n' >&2; exit 1; }

rm -f "${DMG}"
set +e
"${CREATE_DMG}" \
  --volname "OmaSend Installer" \
  --volicon "${ROOT_DIR}/../assets/AppIcon.icns" \
  --background "${DMG_BACKGROUND}" \
  --window-size 560 350 \
  --window-pos 200 120 \
  --icon-size 80 \
  --icon "OmaSend.app" 150 165 \
  --app-drop-link 410 165 \
  --hide-extension "OmaSend.app" \
  --no-internet-enable \
  "${DMG}" \
  "${APP}"
create_dmg_status=$?
set -e
if [[ ${create_dmg_status} -ne 0 && ${create_dmg_status} -ne 2 ]]; then
  printf 'create-dmg failed with status %s\n' "${create_dmg_status}" >&2
  exit "${create_dmg_status}"
fi
[[ -f "${DMG}" ]] || { printf 'DMG was not created\n' >&2; exit 1; }

codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"

if (( ${#notary_args[@]} > 0 )); then
  xcrun notarytool submit "${DMG}" "${notary_args[@]}" --wait
  xcrun stapler staple "${DMG}"
fi
