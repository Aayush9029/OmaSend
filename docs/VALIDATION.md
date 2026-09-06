# Validation for 0.2.0

## Executed on the Windows 11 x64 development computer

- Release WPF build with zero warnings/errors.
- C# core suite: 28 checks, including Go/Swift vectors, malformed framing, wrong secrets, tampering, safe filenames, replay/history bounds, three simultaneous C# TCP peers, and multi-chunk file fanout.
- Independent Python AES-GCM interoperability: bidirectional Unicode and PNG, two peers at once, fragmented TCP, interrupted file resume, full-file hash checks, and history clear.
- Real Windows clipboard APIs: text, PNG, file references, and per-user DPAPI settings encryption.
- Running WPF app: two Python peers connected simultaneously; incoming auto-copy; local text and file fanout; no incoming clipboard echo; resumed incoming file; retained Mark of the Web.
- Packaged self-contained Windows x64 app: actual multicast advertisement and discovery of a Python mDNS service followed by encrypted hello.
- Existing Go tests and vet ran on Windows, including three Go TCP peers. This does not count as Linux desktop execution.

## CI and limits

Native Linux and macOS CI execution results will be recorded after the workflow completes. Windows ARM64 is cross-built; no ARM64 runtime test has been performed. Tailscale parsing is implemented, but no live tailnet or physical macOS/Windows/Linux three-machine test has been performed. Existing macOS and Omarchy screenshots were retained; the Windows screenshot is a real app capture with simulated Python peers.

## Windows tray follow-up

The redesigned WPF Fluent popup was visually checked on Windows: Devices and inline Settings navigation, masked pairing field, and native controls. The preview temporarily disabled light dismissal for capture; that diagnostic behavior is removed from packaged builds. Physical desktop coordinates now position the flyout correctly across mixed-DPI monitors. Reopening signals the existing instance without a blocking duplicate-instance dialog.

A real Mac on the local network completed the encrypted hello handshake with the Windows pairing helper, and the running Windows UI showed the Mac connected. This verifies real cross-OS pairing; it is not a claim of an end-to-end physical three-platform clipboard test.

The 28 core checks passed after the redesign. Both Windows architectures bundle their runtime; packaging rejects missing runtime files or references to an external framework. ARM64 packages are built but have not run on ARM64 hardware.
