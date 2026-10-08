[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [ValidateSet('Win32', 'Win64')]
    [string]$FixturePlatform,
    [string]$BdsRoot = $env:BDS,
    [string]$BridgePath,
    [string]$PythonPath,
    [switch]$CompileFixtureOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
if ($Platform -eq 'Both' -and -not [string]::IsNullOrWhiteSpace($BridgePath)) {
    throw '-BridgePath requires a single -Platform.'
}
if (-not $CompileFixtureOnly -and [string]::IsNullOrWhiteSpace($PythonPath)) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) {
        $PythonPath = $pythonCommand.Source
    }
    else {
        $PythonPath = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    }
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $currentFixturePlatform = if ([string]::IsNullOrWhiteSpace($FixturePlatform)) {
        $currentPlatform
    } else { $FixturePlatform }
    $outputDirectory = Join-Path $projectRoot "Build\Tests-Launcher-$currentFixturePlatform"
    $compilerName = if ($currentFixturePlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentFixturePlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi compiler not found: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    # All compiler outputs are flat. Runtime fixtures live in a fresh temporary
    # directory; the runner checks handles and paths before cleaning up processes.
    $compilerArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+'
        "-E$outputDirectory"
        "-N0$outputDirectory"
        "-U$libraryDirectory"
        (Join-Path $PSScriptRoot 'LauncherTests\bds.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Launcher fixture $currentFixturePlatform failed to compile: $LASTEXITCODE"
    }
    if ($CompileFixtureOnly) { continue }
    $policyIsolated = [string]::IsNullOrWhiteSpace($BridgePath)
    if ([string]::IsNullOrWhiteSpace($BridgePath)) {
        $bridgeOutputDirectory = Join-Path $projectRoot "Build\Tests-LauncherBridge-$currentPlatform"
        $bridgeDcuDirectory = ($bridgeOutputDirectory + '-Dcu')
        $bridgeGeneratedDirectory = ($bridgeOutputDirectory + '-Generated')
        $bridgeCompilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
        $bridgeCompiler = Join-Path $BdsRoot "bin\$bridgeCompilerName"
        $bridgeLibraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
        $sourceDirectory = Join-Path $projectRoot 'Source'
        if (-not (Test-Path -LiteralPath $bridgeCompiler -PathType Leaf)) {
            throw "Delphi compiler not found: $bridgeCompiler"
        }
        New-Item -ItemType Directory -Force -Path $bridgeOutputDirectory, $bridgeDcuDirectory, $bridgeGeneratedDirectory | Out-Null
        # Keep helper/DCU outputs separate from every productive build. The
        # helper platform is independent of the fixture platform for cross-arch QA.
        # Only this generated test main includes a per-process HKCU override.
        # It exercises the productive policy code against isolated GUID keys;
        # the productive bridge contains no test switch or registry redirection.
        $testRegistryUnit = Join-Path $PSScriptRoot 'LauncherTests\DAI.Lifecycle.TestRegistry.pas'
        $bridgeSource = [System.IO.File]::ReadAllText((Join-Path $projectRoot 'DAI.McpBridge.dpr'))
        $bridgeSource = [regex]::Replace($bridgeSource, "(?m)^uses\r?$", {
            "uses`r`n  DAI.Lifecycle.TestRegistry in '" + $testRegistryUnit.Replace("'", "''") + "',"
        })
        $bridgeSource = [regex]::Replace($bridgeSource, "in 'Source\\([^']+)'", {
            param($match)
            "in '" + (Join-Path $sourceDirectory $match.Groups[1].Value).Replace("'", "''") + "'"
        })
        $generatedBridge = Join-Path $bridgeGeneratedDirectory 'DAI.McpBridge.dpr'
        [System.IO.File]::WriteAllText($generatedBridge, $bridgeSource, [System.Text.UTF8Encoding]::new($true))
        $bridgeCompilerArguments = @(
            '-B', '-Q', '-$B+', '-$Q+', '-$R+'
            "-E$bridgeOutputDirectory"
            "-N0$bridgeDcuDirectory"
            "-U$sourceDirectory;$bridgeLibraryDirectory"
            $generatedBridge
        )
        & $bridgeCompiler @bridgeCompilerArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Isolated launcher helper $currentPlatform failed to compile: $LASTEXITCODE"
        }
        $currentBridge = Join-Path $bridgeOutputDirectory 'DAI.McpBridge.exe'
    }
    else {
        # An explicitly supplied executable is never rebuilt or replaced.
        $currentBridge = $BridgePath
    }
    if (-not (Test-Path -LiteralPath $currentBridge -PathType Leaf)) {
        throw "Build the launcher bridge first: $currentBridge"
    }
    if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        throw "Python runtime not found: $PythonPath"
    }
    $runnerArguments = @(
        (Join-Path $PSScriptRoot 'test_launcher.py')
        '--bridge', $currentBridge, '--fixture', (Join-Path $outputDirectory 'bds.exe')
        '--platform', $currentFixturePlatform, '--helper-platform', $currentPlatform
    )
    if ($policyIsolated) { $runnerArguments += '--policy-isolated' }
    & $PythonPath @runnerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Launcher blackbox tests $currentPlatform failed: $LASTEXITCODE"
    }
}
