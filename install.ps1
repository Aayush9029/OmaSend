#requires -Version 5.1
<# Installs a verified, self-contained OmaSend release for the current user.
   Run from PowerShell using your normal execution policy. No elevation required. #>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^v?\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$')][string]$Version,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs/OmaSend')
)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows is required.' }
$repository = 'Aayush9029/OmaSend'
$headers = @{ 'User-Agent' = 'OmaSend-Installer'; Accept = 'application/vnd.github+json' }
$machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$architecture = switch ($machine) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { throw "Unsupported architecture: $machine" } }
if (!$Version) {
    # Platform-specific releases (for example macos-v0.2.1) can be latest.
    for ($page = 1; !$Version; $page++) {
        $releases = @(Invoke-RestMethod "https://api.github.com/repos/$repository/releases?per_page=100&page=$page" -Headers $headers)
        foreach ($release in $releases) {
            if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v\d+\.\d+\.\d+$') { continue }
            $candidate = $release.tag_name.Substring(1)
            if ($release.assets.name -contains "OmaSend_${candidate}_windows_${architecture}_Setup.exe" -and $release.assets.name -contains 'checksums.txt') {
                $Version = $release.tag_name
                break
            }
        }
        if (!$Version -and $releases.Count -lt 100) { throw "No published Windows $architecture release with checksums was found." }
    }
}
if ($Version -notmatch '^v?\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$') { throw 'Invalid release version.' }
$number = $Version.TrimStart('v')
$tag = "v$number"
$name = "OmaSend_${number}_windows_${architecture}_Setup.exe"
$target = [IO.Path]::GetFullPath($InstallRoot)
if (!$PSCmdlet.ShouldProcess($target, "Run OmaSend Setup $tag from GitHub with SHA-256 verification")) { return }
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
    # Keep Windows download/publisher checks on the verified installer.
    Set-Content -LiteralPath ($archive + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3`r`nHostUrl=$base/$name" -Encoding ascii
    $arguments = @('/NORESTART', ('/DIR="' + $target + '"'))
    $process = Start-Process -FilePath $archive -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "OmaSend Setup did not finish (exit code $($process.ExitCode))." }
    Write-Host "Installed OmaSend $tag. Open OmaSend from the Start menu."

} finally {
    # The only recursive deletion is the newly created, verified temporary directory.
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    if ($resolvedTemporary.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($resolvedTemporary) -match '^omasend-install-[a-f0-9]{32}$')) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
