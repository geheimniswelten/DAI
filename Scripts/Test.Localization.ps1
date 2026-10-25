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
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-Localization-$currentPlatform"
    $dcuDirectory = $outputDirectory + '-Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi compiler not found: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Localization.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Localization test $currentPlatform failed to compile: $LASTEXITCODE"
    }
    # The executable only tests pure resource inputs and its own language override.
    # It does not touch the running IDE, registry, configuration or language settings.
    & (Join-Path $outputDirectory 'Test.Localization.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Localization tests failed for ${currentPlatform}: $LASTEXITCODE"
    }
    # Each child runs as bds.exe and recreates pending native RTL resolution.
    # Copies of this test-owned PE are inert resource-only satellite fixtures.
    $lazyDirectory = Join-Path $outputDirectory ('IDE-Lazy-ä-日本語-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $lazyDirectory | Out-Null
    $testExecutable = Join-Path $outputDirectory 'Test.Localization.exe'
    $ideExecutable = Join-Path $lazyDirectory 'bds.exe'
    Copy-Item -LiteralPath $testExecutable -Destination $ideExecutable
    foreach ($languageCode in @('de', 'fr', 'ja')) {
        Copy-Item -LiteralPath $testExecutable -Destination (Join-Path $lazyDirectory "bds.$languageCode")
    }
    foreach ($languageCode in @('en', 'de', 'fr', 'ja', 'missing')) {
        Write-Output "$currentPlatform lazy resource case: $languageCode"
        & $ideExecutable lazy $languageCode
        if ($LASTEXITCODE -ne 0) {
            throw "Lazy IDE localization test $currentPlatform/$languageCode failed: $LASTEXITCODE"
        }
    }
}
