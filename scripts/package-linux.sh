#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUILD_ROOT="${ROOT_DIR}/.build/linux"
DIST_DIR="${ROOT_DIR}/dist"
mkdir -p "${BUILD_ROOT}" "${DIST_DIR}"

for target in amd64 arm64; do
  package="omasend_${VERSION}_linux_${target}"
  stage="${BUILD_ROOT}/${package}"
  rm -rf "${stage}"
  mkdir -p "${stage}/packaging/systemd" "${stage}/omarchy/local.omasend"
  (cd "${ROOT_DIR}/linux" && CGO_ENABLED=0 GOOS=linux GOARCH="${target}" go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o "${stage}/omasend" ./cmd/omasend)
  cp "${ROOT_DIR}/linux/packaging/systemd/omasend.service" "${stage}/packaging/systemd/"
  cp "${ROOT_DIR}/linux/omarchy/local.omasend/manifest.json" "${ROOT_DIR}/linux/omarchy/local.omasend/Panel.qml" "${stage}/omarchy/local.omasend/"
  tar -C "${stage}" -czf "${DIST_DIR}/${package}.tar.gz" .
done
(cd "${DIST_DIR}" && sha256sum omasend_${VERSION}_linux_*.tar.gz > checksums.txt)

