Windows update:

- Native Setup.exe installers for x64 and ARM64, with bundled .NET, Start menu entry, upgrade support, and uninstall.
- PowerShell installation uses a process-scoped execution-policy override and selects Windows releases by their assets.
- Bonjour resolution collects split service records and retries queries; advertisements repeat for peers joining later.
- Settings save automatically: switches immediately, text after a short pause.
- Removed the web companion source, embedded assets, packaging, tests, and CI jobs.

Windows executables are unsigned. The macOS app and DMG are Developer ID signed and notarized by Apple. Standard operating-system security checks remain enabled.

See docs/VALIDATION.md for executed tests and platform limitations.

