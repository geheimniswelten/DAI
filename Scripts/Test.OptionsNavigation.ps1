[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) { $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$stubDirectory = Join-Path $PSScriptRoot 'OptionsNavigationTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\OptionsNavigation\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    & $compiler '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" "-U$stubDirectory;$sourceDirectory;$libraryDirectory" (Join-Path $PSScriptRoot 'Test.OptionsNavigation.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Optionsnavigationstest $currentPlatform konnte nicht kompiliert werden." }
    foreach ($scenario in @('', '--empty-shutdown', '--queued-shutdown', '--insight-shutdown')) {
        if ($scenario -eq '') { & (Join-Path $outputDirectory 'Test.OptionsNavigation.exe') }
        else { & (Join-Path $outputDirectory 'Test.OptionsNavigation.exe') $scenario }
        if ($LASTEXITCODE -ne 0) { throw "Optionsnavigationstest $currentPlatform $scenario fehlgeschlagen." }
    }
}
