[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64')]
    [string]$Platform = 'Win32',
    [string]$BdsRoot = $env:BDS,
    [Alias('Dcc32')]
    [string]$Compiler
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) { $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0' }
if ([string]::IsNullOrWhiteSpace($Compiler)) {
    $compilerName = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $Compiler = Join-Path $BdsRoot "bin\$compilerName"
}
$testProjectRoot = Split-Path -Parent $PSScriptRoot
$testRunRoot = Join-Path $testProjectRoot ('work\client-registration-tests-' + [Guid]::NewGuid().ToString('N'))
$testBin = Join-Path $testRunRoot 'bin'
$testFixtures = Join-Path $testRunRoot 'fixtures'
New-Item -ItemType Directory -Path $testBin, $testFixtures -Force | Out-Null
$testUnitPath = (Join-Path $PSScriptRoot 'RegistrationTests') + ';' + (Join-Path $testProjectRoot 'Source') +
    ';' + (Join-Path $BdsRoot "lib\$Platform\release")
$testCompilerArgs = @('-B', '-Q', ('-E' + $testBin), ('-N0' + $testBin), ('-U' + $testUnitPath),
  (Join-Path $PSScriptRoot 'Test-ClientRegistration.dpr'))
& $Compiler @testCompilerArgs
if ($LASTEXITCODE -ne 0) { throw 'Isolated Delphi registration test compilation failed.' }
& (Join-Path $testBin 'Test-ClientRegistration.exe') $testFixtures
if ($LASTEXITCODE -ne 0) { throw 'Isolated Delphi registration tests failed.' }
Write-Host ('Test files and private backups: ' + $testRunRoot)
