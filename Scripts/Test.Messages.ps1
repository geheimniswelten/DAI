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
$fixtureDirectory = Join-Path $PSScriptRoot 'MessagesTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\Messages\$currentPlatform"
    $packageDcuDirectory = Join-Path $outputDirectory 'PackageDcu'
    $hostDcuDirectory = Join-Path $outputDirectory 'HostDcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $runtimeDirectory = Join-Path $BdsRoot $(if ($currentPlatform -eq 'Win64') { 'bin64' } else { 'bin' })
    New-Item -ItemType Directory -Force -Path $outputDirectory, $packageDcuDirectory, $hostDcuDirectory | Out-Null
    # A synthetic producer exports the verified Delphi method signatures through a real BPL.
    # The complete production reader consumes opaque nodes. No installed IDE BPL is changed.
    $packageArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-LE$outputDirectory"
        "-LN$outputDirectory"
        "-N0$packageDcuDirectory"
        "-U$libraryDirectory"
        (Join-Path $fixtureDirectory 'vclide370.dpk')
    )
    & $compiler @packageArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Messages-Test-BPL fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $hostArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;vclide370'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$hostDcuDirectory"
        "-U$outputDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Messages.dpr')
    )
    & $compiler @hostArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Messages-Test fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $previousProcessPath = $env:PATH
    try {
        $env:PATH = $runtimeDirectory + ';' + $previousProcessPath
        & (Join-Path $outputDirectory 'Test.Messages.exe')
        if ($LASTEXITCODE -ne 0) {
            throw "Messages-Test fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
    } finally {
        $env:PATH = $previousProcessPath
    }
}
