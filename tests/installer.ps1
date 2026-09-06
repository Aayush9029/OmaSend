#requires -Version 5.1
# Uses generated local fixtures; never downloads, launches, or changes Start menu entries.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('omasend-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$global:OmaSendTestBadHash = $false
try {
    $fixture = Join-Path $testRoot 'fixture'
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture 'OmaSend.exe') -Value 'inert installer test fixture' -Encoding ascii
    $global:OmaSendTestArchive = Join-Path $testRoot 'fixture.zip'
    Compress-Archive -LiteralPath (Join-Path $fixture 'OmaSend.exe') -DestinationPath $global:OmaSendTestArchive
    $global:OmaSendTestHash = (Get-FileHash -LiteralPath $global:OmaSendTestArchive -Algorithm SHA256).Hash
    function Invoke-WebRequest {
        param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
        if ($Uri -match '/checksums.txt$') {
            $hash = if ($global:OmaSendTestBadHash) { '0' * 64 } else { $global:OmaSendTestHash }
            @("$hash  OmaSend_0.2.0_windows_x64.zip", "$hash  OmaSend_0.2.0_windows_arm64.zip") | Set-Content -LiteralPath $OutFile -Encoding ascii
        } elseif ($Uri -match '^https://github.com/Aayush9029/OmaSend/releases/download/v0.2.0/OmaSend_0.2.0_windows_(x64|arm64).zip$') {
            Copy-Item -LiteralPath $global:OmaSendTestArchive -Destination $OutFile
        } else { throw "Unexpected download: $Uri" }
    }
    $installRoot = Join-Path $testRoot 'installed'
    & (Join-Path $repo 'install.ps1') -Version 0.2.0 -InstallRoot $installRoot -NoShortcut
    $exe = Join-Path $installRoot '0.2.0/OmaSend.exe'
    if (!(Test-Path -LiteralPath $exe) -or !(Get-Content -LiteralPath ($exe + ':Zone.Identifier') -Raw).Contains('ZoneId=3')) { throw 'Install or MOTW verification failed.' }
    $global:OmaSendTestBadHash = $true
    $rejected = $false
    try { & (Join-Path $repo 'install.ps1') -Version 0.2.0 -InstallRoot (Join-Path $testRoot 'bad') -NoShortcut } catch { $rejected = $_.Exception.Message.Contains('checksum mismatch') }
    if (!$rejected -or (Test-Path (Join-Path $testRoot 'bad/0.2.0'))) { throw 'Checksum mismatch was not rejected before install.' }
    Write-Output 'PASS installer verified extraction, download protection, and corruption rejection'
} finally {
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^omasend-installer-test-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
