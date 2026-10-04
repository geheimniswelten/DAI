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
$stubDirectory = Join-Path $PSScriptRoot 'PackageActionTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\Packages\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    foreach ($fixture in @('PackageFixture.dpk', 'RuntimeFixture.dpk', 'PlainFixture.dpr')) {
        & $compiler '-B' '-Q' "-E$outputDirectory" "-LE$outputDirectory" "-LN$dcuDirectory" "-N0$dcuDirectory" "-U$libraryDirectory" (Join-Path $stubDirectory $fixture)
        if ($LASTEXITCODE -ne 0) {
            throw "Isoliertes Packagefixture $fixture konnte nicht für $currentPlatform kompiliert werden."
        }
    }
    # The production service runs with fake SDK mutation methods. No fixture is installed, executed or initialized.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Packages.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Packageaktionstest für $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.Packages.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Packageaktionstest für $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
    }
}
