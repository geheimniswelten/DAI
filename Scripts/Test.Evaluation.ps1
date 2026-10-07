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
$stubDirectory = Join-Path $PSScriptRoot 'EvaluationTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-Evaluation-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    & $compiler '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" "-U$stubDirectory;$sourceDirectory;$libraryDirectory" (Join-Path $PSScriptRoot 'Test.Evaluation.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Evaluatortest $currentPlatform konnte nicht kompiliert werden." }
    & (Join-Path $outputDirectory 'Test.Evaluation.exe')
    if ($LASTEXITCODE -ne 0) { throw "Evaluatortest $currentPlatform fehlgeschlagen." }
}
