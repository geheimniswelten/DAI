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
$sourceDirectory = Join-Path $projectRoot 'Source'
$outputDirectory = Join-Path $projectRoot "Build\Tests-Sessions-$Platform"
$dcuDirectory = ($outputDirectory + '-Dcu')
$compilerName = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
$compiler = Join-Path $BdsRoot "bin\$compilerName"
$libraryDirectory = Join-Path $BdsRoot "lib\$Platform\release"

if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Delphi-Compiler nicht gefunden: $compiler"
}
New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null

# Test only the native session store; no IDE, settings, registry or client configs.
$compilerArguments = @(
    '-B'
    '-Q'
    '-$B+'
    '-$Q+'
    '-$R+'
    "-E$outputDirectory"
    "-N0$dcuDirectory"
    "-U$sourceDirectory;$libraryDirectory"
    (Join-Path $PSScriptRoot 'Test.Sessions.dpr')
)
& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Sitzungstest konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
}
& (Join-Path $outputDirectory 'Test.Sessions.exe')
if ($LASTEXITCODE -ne 0) {
    throw "Sitzungstest fehlgeschlagen (Exitcode $LASTEXITCODE)."
}
