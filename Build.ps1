[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Win32',

    [string]$BdsRoot = $env:BDS
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectFile = Join-Path $projectRoot 'DAI.dproj'

if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "DAI.dproj wurde nicht gefunden: $projectFile"
}

if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}

$rsvars = Join-Path $BdsRoot 'bin\rsvars.bat'
if (-not (Test-Path -LiteralPath $rsvars)) {
    throw "rsvars.bat wurde nicht gefunden: $rsvars"
}

$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    Write-Host "Baue DAI: Configuration=$Configuration Platform=$currentPlatform"

    $command = @(
        'call'
        "`"$rsvars`""
        '&&'
        'msbuild'
        "`"$projectFile`""
        '/t:Build'
        "/p:Config=$Configuration"
        "/p:Platform=$currentPlatform"
        '/nologo'
        '/verbosity:minimal'
    ) -join ' '

    & $env:ComSpec /d /s /c $command
    if ($LASTEXITCODE -ne 0) {
        throw "Der DAI-Build für $currentPlatform ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
    }

    $bridgeOutput = Join-Path $projectRoot "Build\$currentPlatform\$Configuration\Bpl"
    $bridgeDcu = Join-Path $projectRoot "Build\$currentPlatform\$Configuration\BridgeDcu"
    New-Item -ItemType Directory -Path $bridgeOutput, $bridgeDcu -Force | Out-Null
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $bridgeCommand = @(
        'call'
        "`"$rsvars`""
        '&&'
        "`"$(Join-Path $BdsRoot "bin\$compilerName")`""
        '-B'
        "-E`"$bridgeOutput`""
        "-N0`"$bridgeDcu`""
        "`"$(Join-Path $projectRoot 'DAI.McpBridge.dpr')`""
    ) -join ' '
    & $env:ComSpec /d /s /c $bridgeCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Der Delphi-MCP-Bridge-Build für $currentPlatform ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
    }
}

Write-Host 'DAI wurde erfolgreich gebaut.'
