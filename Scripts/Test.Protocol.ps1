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
$stubDirectory = Join-Path $PSScriptRoot 'ProtocolTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$outputDirectory = Join-Path $projectRoot "Build\Tests\Protocol\$Platform"
$dcuDirectory = Join-Path $outputDirectory 'Dcu'
$compilerName = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
$compiler = Join-Path $BdsRoot "bin\$compilerName"
$libraryDirectory = Join-Path $BdsRoot "lib\$Platform\release"

if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Delphi-Compiler nicht gefunden: $compiler"
}
New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null

# Compile the real HTTP server and protocol with isolated IDE/settings/tool stubs.
# The test never reads real client configs, registry settings, or the running IDE.
$compilerArguments = @(
    '-B'
    "-E$outputDirectory"
    "-N0$dcuDirectory"
    "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
    (Join-Path $PSScriptRoot 'Test.Protocol.dpr')
)
& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "MCP-Protokoll-Test konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
}
& (Join-Path $outputDirectory 'Test.Protocol.exe')
if ($LASTEXITCODE -ne 0) {
    throw "MCP-Protokoll-Test fehlgeschlagen (Exitcode $LASTEXITCODE)."
}
