# Validation for 0.2.0

## Web companion and Trusted LAN — September 6, 2026

[CI run 34011583158](https://github.com/Aayush9029/OmaSend/actions/runs/34011583158) passed for Windows, macOS and Linux at commit `3d63bd1`.

- Windows: WPF Release build, 46 C# checks, installer checks, independent Python TCP interoperability in encrypted and Trusted LAN modes. Tests cover Unicode, PNG, two-peer fanout, fragmented frames, multi-chunk files, interrupted resume, completion hashes and malformed messages.
- macOS: native Swift tests and Release build. TCP fanout ran in both modes, including different keys in Trusted LAN mode. Old configurations, mode separation, LAN address restrictions and matching Go/C# chunk vectors were checked.
- Linux: Go tests, vet and race checks. Browser tests cover real loopback TCP text delivery, upload/download, persisted settings, arbitrary-path rejection, Host/Origin restrictions and host-only security settings.
- The Go browser engine sent multi-chunk files in both directions in both modes on Windows and Linux. This caught and fixed the Windows requirement to close a received file before renaming it.
- Web packages built for Windows, macOS and Linux on x64 and ARM64 with no external runtime. Cross-compilation is not an ARM64 hardware test.
- The browser interface was visually inspected on Windows. Sending text added a real history item; Copy completed; Paste displayed the manual fallback when browser clipboard reading was unavailable. WebMCP read/send tools passed, including rejection of empty text.
- The companion authenticated with the user's real Mac using the saved key, then sent a test text frame. The Mac clipboard display and Mac browser reachability were not independently confirmed. Both endpoints must use the same sharing mode.

The current unsigned native WPF build is blocked by Smart App Control on the development machine. Earlier desktop checks below predate that block. Browser background clipboard monitoring is not implemented. No complete physical three-platform clipboard, live Tailscale, Linux desktop UI or ARM64 hardware test has been performed.

## Earlier development sessions (historical)

## Executed on the Windows 11 x64 development computer

- Release WPF build with zero warnings/errors.
- C# core suite: 28 checks, including Go/Swift vectors, malformed framing, wrong secrets, tampering, safe filenames, replay/history bounds, three simultaneous C# TCP peers, and multi-chunk file fanout.
- Independent Python AES-GCM interoperability: bidirectional Unicode and PNG, two peers at once, fragmented TCP, interrupted file resume, full-file hash checks, and history clear.
- Real Windows clipboard APIs: text, PNG, file references, and per-user DPAPI settings encryption.
- Running WPF app: two Python peers connected simultaneously; incoming auto-copy; local text and file fanout; no incoming clipboard echo; resumed incoming file; retained Mark of the Web.
- Packaged self-contained Windows x64 app: actual multicast advertisement and discovery of a Python mDNS service followed by encrypted hello.
- Existing Go tests and vet ran on Windows, including three Go TCP peers. This does not count as Linux desktop execution.

## CI and limits

Current native CI results are recorded above. Windows ARM64 is cross-built; no ARM64 runtime test has been performed. Existing macOS and Omarchy screenshots were retained; the current Windows README image is a native WPF render on a Windows CI runner with sample history.

## Windows tray follow-up

The redesigned WPF Fluent popup was visually checked on Windows: Devices and inline Settings navigation, masked pairing field, and native controls. The preview temporarily disabled light dismissal for capture; that diagnostic behavior is removed from packaged builds. Physical desktop coordinates now position the flyout correctly across mixed-DPI monitors. Reopening signals the existing instance without a blocking duplicate-instance dialog.

A real Mac on the local network completed the encrypted hello handshake with the Windows pairing helper, and the running Windows UI showed the Mac connected. This verifies real cross-OS pairing; it is not a claim of an end-to-end physical three-platform clipboard test.

The 28 core checks passed after the redesign. Both Windows architectures bundle their runtime; packaging rejects missing runtime files or references to an external framework. ARM64 packages are built but have not run on ARM64 hardware.
