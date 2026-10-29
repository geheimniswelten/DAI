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
$helperSource = [IO.File]::ReadAllText((Join-Path $sourceDirectory 'h5u.DAI.OTA.Helpers.pas'))
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

function Get-ProductionMethods {
    param([string]$MethodName, [int]$ExpectedCount)
    $pattern = '(?ms)^class (?:function|procedure) TDAIOTA\.' + [regex]::Escape($MethodName) +
        '\(.*?(?=^class (?:function|procedure) TDAIOTA\.|\z)'
    $methods = [regex]::Matches($helperSource, $pattern)
    if ($methods.Count -ne $ExpectedCount) {
        throw "Die Anzahl der Produktivmethoden hat sich geaendert: $MethodName ($($methods.Count))."
    }
    return ($methods | ForEach-Object { $_.Value }) -join [Environment]::NewLine
}

$readerConstants = [regex]::Matches($helperSource, '(?m)^\s*CEditReaderChunkSize\s*=\s*\d+;')
if ($readerConstants.Count -ne 1) {
    throw 'Die produktive Editor-Lesepuffergroesse ist nicht mehr eindeutig.'
}
$productionMethods = (Get-ProductionMethods 'ReadEditorText' 1) + [Environment]::NewLine +
    (Get-ProductionMethods 'ReplaceEditorText' 2)
$sdkVersion = Split-Path -Leaf $BdsRoot

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-EditorChanges-$sdkVersion-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $generatedDirectory = ($outputDirectory + '-Generated')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $generatedDirectory | Out-Null

    # Execute the production diff unit and exact production reader/writer methods.
    # Interface doubles enforce the SDK's original-byte forward cursor contract.
    # Undo snapshots are simulated; this test never attaches to or changes a live IDE.
    [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.EditorChanges.Constants.inc'),
        ('const' + [Environment]::NewLine + $readerConstants[0].Value.Trim()), [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.EditorChanges.Methods.inc'),
        $productionMethods, [Text.UTF8Encoding]::new($true))
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-I$generatedDirectory"
        "-U$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.EditorChanges.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Editor-Aenderungstest fuer $sdkVersion/$currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.EditorChanges.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Editor-Aenderungstest fuer $sdkVersion/$currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
