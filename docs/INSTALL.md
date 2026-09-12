# Install OmaSend

## Windows 11

Download the Windows Setup.exe for x64 or ARM64 from Releases and run it. Setup installs for the current user, includes .NET, creates a Start menu shortcut, and registers an uninstaller. Settings and encrypted history remain in `%LOCALAPPDATA%/OmaSend/Data` during upgrades and uninstall.

For PowerShell installation use the command in the README. It uses `-ExecutionPolicy Bypass` for that process only, downloads the matching Setup.exe, verifies its release SHA-256 checksum, and opens Setup. Windows publisher checks still apply; the installer is currently unsigned.

Discovery uses UDP 5353; transfers use TCP 53317. Allow OmaSend through the firewall on your local network. Both devices need the same pairing code and sharing mode. Settings save automatically. If multicast is blocked, add peer IP addresses in Settings.

Quit from the tray menu before replacing a manually extracted older copy. Use Windows Installed apps to uninstall Setup-installed copies.

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

With Homebrew installed, run:

```bash
brew tap aayush9029/omasend https://github.com/Aayush9029/OmaSend && brew install --cask aayush9029/omasend/omasend
```

The cask is pinned to the published macOS release and its SHA-256 hash.

Alternatively, download the DMG from the [macOS 0.2.1 release](https://github.com/Aayush9029/OmaSend/releases/tag/macos-v0.2.1), open it, and drag OmaSend into Applications. This release is Developer ID signed and notarized by Apple. It requires Apple Silicon and macOS 15 or later. A ZIP archive is also available.

To build from source with Xcode command-line tools:

```bash
bash macos/script/build_and_run.sh
```

## Pair and share

Copy the pairing code from one device and enter that exact code on every other device. Adding a third device does not require replacing the code on the first two. Treat the code as a shared secret: anyone with it can read and send clipboard items.

All connected peers receive locally copied text, supported images, and the first regular, nonempty file in a clipboard file selection. Files arrive under `Downloads/OmaSend`. Windows marks received files as downloaded. Nothing executes automatically. History clearing keeps downloaded files.

Update all clients to 0.2.0 for the full 10 MiB image limit. Older clients can still exchange smaller clipboard items and encrypted file streams. Peers must be directly reachable; this is a mesh, not a relay through a third computer.
