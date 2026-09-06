Native Windows 11 support for encrypted clipboard sharing across macOS, Windows, and Linux.

- Windows tray app with text, PNG/image clipboard, resumable encrypted file transfers, clipboard history, pairing, optional peer hosts, Tailscale discovery, and sign-in startup.
- Multiple paired devices share one code and receive each local clipboard change directly.
- Fixes Linux malformed-nonce handling, discovery authentication, clipboard echo races, and pairing-code copy behavior. Fixes macOS received-file auto-copy and discovery after pairing changes.
- Raises the encrypted frame limit to support the documented 10 MiB image limit. Older clients remain compatible for smaller items; update all clients for full-size images.
- Windows installer and Linux installer verify release SHA-256 checksums before installing.

Windows executables are unsigned. The macOS app in this release has an ad-hoc signature and is not notarized. No Microsoft approval or Apple Developer ID signing is claimed. Standard operating-system security checks remain enabled.

See docs/VALIDATION.md for executed tests and platform limitations. Existing macOS/Linux screenshots are retained; the new Windows screenshot was captured from the running app with explicitly simulated Python peers.
