# OmaSend

OmaSend shares one encrypted clipboard across Windows, macOS, and Linux on a LAN. Each platform has a native app that speaks the same protocol (`PROTOCOL.md`). A browser companion (`omasend-web`) serves a web UI. Status: active.

## Platforms

| Folder | Platform | Stack |
|--------|----------|-------|
| `windows/` | Windows x64 and ARM64 | WPF on .NET 10, `OmaSend.Core` protocol assembly, DPAPI storage |
| `macos/` | macOS 15+, Apple silicon | Swift package, Network.framework |
| `linux/` | Wayland Linux | Go daemon and CLI (`cmd/omasend`), `wl-clipboard`, systemd user services, Omarchy Shell panel (`omarchy/`) |
| `linux/cmd/omasend-web` | Browser companion for all OSes | Go server that embeds the web UI |
| `web/` | Web UI source | React 19, Vite, Tailwind CSS 4, Radix UI |
| `tests/` | Cross-platform checks | Python interop, mDNS, Windows UI, installer tests |

## Commands

| Task | Command |
|------|---------|
| Linux test | `cd linux && go test ./... && go vet ./...` |
| macOS test | `cd macos && swift test` |
| macOS build and run | `macos/script/build_and_run.sh` |
| Windows build | `dotnet build windows/OmaSend/OmaSend.csproj -c Release` |
| Windows tests | `dotnet run --project windows/OmaSend.Tests -c Release` |
| Protocol interop | `python tests/interop.py --bridge windows/OmaSend.Tests/bin/Release/net10.0/OmaSend.Tests.dll` |
| Web UI build | `cd web && npm ci && npm run build` |
| Package | `scripts/package-linux.sh`, `scripts/package-web.sh`, `scripts/package-windows.ps1` |

`docs/DEVELOPMENT.md` has the full test steps, the isolated Windows test setup, and the screenshot steps.

## Rules

- Keep the three native apps compatible with `PROTOCOL.md`. When you change the protocol, change all three and run `tests/interop.py`.
- Ports: TCP 53317 for the native apps, TCP 53318 for the browser UI, TCP 53319 for the companion peer, UDP 5353 for mDNS.
- `npm run build` in `web/` writes to `linux/internal/web/static`. Commit that output. CI fails when it differs from the source.
- CI uses `web/package-lock.json` with `npm ci`.
- Use real screenshots only. Do not generate or relabel a Windows image as another platform.
- Peers connect only after an encrypted hello. Discovery does not bypass pairing. "Trusted LAN" mode sends data without encryption.

## Release

- A `v*` tag runs `release.yml`. It tests, packages Windows, Linux, macOS, and the web companion, and makes a draft release with a checksum manifest. Check the draft assets before you publish it.
- The `v*` tag workflow `release.yml` also builds, signs, and notarizes the macOS app.
- The macOS job signs and notarizes when these secrets exist: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARY_KEY_BASE64`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER`. Without them, it makes an ad-hoc signed ZIP. Windows executables are unsigned.
- Two casks point at the macOS release. Update both with the version and SHA-256:
  - `Casks/omasend.rb` in this repository (the `aayush9029/omasend` tap, for the ZIP)
  - `../homebrew-tap/Casks/omasend.rb` (the `aayush9029/tap` tap, for the DMG)
- The `homebrew.yml` workflow downloads the archive and checks the cask checksum.
