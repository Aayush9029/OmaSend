#requires -Version 5.1
<# Installs a verified, self-contained OmaSend release for the current user.
   Run from PowerShell using your normal execution policy. No elevation required. #>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^v?\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$')][string]$Version,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs/OmaSend'),
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows is required.' }
$repository = 'Aayush9029/OmaSend'
$headers = @{ 'User-Agent' = 'OmaSend-Installer'; Accept = 'application/vnd.github+json' }
if (!$Version) {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repository/releases/latest" -Headers $headers
    $Version = $release.tag_name
}
if ($Version -notmatch '^v?\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$') { throw 'Invalid release version.' }
$number = $Version.TrimStart('v')
$tag = "v$number"
$machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$architecture = switch ($machine) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { throw "Unsupported architecture: $machine" } }
$name = "OmaSend_${number}_windows_${architecture}.zip"
$target = [IO.Path]::GetFullPath((Join-Path $InstallRoot $number))
if (!$PSCmdlet.ShouldProcess($target, "Install OmaSend $tag from GitHub with SHA-256 verification")) { return }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('omasend-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $archive = Join-Path $temporary $name
    $base = "https://github.com/$repository/releases/download/$tag"
    Invoke-WebRequest "$base/$name" -OutFile $archive -UseBasicParsing
    Invoke-WebRequest "$base/checksums.txt" -OutFile (Join-Path $temporary 'checksums.txt') -UseBasicParsing
    $entries = @(Get-Content -LiteralPath (Join-Path $temporary 'checksums.txt') | Where-Object { $_ -match ('^[a-fA-F0-9]{64}\s+\*?' + [regex]::Escape($name) + '$') })
    if ($entries.Count -ne 1) { throw 'Release checksum missing or ambiguous.' }
    $expected = ($entries[0] -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'Download checksum mismatch. Nothing was installed.' }
    $stage = Join-Path $temporary 'app'
    Expand-Archive -LiteralPath $archive -DestinationPath $stage
    if (!(Test-Path -LiteralPath (Join-Path $stage 'OmaSend.exe'))) { throw 'Release does not contain OmaSend.exe.' }
    if (Test-Path -LiteralPath $target) { throw "This version is already installed at $target." }
    # Invoke-WebRequest does not reliably set MOTW. Preserve normal Windows checks explicitly.
    Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
        Set-Content -LiteralPath ($_.FullName + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3`r`nHostUrl=$base/$name" -Encoding ascii
    }
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Move-Item -LiteralPath $stage -Destination $target
    if (!$NoShortcut) {
        $shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'OmaSend.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $target 'OmaSend.exe'
        $shortcut.WorkingDirectory = $target
        $shortcut.Description = 'Native encrypted clipboard sharing'
        $shortcut.Save()
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
    }
    Write-Host "Installed OmaSend $tag. Open OmaSend from the Start menu."
    Write-Host 'The Windows build is unsigned. Windows may show its normal publisher warning.'
} finally {
    # The only recursive deletion is the newly created, verified temporary directory.
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    if ($resolvedTemporary.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($resolvedTemporary) -match '^omasend-install-[a-f0-9]{32}$')) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
