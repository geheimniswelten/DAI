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
$serviceFixture = Join-Path $PSScriptRoot 'ToolbarTests\h5u.DAI.Symbols.Service.pas'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-SymbolDialog-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $fixtureDirectory = ($outputDirectory + '-Fixtures')
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $fixtureDirectory | Out-Null
    Copy-Item -LiteralPath $serviceFixture -Destination $fixtureDirectory
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.SymbolDialog.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Symbolindex-Dialogtest fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    # The real modeless VCL manager uses an in-memory service double only.
    # No live IDE, model endpoint, SQLite database or registry is touched.
    & (Join-Path $outputDirectory 'Test.SymbolDialog.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Symbolindex-Dialogtest fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
