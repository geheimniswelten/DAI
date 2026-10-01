[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS,
    [string]$BuildSourceDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$stubDirectory = Join-Path $PSScriptRoot 'BuildTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
if ([string]::IsNullOrWhiteSpace($BuildSourceDirectory)) {
    $BuildSourceDirectory = $sourceDirectory
}
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\Build\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
    $runtimeDirectory = Join-Path $BdsRoot $(if ($currentPlatform -eq 'Win64') { 'bin64' } else { 'bin' })
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    # Complete production Build unit and official OTA interfaces; only settings, dispatch and process access are synthetic.
    # No running IDE, registry, configuration, application process or package is touched.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;designide'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$BuildSourceDirectory;$sourceDirectory;$toolsApiDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Build.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Build-Test fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $previousProcessPath = $env:PATH
    try {
        $env:PATH = $runtimeDirectory + ';' + $previousProcessPath
        & (Join-Path $outputDirectory 'Test.Build.exe')
        if ($LASTEXITCODE -ne 0) {
            throw "Build-Test fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
    } finally {
        $env:PATH = $previousProcessPath
    }
}
