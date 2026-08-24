# OmaSend

OmaSend is a native shared clipboard for macOS and Linux. It discovers paired computers on your local network, keeps a shared clipboard history, and can automatically place incoming text and images on the system clipboard.

![OmaSend icon](assets/AppIcon.png)

## Features

- Native macOS menu bar app built with SwiftUI and AppKit
- Native Omarchy bar panel plus a small Linux CLI and service
- Text and image clipboard sharing with thumbnail previews
- Optional Auto Copy on each computer
- Bonjour discovery on a local network
- Direct Tailscale peer discovery when the Tailscale CLI is available
- AES-256-GCM authenticated encryption using a shared pairing code
- No cloud service, account, analytics, or relay

## Install on macOS

Download `OmaSend_0.1.0_macOS_arm64.dmg` from the latest release, open it, and drag OmaSend to Applications.

OmaSend requires macOS 15 or newer on Apple silicon.

## Install on Arch Linux or Omarchy

```bash
curl -fsSL https://raw.githubusercontent.com/Aayush9029/OmaSend/main/install.sh | bash
```

The installer places `omasend` in `~/.local/bin`, enables the user service, and installs the OmaSend bar panel when Omarchy Shell is present.

Required Linux packages:

```bash
sudo pacman -S wl-clipboard
```

## Pair the computers

1. On Linux, run `omasend pair show`.
2. On the Mac, open OmaSend Settings, choose Devices, and select Pair Another Device.
3. Enter the Linux pairing code.

Both apps reconnect automatically. The same pairing code works over the local network and Tailscale.

## Auto Copy

Clipboard history is always shared. Auto Copy only controls whether a received item immediately replaces the current system clipboard.

Turn it on from either menu, or on Linux run:

```bash
omasend auto on
```

## Linux CLI

```text
omasend status
omasend history
omasend auto <on|off>
omasend copy <item-id>
omasend pair <show|copy|set|regenerate>
```

## Build from source

Linux:

```bash
./scripts/build-linux.sh
```

macOS:

```bash
cd macos
swift test
./script/build_and_run.sh
```

See [PROTOCOL.md](PROTOCOL.md) for the wire format and security model.

## License

MIT
