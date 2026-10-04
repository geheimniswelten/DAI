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
$stubDirectory = Join-Path $PSScriptRoot 'ProjectSummaryTests'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\ProjectSummary\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    # Real summary and encoding units; only IDE state and package/registry capture are synthetic.
    # Never activates a project, loads a package, reads the IDE registry or edits live IDE buffers.
    $compilerArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.ProjectSummary.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Project summary test compilation failed for $currentPlatform ($LASTEXITCODE)."
    }
    & (Join-Path $outputDirectory 'Test.ProjectSummary.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Project summary tests failed for $currentPlatform ($LASTEXITCODE)."
    }
}
