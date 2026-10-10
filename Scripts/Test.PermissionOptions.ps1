[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64')]
    [string]$Platform = 'Win32',
    [string]$BdsRoot = $env:BDS
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$stubDirectory = Join-Path $PSScriptRoot 'PermissionOptionsTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$outputDirectory = Join-Path $projectRoot "Build\Tests-PermissionOptions-$Platform"
$dcuDirectory = ($outputDirectory + '-Dcu')
$compilerName = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
$compiler = Join-Path $BdsRoot "bin\$compilerName"
$libraryDirectory = Join-Path $BdsRoot "lib\$Platform\release"
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Delphi-Compiler nicht gefunden: $compiler"
}
New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null

# Actual store and manager, isolated by a synthetic settings root and test-only dialog/log stubs.
# The executable uses a unique temporary directory and synthetic HKCU key; no IDE or DAI policy is accessed.
$compilerArguments = @(
    '-B'
    '-Q'
    '-$B+'
    '-$Q+'
    '-$R+'
    "-E$outputDirectory"
    "-N0$dcuDirectory"
    "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
    (Join-Path $PSScriptRoot 'Test.PermissionOptions.dpr')
)
& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Berechtigungsoptionen-Test konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
}
& (Join-Path $outputDirectory 'Test.PermissionOptions.exe')
if ($LASTEXITCODE -ne 0) {
    throw "Berechtigungsoptionen-Test fehlgeschlagen (Exitcode $LASTEXITCODE)."
}
