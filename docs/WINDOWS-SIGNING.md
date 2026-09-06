# Windows signing

The current unsigned Windows build is blocked on a machine with Smart App Control enabled. Bundling .NET removes the runtime installation requirement; it does not establish publisher trust. Do not describe unsigned archives as universally runnable on Windows 11.

## Obtain a signing identity

- Microsoft Store MSIX distribution: create a developer account, reserve the app identity, and complete certification. Microsoft signs the submitted package. This does not sign the existing standalone ZIP.
- Direct-download distribution: use an RSA code-signing identity from a trusted provider, such as Azure Artifact Signing, a certificate authority, or the SignPath Foundation program for eligible open-source projects. Identity validation and provider approval are external prerequisites.

No publisher account, signing certificate, or signing credentials are currently configured for OmaSend. Self-signing alone is not a Smart App Control solution.

## Existing certificate workflow

With a trusted RSA certificate available in the current-user Windows certificate store and SignTool from the Windows SDK, sign a published staging folder before archiving it:

```powershell
./scripts/sign-windows.ps1 -PackageDirectory .build/windows/0.2.0/win-x64 -CertificateThumbprint <thumbprint> -SignTool <path-to-signtool.exe>
```

The script signs unsigned EXE/DLL files, retains existing signatures, and verifies every executable binary. After signing, recreate the ZIP and SHA-256 manifest; signatures change the binary hashes. Then validate the signed package under Smart App Control before publishing it. Cloud signing requires the selected provider's supported integration instead of this certificate-store command.

The script does not create certificates, install roots, alter security policies, or submit a package to a store.

Sources: [Microsoft signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options), [Smart App Control signing](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control).
