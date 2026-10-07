[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS,
    [switch]$StrictSeparators
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$stubDirectory = Join-Path $PSScriptRoot 'SourcePathsTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-SourcePaths-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    # Compile real Settings with a read-only OTA double. Save is never called.
    # Each test process restores its environment and reads only a fresh GUID registry root.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.SourcePaths.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Quellpfadtest für $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    if ($StrictSeparators) {
        & (Join-Path $outputDirectory 'Test.SourcePaths.exe') -strict-separators
    } else {
        & (Join-Path $outputDirectory 'Test.SourcePaths.exe')
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Quellpfadtest für $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
