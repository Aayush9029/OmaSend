#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-dev}"
cd "${ROOT_DIR}/linux"
go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o "${ROOT_DIR}/linux/omasend" ./cmd/omasend
printf 'Built %s\n' "${ROOT_DIR}/linux/omasend"

