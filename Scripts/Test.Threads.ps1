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
$fixtureDirectory = Join-Path $PSScriptRoot 'ThreadTests'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-Threads-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $sdkFixtureDirectory = ($outputDirectory + '-SDKFixtures')
    $sdkDcuDirectory = ($outputDirectory + '-SDKDcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $sdkFixtureDirectory, $sdkDcuDirectory |
        Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtureDirectory 'h5u.DAI.OTA.Helpers.pas') -Destination $sdkFixtureDirectory
    if (Test-Path -LiteralPath (Join-Path $sdkFixtureDirectory 'ToolsAPI.pas')) {
        throw 'Eine ToolsAPI-Testdouble darf nicht im SDK-Probenpfad liegen.'
    }
    # Every production OTA signature is compiled against designide.dcp's real
    # installed ToolsAPI, while only the main-thread marshaller is doubled.
    $sdkArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;designide'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-N0$sdkDcuDirectory"
        "-U$sdkFixtureDirectory;$libraryDirectory"
        (Join-Path $sourceDirectory 'h5u.DAI.OTA.Threads.pas')
    )
    & $compiler @sdkArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Thread-SDK-Probe fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Threads.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Threadtest fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    # In-memory debugger doubles reject mutation and off-main-thread getters.
    # No live process, running IDE, registry or client configuration is touched.
    & (Join-Path $outputDirectory 'Test.Threads.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Threadtest fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
