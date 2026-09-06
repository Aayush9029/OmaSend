# Install OmaSend

## Windows 11

Download the **Windows x64** or **Windows ARM64** ZIP from [Releases](https://github.com/Aayush9029/OmaSend/releases/latest), extract it, and open `OmaSend.exe`. The .NET runtime is included.

For a per-user installation with a Start menu shortcut, download `install.ps1` from the same release, review it, and run it from PowerShell using your normal execution policy:

```powershell
./install.ps1
```

The installer verifies the ZIP against the release's SHA-256 manifest before installing to `%LOCALAPPDATA%/Programs/OmaSend/<version>`. It does not request administrator access, disable execution policy, remove download protection, or change firewall rules. Checksums verify download integrity over HTTPS; they are not publisher signatures. The Windows binaries are unsigned and may trigger Windows' normal publisher checks.

If Windows requests network access, allow OmaSend only on networks you trust. Local discovery uses UDP 5353 and clipboard transfers use TCP 53317. If discovery is unavailable, add the other devices' IP addresses in Settings. Tailscale must already be installed and connected to use its discovery path.

Close the window to keep the app in the tray. Choose **Quit OmaSend** in the tray menu to stop sharing. Enable **Launch at sign-in** in Settings if desired. To remove OmaSend, disable that option, quit, and delete its installation folder and Start menu shortcut. Encrypted history/settings remain under `%LOCALAPPDATA%/OmaSend/Data` until you delete them.

## Linux

Use a Wayland desktop with `wl-copy`, `wl-paste`, systemd user services, `curl`, `tar`, and `sha256sum`. Install `wl-clipboard` using your distribution's package manager first.

```bash
curl -fsSLO https://raw.githubusercontent.com/Aayush9029/OmaSend/main/install.sh
bash install.sh
```

The installer downloads the matching amd64 or arm64 release, checks its SHA-256 hash, and starts the user service. Use `omasend status`, `omasend history`, and `omasend auto on`. Generic Linux has a native Go service and CLI; the graphical panel is specific to Omarchy Shell. X11 is not supported.

## Omarchy

Use the Linux installer above. When both `omarchy` and `omarchy-shell` are available, it also installs and enables the existing clipboard panel. This targets [Basecamp's Omarchy](https://github.com/basecamp/omarchy), the Arch/Hyprland distribution, with its [Omarchy Shell plugin API](https://github.com/basecamp/omarchy/blob/quattro/manual/32-shell-plugins.md). Older Waybar-only versions can use the CLI but do not have this panel.

## macOS

Download the macOS ARM64 ZIP from [Releases](https://github.com/Aayush9029/OmaSend/releases/latest), extract it, and move OmaSend to Applications. macOS 15 or later is required. The automated build uses an ad-hoc signature and is not notarized; it may be blocked by your Mac's normal security policy. No security settings are changed by OmaSend.

The existing Developer ID/notarization packaging script remains available for maintainers with signing credentials. To build from source with Xcode command-line tools:

```bash
bash macos/script/build_and_run.sh
```

## Pair and share

Copy the pairing code from one device and enter that exact code on every other device. Adding a third device does not require replacing the code on the first two. Treat the code as a shared secret: anyone with it can read and send clipboard items.

All connected peers receive locally copied text, supported images, and the first regular, nonempty file in a clipboard file selection. Files arrive under `Downloads/OmaSend`. Windows marks received files as downloaded. Nothing executes automatically. History clearing keeps downloaded files.

Update all clients to 0.2.0 for the full 10 MiB image limit. Older clients can still exchange smaller clipboard items and encrypted file streams. Peers must be directly reachable; this is a mesh, not a relay through a third computer.
