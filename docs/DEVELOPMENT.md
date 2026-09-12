# Development

Windows uses WPF on .NET 10, Windows clipboard APIs, DPAPI storage, and a separate C# protocol/transport assembly. It has no browser engine. mDNS uses the pinned Makaretu library; discovery results become connected peers only after an encrypted hello succeeds. Each pairing group uses the existing shared-secret protocol.

```powershell
dotnet restore windows/OmaSend/OmaSend.csproj --locked-mode
dotnet build windows/OmaSend/OmaSend.csproj -c Release
dotnet run --project windows/OmaSend.Tests -c Release
dotnet run --project windows/OmaSend.WindowsTests -c Release
pip install -r tests/requirements.txt
python tests/interop.py --bridge windows/OmaSend.Tests/bin/Release/net10.0/OmaSend.Tests.dll
dotnet run --project windows/OmaSend.WindowsTests -c Release -- settings
dotnet run --project windows/OmaSend.WindowsTests -c Release -- discovery
./scripts/package-windows.ps1 -Version 0.2.2
```

The default Windows-only test writes generated text, a PNG, and a file reference to the real clipboard. Run it in an interactive user session. The `settings` test uses isolated settings; `discovery` uses a simulated multicast peer that splits TXT/SRV/address responses. The core and Python suites use loopback sockets and isolated temporary files; their remote peers are simulations.

Packaging requires Inno Setup 6 (`ISCC.exe`); pass `-Compiler` if it is outside the standard install folder. The script emits self-contained x64 and ARM64 Setup.exe installers with SHA-256 sidecars.

For an isolated interactive app test, initialize a fresh directory with `OmaSend.WindowsTests init <directory>`, then launch the app with `OMASEND_DATA_DIR` set to that directory, `OMASEND_PORT=53319`, `OMASEND_DOWNLOADS` set to an empty test folder, and `OMASEND_NO_DISCOVERY=1`. The initializer uses the public test-vector code and must never be used for normal sharing. Run `tests/windows_ui.py --helper <WindowsTests.dll> --downloads <test-folder>` to check real clipboard integration with two Python peers. `--keep-peers` retains them for up to 30 minutes for screenshot capture.

`tests/mdns_windows.py` requires `zeroconf==0.151.3`. Run it alongside an isolated app on port 53320 with discovery enabled. It checks actual Windows multicast advertisement and discovery of a Python service, followed by an authenticated hello.

Linux: `cd linux && go test ./... && go vet ./...`. Tests include three native Go TCP peers without requiring a clipboard server. macOS: `cd macos && swift test`; this includes native Network.framework TCP fanout. These tests exercise real platform runtimes when executed on their matching CI hosts, but are not a physical three-computer LAN test.

## Screenshots

The repository originally contained real macOS and Omarchy screenshots without a capture script. Keep those captures unless you can run the corresponding desktop. Do not generate or relabel a Windows image as another platform.

For Windows, populate the isolated running app using `tests/windows_ui.py`, open its panel, and capture the actual OmaSend window. Save the unmodified window capture to `assets/screenshots/omasend-windows.png`. The test peers are labeled Python test peers in the UI. The README displays all three platform captures at the same width.

## Releases

CI tests and builds all three platforms. The release workflow tests again, packages Windows x64/ARM64, Linux amd64/arm64, and macOS ARM64, then creates a draft containing a combined checksum manifest and Windows installer. A maintainer validates the draft assets before publishing it.

The macOS job signs the app and DMG with the Developer ID certificate and notarizes both with Apple when the repository secrets `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_NOTARY_KEY_BASE64`, `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER` are set. `APPLE_CERTIFICATE_PASSWORD` is optional. The job imports the certificate into a temporary keychain, runs `macos/script/package_release.sh`, validates the staple, and deletes the keychain. Without the secrets, the job falls back to an ad-hoc signed ZIP. Windows executables are unsigned.

## Windows README capture

Run the **Windows screenshot** workflow to render the current native WPF window on a Windows runner. The `OmaSend.Screenshots` harness uses isolated settings, disables network discovery, and supplies sample clipboard history. Download `windows-screenshot`, inspect the PNG, and replace `assets/screenshots/omasend-windows.png`. It is a native app render, not a photograph of the user's desktop; the README labels this distinction.

## Homebrew updates

This repository doubles as the `aayush9029/omasend` tap through its explicit Git URL. After publishing a macOS release, update `Casks/omasend.rb` with the version and the archive SHA-256. The Homebrew workflow parses the cask and fetches the real archive to verify its checksum.
