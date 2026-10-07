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
$stubDirectory = Join-Path $PSScriptRoot 'DesignerTests'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    $outputDirectory = Join-Path $projectRoot "Build\Tests-DesignerOperations-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    # Compile the complete production Designer unit against real SDK interfaces and local doubles.
    & $compiler '-LUrtl;vcl;designide' '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" `
        "-U$stubDirectory;$sourceDirectory;$toolsApiDirectory;$libraryDirectory" `
        (Join-Path $PSScriptRoot 'Test.DesignerOperations.dpr')
    if ($LASTEXITCODE -ne 0) {
        throw "DesignerOperations fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.DesignerOperations.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "DesignerOperations fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
