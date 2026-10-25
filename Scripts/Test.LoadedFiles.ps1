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
$stubDirectory = Join-Path $PSScriptRoot 'LoadedFilesTests'
$helperSource = [IO.File]::ReadAllText((Join-Path $sourceDirectory 'h5u.DAI.OTA.Helpers.pas'))
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
$helperMethods = foreach ($methodName in @('RunOnMainThread', 'LoadedFileNames', 'IsFileLoadedInIDE', 'FindModuleByFileName', 'IsWorkspaceFile')) {
    $pattern = '(?ms)^class (?:function|procedure) TDAIOTA\.' + [regex]::Escape($methodName) + '(?=[:(]).*?(?=^class (?:function|procedure) TDAIOTA\.|\z)'
    $methodMatches = [regex]::Matches($helperSource, $pattern)
    if ($methodMatches.Count -ne 1) {
        throw "Die Produktivmethode ist nicht mehr eindeutig: $methodName"
    }
    $methodMatches[0].Value
}

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-LoadedFiles-$currentPlatform"
    $dcuDirectory = $outputDirectory + '-Dcu'
    $generatedDirectory = $outputDirectory + '-Generated'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $generatedDirectory | Out-Null
    [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.LoadedFiles.Helpers.inc'),
        ($helperMethods -join [Environment]::NewLine), [Text.UTF8Encoding]::new($true))
    # Compile the production collector and exact helper methods against isolated, read-only OTA snapshots.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-I$generatedDirectory"
        "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.LoadedFiles.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "LoadedFiles-Test für $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.LoadedFiles.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "LoadedFiles-Test für $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
