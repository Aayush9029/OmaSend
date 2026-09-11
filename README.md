<p align="center">
  <img src="assets/AppIcon.png" width="88" alt="OmaSend">
</p>

<h1 align="center">OmaSend</h1>
<p align="center">One encrypted clipboard across Windows, macOS, and Linux.</p>

<p align="center">
  <img alt="banner" src="https://github.com/user-attachments/assets/4a44ccd5-7396-47e4-aa35-4fa6dc84f095" />
</p>

<p align="center">
  <a href="https://github.com/Aayush9029/OmaSend/releases/download/v0.2.0/OmaSend_0.2.0_windows_x64.zip"><img src="assets/readme/download-windows.svg" alt="Download for Windows"></a>
  <a href="https://github.com/Aayush9029/OmaSend/releases/download/macos-v0.2.1/OmaSend_0.2.1_macOS_arm64.zip"><img src="https://img.shields.io/badge/Download%20for%20macOS-black?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Download for macOS"></a>
  <a href="https://github.com/Aayush9029/OmaSend/releases/download/v0.2.0/omasend_0.2.0_linux_amd64.tar.gz"><img src="https://img.shields.io/badge/Download%20for%20Linux-333333?style=for-the-badge&amp;logo=linux&amp;logoColor=white" alt="Download for Linux"></a>
</p>
<p align="center">Windows x64 · macOS Apple Silicon · Linux x64<br><a href="https://github.com/Aayush9029/OmaSend/releases/latest">All downloads, ARM64 builds and release notes</a></p>

## Windows

Install with one line in PowerShell:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/Aayush9029/OmaSend/main/install.ps1 -OutFile "$env:TEMP\OmaSend-install.ps1"; & "$env:TEMP\OmaSend-install.ps1"
```

## macOS

Apple Silicon, macOS 15 or later. With [Homebrew](https://brew.sh) installed:

```bash
brew tap aayush9029/omasend https://github.com/Aayush9029/OmaSend && brew install --cask aayush9029/omasend/omasend
```

Or [download the signed and notarized macOS app](https://github.com/Aayush9029/OmaSend/releases/tag/macos-v0.2.1). The tap uses this repository and installs the checksum-pinned published release. macOS security checks still apply.

## Linux

Wayland with `wl-clipboard` and systemd user services:

```bash
curl -fsSL https://raw.githubusercontent.com/Aayush9029/OmaSend/main/install.sh | bash
```

The installer also enables the panel on compatible **Omarchy Shell** systems. Other Wayland desktops use the native daemon and CLI: `omasend status`. [Linux install details](docs/INSTALL.md#linux).

## Web companion

Open OmaSend in a browser on your local network. Send text, attach files, copy shared text, and download incoming files. Runs on Windows, macOS and Linux as one executable, with no extra runtime.

Download the [web companion for your OS](https://github.com/Aayush9029/OmaSend/releases/tag/v0.2.0) and run `omasend-web` (`omasend-web.exe` on Windows). No extra runtime is required.

Or build and run from this repository with Go installed:

```sh
cd linux && go run ./cmd/omasend-web
```

Open **http://localhost:53318**. Add `--lan YOUR_LAN_IP` to make it available to other browsers on that network. [Setup, packaged builds and browser limits](docs/WEB.md).

## Security

By default, clipboard data and files travel directly between paired devices using AES-256-GCM. Optional Trusted LAN skips keys and encryption: anyone on that network can read or send items. The browser-to-companion LAN HTTP connection is also unencrypted.

[Protocol](PROTOCOL.md) · [Build and screenshots](docs/DEVELOPMENT.md) · [Test results](docs/VALIDATION.md) · [MIT license](LICENSE)
