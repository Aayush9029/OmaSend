# Validation for 0.2.0

## Windows update — September 12, 2026

- Native Windows Release build; 46 protocol and transport checks passed.
- Installer-script fixtures passed: platform-specific release selection, checksum verification, download protection, cancelled Setup, and WhatIf.
- Live multicast regression passed with a simulated peer splitting TXT, SRV, and address records across packets, followed by authenticated TCP hello.
- Isolated WPF settings checks passed: immediate switch persistence, debounced device-name save, removal of Save button, and retention of the previous code while an invalid partial code is entered.
- Windows x64 Setup.exe installed successfully with bundled runtime, Start menu shortcut, and uninstaller.
- Remaining Go tests passed on Windows after removing the companion code. No Mac build was run during this Windows work. Physical Mac connectivity was reported working by the user.

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
