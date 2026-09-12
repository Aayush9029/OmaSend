#requires -Version 5.1
# Mocked downloads and process launch; no installer is run.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('omasend-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $global:OmaSendTestFixture = Join-Path $testRoot 'Setup.exe'
    Set-Content -LiteralPath $global:OmaSendTestFixture -Value 'inert setup fixture'
    $global:OmaSendTestHash = (Get-FileHash $global:OmaSendTestFixture).Hash
    $global:OmaSendTestBadHash = $false
    $global:OmaSendTestLaunches = 0
    $global:OmaSendTestExitCode = 0
    function Invoke-RestMethod {
        param([string]$Uri, $Headers)
        if ($Uri -notmatch '/releases\?per_page=100&page=1$') { throw "Unexpected lookup: $Uri" }
        @(
            @{tag_name='macos-v0.2.3'; assets=@(@{name='OmaSend_0.2.3_macOS_arm64.zip'})},
            @{tag_name='v0.2.2'; assets=@(@{name='OmaSend_0.2.2_windows_x64_Setup.exe'}, @{name='OmaSend_0.2.2_windows_arm64_Setup.exe'}, @{name='checksums.txt'})}
        )
    }
    function Invoke-WebRequest {
        param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
        if ($Uri -match '/checksums.txt$') {
            $hash = if ($global:OmaSendTestBadHash) { '0' * 64 } else { $global:OmaSendTestHash }
            @("$hash  OmaSend_0.2.2_windows_x64_Setup.exe", "$hash  OmaSend_0.2.2_windows_arm64_Setup.exe") | Set-Content $OutFile
        } elseif ($Uri -match '/v0.2.2/OmaSend_0.2.2_windows_(x64|arm64)_Setup.exe$') {
            Copy-Item $global:OmaSendTestFixture $OutFile
        } else { throw "Unexpected download: $Uri" }
    }
    function Start-Process {
        param([string]$FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru)
        if (!(Get-Content ($FilePath + ':Zone.Identifier') -Raw).Contains('ZoneId=3')) { throw 'Missing download protection.' }
        if (!$Wait -or !$PassThru -or $ArgumentList[1] -notmatch '^/DIR=".*"$') { throw 'Incorrect Setup arguments.' }
        $global:OmaSendTestLaunches++
        @{ExitCode=$global:OmaSendTestExitCode}
    }
    & "$repo/install.ps1" -InstallRoot (Join-Path $testRoot 'path with spaces')
    if ($global:OmaSendTestLaunches -ne 1) { throw 'Compatible Setup was not run.' }
    $global:OmaSendTestBadHash = $true
    $rejected = $false
    try { & "$repo/install.ps1" -Version 0.2.2 } catch { $rejected = $_.Exception.Message.Contains('checksum mismatch') }
    if (!$rejected -or $global:OmaSendTestLaunches -ne 1) { throw 'Corrupt installer was not rejected.' }
    $global:OmaSendTestBadHash = $false
    $global:OmaSendTestExitCode = 2
    $rejected = $false
    try { & "$repo/install.ps1" -Version 0.2.2 } catch { $rejected = $_.Exception.Message.Contains('exit code 2') }
    if (!$rejected) { throw 'Cancelled Setup incorrectly reported success.' }
    & "$repo/install.ps1" -Version 0.2.2 -WhatIf
    if ($global:OmaSendTestLaunches -ne 2) { throw 'WhatIf ran Setup.' }
    Write-Output 'PASS release selection, verified Setup launch, MOTW, corruption rejection, cancellation, WhatIf'
} finally {
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^omasend-installer-test-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
