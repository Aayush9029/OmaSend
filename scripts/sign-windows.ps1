#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$CertificateThumbprint,
    [Parameter(Mandatory)][string]$SignTool
)
$ErrorActionPreference = 'Stop'
$stage = (Resolve-Path -LiteralPath $PackageDirectory).Path
$tool = (Resolve-Path -LiteralPath $SignTool).Path
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint"
if (!$certificate.HasPrivateKey -or $certificate.NotAfter -le (Get-Date)) { throw 'A valid code-signing certificate with a private key is required.' }
if ($certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') { throw 'Smart App Control requires an RSA certificate.' }
if (!($certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' })) { throw 'The certificate must allow code signing.' }
if (!$certificate.Verify()) { throw 'The signing certificate must have a valid trusted chain.' }
$files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.Extension -in @('.exe','.dll') })
if (!$files.Count -or !(Test-Path -LiteralPath (Join-Path $stage 'OmaSend.exe'))) { throw 'This is not an OmaSend package directory.' }
foreach ($file in $files) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -eq 'NotSigned') {
        & $tool sign /sha1 $CertificateThumbprint /s My /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Signing failed: $($file.Name)" }
    }
    & $tool verify /pa $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($file.Name)" }
}
Write-Output "Verified signatures on $($files.Count) package binaries."
