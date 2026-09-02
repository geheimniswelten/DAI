[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [ValidateSet('Win32', 'Win64', 'Both')]
    [string] $Platform = 'Both',

    [string] $BdsRoot = $env:BDS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Embarcadero\Studio\37.0'
    if (Test-Path -LiteralPath $candidate) {
        $BdsRoot = $candidate
    }
}

if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    throw 'Delphi 13 wurde nicht gefunden. Übergeben Sie -BdsRoot oder setzen Sie BDS.'
}

$rsvars = Join-Path $BdsRoot 'bin\rsvars.bat'
if (-not (Test-Path -LiteralPath $rsvars)) {
    throw "rsvars.bat wurde nicht gefunden: $rsvars"
}

$project = Join-Path $PSScriptRoot 'CodexMCPIDE.dproj'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
$commandProcessor = $env:ComSpec
if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
    $commandProcessor = Join-Path $env:SystemRoot 'System32\cmd.exe'
}
if (-not (Test-Path -LiteralPath $commandProcessor)) {
    throw "cmd.exe wurde nicht gefunden: $commandProcessor"
}

foreach ($targetPlatform in $platforms) {
    Write-Host "Building CodexMCPIDE ($Configuration|$targetPlatform)..."
    $command = 'call "{0}" && msbuild "{1}" /t:Build /p:Config={2} /p:Platform={3} /m /nologo' -f `
        $rsvars, $project, $Configuration, $targetPlatform

    & $commandProcessor /d /s /c $command
    if ($LASTEXITCODE -ne 0) {
        throw "Build fehlgeschlagen ($Configuration|$targetPlatform), ExitCode $LASTEXITCODE."
    }
}

Write-Host 'Build erfolgreich.'
