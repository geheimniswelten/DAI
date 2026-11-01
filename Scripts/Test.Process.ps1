[CmdletBinding()]
param([ValidateSet('Win32','Win64','Both')][string]$Platform='Both', [string]$BdsRoot=$env:BDS)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($BdsRoot)) { $BdsRoot='C:\Program Files (x86)\Embarcadero\Studio\37.0' }
$projectRoot=Split-Path -Parent $PSScriptRoot
$platforms=if ($Platform -eq 'Both') { @('Win32','Win64') } else { @($Platform) }
foreach ($arch in $platforms) {
 $out=Join-Path $projectRoot "Build\Tests-Process-$arch"
 $dcu=$out+'-Dcu'
 New-Item -ItemType Directory -Force -Path $out,$dcu | Out-Null
 $compiler=if ($arch -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
 $source=Join-Path $projectRoot 'Source'
 $fixture=Join-Path $PSScriptRoot 'ProcessTests'
 $lib=Join-Path $BdsRoot "lib\$arch\release"
 & (Join-Path $BdsRoot "bin\$compiler") '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$out" "-N0$dcu" "-U$fixture;$source;$lib" (Join-Path $PSScriptRoot 'Test.Process.dpr')
 if ($LASTEXITCODE -ne 0) { throw 'Process test compilation failed' }
 & (Join-Path $out 'Test.Process.exe') (Join-Path $BdsRoot 'bin\dcc32.exe') (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe')
 if ($LASTEXITCODE -ne 0) { throw 'Process tests failed' }
}
