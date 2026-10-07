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
$stubDirectory = Join-Path $PSScriptRoot 'CodeInsightTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-CodeInsight-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
    $runtimeDirectory = Join-Path $BdsRoot $(if ($currentPlatform -eq 'Win64') { 'bin64' } else { 'bin' })
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    # Real production service + official OTA interfaces; synthetic services/settings/editor.
    # Outputs are standalone tests; no DAI BPL, IDE, registry settings or client configs are replaced.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;designide'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$sourceDirectory;$toolsApiDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.CodeInsight.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "CodeInsight-Test fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $previousProcessPath = $env:PATH
    try {
        $env:PATH = $runtimeDirectory + ';' + $previousProcessPath
        & (Join-Path $outputDirectory 'Test.CodeInsight.exe')
        if ($LASTEXITCODE -ne 0) {
            throw "CodeInsight-Test fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }

        # Load/unload an isolated BPL with the complete production CodeInsight unit.
        # Windows PIN and Delphi FinalizePackage are distinct; late callbacks exercise both.
        $probeOutputDirectory = Join-Path $projectRoot "Build\Tests-CodeInsight-PackageProbe-$currentPlatform"
        $probeDcuDirectory = ($probeOutputDirectory + '-Dcu')
        $hostDcuDirectory = ($probeOutputDirectory + '-HostDcu')
        New-Item -ItemType Directory -Force -Path $probeOutputDirectory, $probeDcuDirectory, $hostDcuDirectory | Out-Null
        $probeArguments = @(
            '-B'
            '-Q'
            '-$Q+'
            '-$R+'
            "-LE$probeOutputDirectory"
            "-LN$probeOutputDirectory"
            "-N0$probeDcuDirectory"
            "-U$stubDirectory;$sourceDirectory;$toolsApiDirectory;$libraryDirectory"
            (Join-Path $stubDirectory 'DAI.CodeInsight.ShutdownProbe.dpk')
        )
        & $compiler @probeArguments
        if ($LASTEXITCODE -ne 0) {
            throw "CodeInsight-Probe-BPL fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
        }
        $hostArguments = @(
            '-B'
            '-Q'
            '-LUrtl;vcl;designide'
            '-$Q+'
            '-$R+'
            "-E$probeOutputDirectory"
            "-N0$hostDcuDirectory"
            "-U$stubDirectory;$toolsApiDirectory;$libraryDirectory"
            (Join-Path $PSScriptRoot 'Test.CodeInsightPackage.dpr')
        )
        & $compiler @hostArguments
        if ($LASTEXITCODE -ne 0) {
            throw "CodeInsight-Probe-Host fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
        }
        & (Join-Path $probeOutputDirectory 'Test.CodeInsightPackage.exe') (Join-Path $probeOutputDirectory 'DAI.CodeInsight.ShutdownProbe.bpl')
        if ($LASTEXITCODE -ne 0) {
            throw "CodeInsight-Package-Regression fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
    } finally {
        $env:PATH = $previousProcessPath
    }
}
