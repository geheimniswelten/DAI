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
$paletteSource = [IO.File]::ReadAllText((Join-Path $sourceDirectory 'h5u.DAI.OTA.Palette.pas'))
$startMarker = "const`n  CMaximumPaletteResults"
$normalizedSource = $paletteSource.Replace("`r`n", "`n")
$endMarker = 'class function TDAIPaletteService.ListComponents('
if ([regex]::Matches($normalizedSource, [regex]::Escape($startMarker)).Count -ne 1 -or
    [regex]::Matches($normalizedSource, [regex]::Escape($endMarker)).Count -ne 1) {
    throw 'Die produktiven Palettenfunktionen sind nicht mehr eindeutig.'
}
$start = $normalizedSource.IndexOf($startMarker, [StringComparison]::Ordinal)
$end = $normalizedSource.IndexOf($endMarker, $start, [StringComparison]::Ordinal)
$productionFunctions = $normalizedSource.Substring($start, $end - $start)
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    $outputDirectory = Join-Path $projectRoot "Build\Tests-Palette-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $generatedDirectory = ($outputDirectory + '-Generated')
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $generatedDirectory | Out-Null
    # Test the exact production traversal/parsing with original SDK interface doubles.
    [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.Palette.Functions.inc'),
        $productionFunctions, [Text.UTF8Encoding]::new($true))
    & $compiler '-LUrtl;vcl;designide' '-B' '-Q' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" `
        "-I$generatedDirectory" "-U$sourceDirectory;$toolsApiDirectory;$libraryDirectory" `
        (Join-Path $PSScriptRoot 'Test.Palette.dpr')
    if ($LASTEXITCODE -ne 0) {
        throw "Palette fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.Palette.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Palette fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
