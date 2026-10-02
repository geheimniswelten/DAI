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
$stubDirectory = Join-Path $PSScriptRoot 'StackTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\Stack\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $sdkDirectory = Join-Path $outputDirectory 'SDK'
    $sdkDcuDirectory = Join-Path $sdkDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory, $sdkDirectory, $sdkDcuDirectory | Out-Null

    # Real production unit, small deterministic process/thread doubles, actual worker/main-thread marshalling.
    # No IDE, debugging target, registry or config is accessed.
    $compilerArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Stack.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "Stack-Test für $currentPlatform konnte nicht kompiliert werden: $LASTEXITCODE" }
    & (Join-Path $outputDirectory 'Test.Stack.exe')
    if ($LASTEXITCODE -ne 0) { throw "Stack-Test für $currentPlatform fehlgeschlagen: $LASTEXITCODE" }

    # Independent output/DCU directories ensure the mock ToolsAPI cannot contaminate this SDK compilation.
    $sdkArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+', '-LUrtl;vcl;designide'
        "-E$sdkDirectory"
        "-N0$sdkDcuDirectory"
        "-U$sourceDirectory;$toolsApiDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Stack.SDK.dpr')
    )
    & $compiler @sdkArguments
    if ($LASTEXITCODE -ne 0) { throw "Echte Stack-SDK-Kompilierung für $currentPlatform fehlgeschlagen: $LASTEXITCODE" }
    Write-Output "PASS: Stack production unit compiles against the real ToolsAPI ($currentPlatform)."
}
