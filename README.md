<p align="center">
  <img src="assets/AppIcon.png" width="88" alt="OmaSend clipboard icon">
</p>

<h1 align="center">OmaSend</h1>

<p align="center">One encrypted clipboard across macOS, Windows, and Linux.</p>

<p align="center">
  <a href="docs/INSTALL.md#windows-11"><img src="https://img.shields.io/badge/Install-Windows-0078D4?style=for-the-badge" alt="Install for Windows"></a>
  <a href="docs/INSTALL.md#linux"><img src="https://img.shields.io/badge/Install-Linux-E9B44C?style=for-the-badge" alt="Install for Linux"></a>
  <a href="docs/INSTALL.md#omarchy"><img src="https://img.shields.io/badge/Install-Omarchy-1793D1?style=for-the-badge" alt="Install for Omarchy"></a>
  <a href="docs/INSTALL.md#macos"><img src="https://img.shields.io/badge/Install-macOS-555555?style=for-the-badge" alt="Install for macOS"></a>
</p>

<p align="center">
  <img src="assets/screenshots/omasend-macos.jpeg" width="245" alt="OmaSend on macOS">
  <img src="assets/screenshots/omasend-windows.png" width="245" alt="OmaSend on Windows 11 with two simulated test peers">
  <img src="assets/screenshots/omasend-linux.jpeg" width="245" alt="OmaSend on Omarchy Linux">
</p>

Text, images, and files travel directly over your local network or Tailscale with AES-256-GCM encryption. No cloud or account. Native apps, 50-item history, and resumable file transfers.

Use **the same pairing code on every device**. Open **Settings > Pairing code** on Windows or **OmaSend Settings > Devices** on macOS. On Linux, run `omasend pair show` or `omasend pair set <code>`. All three can connect at once. Enable **Auto copy** to put incoming items on your clipboard.

Linux requires Wayland and `wl-clipboard`. The Omarchy panel uses Omarchy Shell plugin support. Windows builds are unsigned; CI macOS builds are not notarized. [Install details](docs/INSTALL.md).

[Protocol](PROTOCOL.md) · [Build and screenshots](docs/DEVELOPMENT.md) · [Test results](docs/VALIDATION.md) · [MIT](LICENSE)
