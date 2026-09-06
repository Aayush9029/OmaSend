#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$')][string]$Version = '0.2.0',
    [ValidateSet('win-x64', 'win-arm64')][string[]]$Runtime = @('win-x64', 'win-arm64')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
foreach ($rid in $Runtime) {
    $stage = Join-Path $repoRoot ".build/windows/$Version/$rid"
    & dotnet publish (Join-Path $repoRoot 'windows/OmaSend/OmaSend.csproj') -c Release -r $rid --self-contained true -p:RestoreLockedMode=true -p:Version=$Version -p:DebugType=None -o $stage
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $repoRoot 'windows/THIRD-PARTY-NOTICES.txt') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $repoRoot 'windows/licenses') -Destination $stage -Recurse -Force
    $architecture = $rid.Substring(4)
    $archive = Join-Path $dist "OmaSend_${Version}_windows_${architecture}.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -Force
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
}
