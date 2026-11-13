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
$sdkVersion = Split-Path -Leaf $BdsRoot
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($architecture in $platforms) {
    $output = Join-Path $projectRoot "Build\Tests-IndentationTabs-$sdkVersion-$architecture"
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $name = if ($architecture -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$name"
    $library = Join-Path $BdsRoot "lib\$architecture\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    # Pure source transformations only; no IDE, settings or user source files are touched.
    & $compiler -B -Q '-$B+' '-$Q+' '-$R+' "-E$output" "-N0$output" "-U$projectRoot\Source;$library" `
        (Join-Path $PSScriptRoot 'Test.IndentationTabs.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Einrueckungstest konnte nicht kompiliert werden: $sdkVersion/$architecture" }
    & (Join-Path $output 'Test.IndentationTabs.exe')
    if ($LASTEXITCODE -ne 0) { throw "Einrueckungstest fehlgeschlagen: $sdkVersion/$architecture" }
}
