[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-SourceSearch-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null

    # Compile the real pure source-search/encoding units and test against temporary fixtures.
    # No live IDE, settings, registration or project source is modified.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.SourceSearch.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Quellensuche für $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.SourceSearch.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Quellensuche für $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
