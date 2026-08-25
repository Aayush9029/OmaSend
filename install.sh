#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="Aayush9029/OmaSend"
INSTALL_ROOT="${HOME}/.local"
SYSTEMD_ROOT="${HOME}/.config/systemd/user"
OMARCHY_ROOT="${HOME}/.config/omarchy/plugins/local.omasend"

fail() { printf 'OmaSend: %s\n' "$1" >&2; exit 1; }
[[ "$(uname -s)" == "Linux" ]] || fail "Linux is required"
for command in curl tar systemctl wl-copy wl-paste; do command -v "${command}" >/dev/null || fail "${command} is required"; done

case "$(uname -m)" in
  x86_64) architecture="amd64" ;;
  aarch64|arm64) architecture="arm64" ;;
  *) fail "unsupported architecture: $(uname -m)" ;;
esac

version="${OMASEND_VERSION:-}"
if [[ -z "${version}" ]]; then
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPOSITORY}/releases/latest")"
  version="${latest_url##*/}"
fi
[[ "${version}" == v* ]] || fail "could not find the latest release"

archive="omasend_${version#v}_linux_${architecture}.tar.gz"
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT

printf 'Installing OmaSend %s for linux/%s\n' "${version}" "${architecture}"
curl -fsSL "https://github.com/${REPOSITORY}/releases/download/${version}/${archive}" -o "${temporary_root}/${archive}"
tar -xzf "${temporary_root}/${archive}" -C "${temporary_root}"
install -Dm755 "${temporary_root}/omasend" "${INSTALL_ROOT}/bin/omasend"
install -Dm644 "${temporary_root}/packaging/systemd/omasend.service" "${SYSTEMD_ROOT}/omasend.service"
systemctl --user daemon-reload
# Drop enablement symlinks from older releases that started the daemon
# before the graphical session imported WAYLAND_DISPLAY
systemctl --user disable omasend.service >/dev/null 2>&1 || true
systemctl --user enable omasend.service
systemctl --user restart omasend.service

if command -v omarchy >/dev/null && command -v omarchy-shell >/dev/null; then
  install -Dm644 "${temporary_root}/omarchy/local.omasend/manifest.json" "${OMARCHY_ROOT}/manifest.json"
  install -Dm644 "${temporary_root}/omarchy/local.omasend/Panel.qml" "${OMARCHY_ROOT}/Panel.qml"
  omarchy plugin validate "${OMARCHY_ROOT}"
  omarchy-shell -q shell rescanPlugins
  omarchy plugin enable local.omasend --section right --before omarchy.clock
  printf 'Omarchy menu-bar panel installed\n'
fi

printf 'OmaSend is ready. Run: omasend status\n'

