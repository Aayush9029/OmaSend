<p align="center">
  <img src="assets/AppIcon.png" width="88" alt="OmaSend">
</p>

<h1 align="center">OmaSend</h1>
<p align="center">One encrypted clipboard across Windows, macOS, and Linux.</p>

Share text, images, and files directly between your computers. No cloud or account. Includes clipboard history, auto copy, and resumable file transfers.

## Windows

<img src="assets/screenshots/omasend-windows.png" width="360" alt="OmaSend Windows tray panel with an Auto copy switch and sample clipboard history">

Native Windows 11 tray app. x64 and ARM64 packages include .NET; there is no separate runtime to install.

**Preview:** a Windows release has not been published yet. This one-line PowerShell installer is ready for the first Windows release:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/Aayush9029/OmaSend/main/install.ps1 -OutFile "$env:TEMP\OmaSend-install.ps1"; & "$env:TEMP\OmaSend-install.ps1"
```

The current build is unsigned and can be blocked by Smart App Control. [Windows install details](docs/INSTALL.md#windows-11).

<sub>Windows image rendered from the current native WPF app on a Windows CI runner, using sample history.</sub>

## macOS

<img src="assets/screenshots/omasend-macos.jpeg" width="300" alt="OmaSend macOS menu-bar app">

Apple Silicon, macOS 15 or later. With [Homebrew](https://brew.sh) installed:

```bash
brew tap aayush9029/omasend https://github.com/Aayush9029/OmaSend && brew install --cask aayush9029/omasend/omasend
```

Or [download the macOS app](https://github.com/Aayush9029/OmaSend/releases/latest). The tap uses this repository and installs the checksum-pinned published release. macOS security checks still apply.

## Linux

<img src="assets/screenshots/omasend-linux.jpeg" width="300" alt="OmaSend panel on Omarchy Linux">

Wayland with `wl-clipboard` and systemd user services:

```bash
curl -fsSL https://raw.githubusercontent.com/Aayush9029/OmaSend/main/install.sh | bash
```

The installer also enables the panel on compatible **Omarchy Shell** systems. Other Wayland desktops use the native daemon and CLI: `omasend status`. [Linux install details](docs/INSTALL.md#linux).

## Pair your devices

Use the same pairing code on every computer: **Settings > Pairing code** on Windows, **OmaSend Settings > Devices** on macOS, or `omasend pair set <code>` on Linux. Enable **Auto copy** to put received items directly on the clipboard.

## Security

Clipboard data travels directly between paired devices over your local network or Tailscale, encrypted with AES-256-GCM using your shared pairing code; keep that code private.

[Protocol](PROTOCOL.md) · [Build and screenshots](docs/DEVELOPMENT.md) · [Test results](docs/VALIDATION.md) · [MIT license](LICENSE)
