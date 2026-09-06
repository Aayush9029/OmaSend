#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:-0.2.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$root/dist"
for target in windows/amd64 windows/arm64 darwin/amd64 darwin/arm64 linux/amd64 linux/arm64; do
  os="${target%/*}"; arch="${target#*/}"
  dir="$stage/$os-$arch"; mkdir -p "$dir"
  name=omasend-web; [[ "$os" != windows ]] || name=omasend-web.exe
  (cd "$root/linux" && CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -trimpath -ldflags='-s -w' -o "$dir/$name" ./cmd/omasend-web)
  cp "$root/docs/WEB.md" "$dir/README.md"
  if [[ "$os" == windows ]]; then
    (cd "$dir" && zip -q "$root/dist/OmaSendWeb_${version}_${os}_${arch}.zip" "$name" README.md)
  else
    tar -czf "$root/dist/OmaSendWeb_${version}_${os}_${arch}.tar.gz" -C "$dir" "$name" README.md
  fi
done
