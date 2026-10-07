[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [ValidateSet('Static', 'Packages', 'Both')]
    [string]$Linkage = 'Both',
    [switch]$HostPeers,
    [switch]$InheritanceOnly,
    [string]$BdsRoot = $env:BDS
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$stubDirectory = Join-Path $PSScriptRoot 'ProtocolTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
$linkages = if ($Linkage -eq 'Both') { @('Static', 'Packages') } else { @($Linkage) }
if ($HostPeers) {
    if ($Linkage -eq 'Static') { throw '-HostPeers erfordert -Linkage Packages oder Both.' }
    $linkages = @($linkages) + 'HostPeers'
}
foreach ($currentPlatform in $platforms) {
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $runtimeDirectory = Join-Path $BdsRoot $(if ($currentPlatform -eq 'Win64') { 'bin64' } else { 'bin' })
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "Delphi-Compiler nicht gefunden: $compiler" }
    foreach ($currentLinkage in $linkages) {
        $outputDirectory = Join-Path $projectRoot "Build\Tests-ServerLifecycle-$currentPlatform-$currentLinkage"
        $dcuDirectory = ($outputDirectory + '-Dcu')
        New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
        # Actual MCP server/instance/sessions/TCP code; only existing non-IDE protocol stubs are substituted.
        $compilerArguments = @(
            '-B', '-Q', '-$B+', '-$Q+', '-$R+'
            "-E$outputDirectory"
            "-N0$dcuDirectory"
            "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        )
        if ($currentLinkage -ne 'Static') {
            $compilerArguments += '-DDAI_LIFECYCLE_PACKAGES'
            $compilerArguments += '-LUrtl;IndySystem;IndyCore;IndyProtocols'
        }
        $compilerArguments += (Join-Path $PSScriptRoot 'Test.ServerLifecycle.dpr')
        & $compiler @compilerArguments
        if ($LASTEXITCODE -ne 0) { throw "Server-Lifecycle-Test $currentPlatform/$currentLinkage konnte nicht kompiliert werden: $LASTEXITCODE" }
        $savedPath = $env:PATH
        try {
            # The binary verifies its loaded BPL names and prints their actual source paths.
            $env:PATH = "$runtimeDirectory;$savedPath"
            $testArguments = @()
            if ($currentLinkage -eq 'HostPeers') { $testArguments = @('--host-peers', $runtimeDirectory) }
            if ($InheritanceOnly) { $testArguments = @($testArguments) + '--inheritance-only' }
            & (Join-Path $outputDirectory 'Test.ServerLifecycle.exe') @testArguments
            if ($LASTEXITCODE -ne 0) { throw "Server-Lifecycle-Test $currentPlatform/$currentLinkage fehlgeschlagen: $LASTEXITCODE" }
        } finally {
            $env:PATH = $savedPath
        }
    }
}
