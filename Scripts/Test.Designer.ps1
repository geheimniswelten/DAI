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
$designerSource = [IO.File]::ReadAllText((Join-Path $sourceDirectory 'h5u.DAI.OTA.Designer.pas'))
$helperSource = [IO.File]::ReadAllText((Join-Path $sourceDirectory 'h5u.DAI.OTA.Helpers.pas'))
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

function Get-ProductionSection {
    param([string]$Source, [string]$StartMarker, [string]$EndMarker)
    if ([regex]::Matches($Source, [regex]::Escape($StartMarker)).Count -ne 1 -or
        [regex]::Matches($Source, [regex]::Escape($EndMarker)).Count -ne 1) {
        throw "Der Produktivabschnitt ist nicht mehr eindeutig: $StartMarker"
    }
    $start = $Source.IndexOf($StartMarker, [StringComparison]::Ordinal)
    $end = $Source.IndexOf($EndMarker, $start, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) {
        throw "Der Produktivabschnitt ist nicht mehr verfuegbar: $StartMarker"
    }
    return $Source.Substring($start, $end - $start)
}

function Get-ProductionMethod {
    param([string]$Source, [string]$MethodName)
    $pattern = '(?ms)^class (?:function|procedure) TDAIOTA\.' + [regex]::Escape($MethodName) +
        '\(.*?(?=^class (?:function|procedure) TDAIOTA\.|\z)'
    $methodMatches = [regex]::Matches($Source, $pattern)
    if ($methodMatches.Count -ne 1) {
        throw "Die Produktivmethode ist nicht mehr eindeutig: $MethodName"
    }
    return $methodMatches[0].Value
}

$designerFunctions = Get-ProductionSection $designerSource 'function TryComponentString(' 'procedure CollectComponents('
$propertyLimit = [regex]::Matches($designerSource, '(?m)^\s*CMaximumPropertyCharacters\s*=\s*\d+;')
if ($propertyLimit.Count -ne 1) {
    throw 'Das produktive Limit fuer Designer-Strings ist nicht mehr eindeutig.'
}
$designerConstants = 'const' + [Environment]::NewLine + $propertyLimit[0].Value.Trim() + [Environment]::NewLine
$formTextMethods = foreach ($methodName in @('RunOnMainThread', 'FindModuleByFileName', 'FindSourceEditor', 'FindFormEditor',
    'FormFileName', 'EnsureFormTextEditor', 'EnsureFormDesigner', 'ReadEditorText')) {
    Get-ProductionMethod $helperSource $methodName
}
# Only the private transition state/guard section is needed, not the public unit declarations.
$formViewState = Get-ProductionSection $helperSource '  TDAIFormViewRequest = record' 'class function TDAIOTA.ActiveProject:'
$formViewState = 'type' + [Environment]::NewLine + $formViewState
$formViewConstants = [regex]::Match($helperSource,
    '(?m)^\s*CFormViewWaitMilliseconds\s*=\s*\d+;\r?\n\s*CFormViewProbeMilliseconds\s*=\s*\d+;').Value
if ($formViewConstants -eq '') {
    throw 'Die produktiven Formular-Wartezeiten sind nicht mehr verfuegbar.'
}
$readerChunkSize = [regex]::Matches($helperSource, '(?m)^\s*CEditReaderChunkSize\s*=\s*\d+;')
if ($readerChunkSize.Count -ne 1) {
    throw 'Die produktive Editor-Lesepuffergroesse ist nicht mehr eindeutig.'
}
$formViewConstants += [Environment]::NewLine + $readerChunkSize[0].Value.Trim() + [Environment]::NewLine

foreach ($currentPlatform in $platforms) {
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }

    foreach ($suiteName in @('Designer', 'FormText')) {
        $outputDirectory = Join-Path $projectRoot "Build\Tests-$suiteName-$currentPlatform"
        $dcuDirectory = ($outputDirectory + '-Dcu')
        $generatedDirectory = ($outputDirectory + '-Generated')
        New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $generatedDirectory | Out-Null

        # Private production routines are included verbatim. Only test inputs and interface doubles
        # are stored in the DPRs; no copied implementation, live IDE, registry or config is used.
        if ($suiteName -eq 'Designer') {
            [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.Designer.Constants.inc'),
                $designerConstants, [Text.UTF8Encoding]::new($true))
            [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.Designer.Functions.inc'),
                $designerFunctions, [Text.UTF8Encoding]::new($true))
        } else {
            [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.FormText.State.inc'),
                ('const' + [Environment]::NewLine + $formViewConstants + $formViewState), [Text.UTF8Encoding]::new($true))
            [IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.FormText.Methods.inc'),
                ($formTextMethods -join [Environment]::NewLine), [Text.UTF8Encoding]::new($true))
        }

        $compilerArguments = @(
            '-B'
            '-Q'
            '-$Q+'
            '-$R+'
            "-E$outputDirectory"
            "-N0$dcuDirectory"
            "-I$generatedDirectory"
            "-U$sourceDirectory;$toolsApiDirectory;$libraryDirectory"
            (Join-Path $PSScriptRoot "Test.$suiteName.dpr")
        )
        if ($suiteName -eq 'Designer') {
            # The string-readability fixture implements the actual SDK IOTAComponent interface.
            $compilerArguments = @('-LUrtl;vcl;designide') + $compilerArguments
        }
        & $compiler @compilerArguments
        if ($LASTEXITCODE -ne 0) {
            throw "$suiteName fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
        }
        & (Join-Path $outputDirectory "Test.$suiteName.exe")
        if ($LASTEXITCODE -ne 0) {
            throw "$suiteName fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
    }
}
