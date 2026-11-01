[CmdletBinding()]
param([ValidateSet('Win32','Win64','Both')][string]$Platform='Both', [string]$BdsRoot=$env:BDS)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($BdsRoot)) { $BdsRoot='C:\Program Files (x86)\Embarcadero\Studio\37.0' }
$projectRoot=Split-Path -Parent $PSScriptRoot
$platforms=if ($Platform -eq 'Both') { @('Win32','Win64') } else { @($Platform) }
foreach ($arch in $platforms) {
 $out=Join-Path $projectRoot "Build\Tests-ProjectOpen-$arch"
 $dcu=$out+'-Dcu'
 New-Item -ItemType Directory -Force -Path $out,$dcu | Out-Null
 $compiler=if ($arch -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
 $source=Join-Path $projectRoot 'Source'
 $fixture=Join-Path $PSScriptRoot 'ProjectOpenTests'
 $lib=Join-Path $BdsRoot "lib\$arch\release"
 & (Join-Path $BdsRoot "bin\$compiler") '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$out" "-N0$dcu" "-U$fixture;$source;$lib" (Join-Path $PSScriptRoot 'Test.ProjectOpen.dpr')
 if ($LASTEXITCODE -ne 0) { throw 'ProjectOpen test compilation failed' }
 & (Join-Path $out 'Test.ProjectOpen.exe')
 if ($LASTEXITCODE -ne 0) { throw 'ProjectOpen tests failed' }
 # Exercise the production controller inside a real, unloadable package.
 $probeOut=$out+'-Package'
 $probeDcu=$probeOut+'-Dcu'
 $hostDcu=$probeOut+'-HostDcu'
 New-Item -ItemType Directory -Force -Path $probeOut,$probeDcu,$hostDcu | Out-Null
 & (Join-Path $BdsRoot "bin\$compiler") '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-LE$probeOut" "-LN$probeOut" "-N0$probeDcu" `
   "-U$fixture;$source;$lib" (Join-Path $fixture 'DAI.ProjectOpen.ShutdownProbe.dpk')
 if ($LASTEXITCODE -ne 0) { throw 'ProjectOpen BPL probe compilation failed' }
 & (Join-Path $BdsRoot "bin\$compiler") '-B' '-Q' '-LUrtl;vcl' '-$B+' '-$Q+' '-$R+' "-E$probeOut" "-N0$hostDcu" `
   "-U$lib" (Join-Path $PSScriptRoot 'Test.ProjectOpenPackage.dpr')
 if ($LASTEXITCODE -ne 0) { throw 'ProjectOpen BPL host compilation failed' }
 $previousPath=$env:PATH
 try {
   $runtime=if ($arch -eq 'Win64') { 'bin64' } else { 'bin' }
   $env:PATH=(Join-Path $BdsRoot $runtime)+';'+$previousPath
   & (Join-Path $probeOut 'Test.ProjectOpenPackage.exe') (Join-Path $probeOut 'DAI.ProjectOpen.ShutdownProbe.bpl')
   if ($LASTEXITCODE -ne 0) { throw 'ProjectOpen BPL lifetime tests failed' }
 } finally { $env:PATH=$previousPath }
}

