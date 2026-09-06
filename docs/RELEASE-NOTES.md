Clipboard and file sharing across Windows, macOS, Linux, and a new local browser companion.

- OmaSend Web sends text and files, displays shared history, and downloads received items. One executable runs on each OS with no extra runtime. Browser access stays local; optional LAN access uses unencrypted HTTP.
- Optional Trusted LAN mode on all native clients and the companion shares without copying keys. It is unencrypted, disabled by default, and must be enabled on each device. Encrypted pairing remains available and existing keys are preserved.

- Windows tray app with text, PNG/image clipboard, resumable encrypted file transfers, clipboard history, pairing, optional peer hosts, Tailscale discovery, and sign-in startup.
- Multiple paired devices share one code and receive each local clipboard change directly.
- Fixes Linux malformed-nonce handling, discovery authentication, clipboard echo races, and pairing-code copy behavior. Fixes macOS received-file auto-copy and discovery after pairing changes.
- Raises the encrypted frame limit to support the documented 10 MiB image limit. Older clients remain compatible for smaller items; update all clients for full-size images.
- Windows installer and Linux installer verify release SHA-256 checksums before installing.

Windows executables are unsigned. The macOS app in this release has an ad-hoc signature and is not notarized. No Microsoft approval or Apple Developer ID signing is claimed. Standard operating-system security checks remain enabled.

See docs/WEB.md for browser setup and docs/VALIDATION.md for executed tests and platform limitations. The Windows README image is rendered from the native WPF app on a Windows CI runner with sample history.
