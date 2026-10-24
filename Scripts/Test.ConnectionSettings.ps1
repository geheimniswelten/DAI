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
$stubDirectory = Join-Path $PSScriptRoot 'ConnectionSettingsTests'
$launcherTestDirectory = Join-Path $PSScriptRoot 'LauncherTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
$executables = @{}
$scenarios = @('fresh', 'legacy', 'separate', 'preview', 'partial-port', 'partial-token', 'malformed-token',
    'invalid-save', 'stale-save', 'stale-preview', 'read-directories', 'refresh', 'concurrent-scope', 'manual-registration')

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-ConnectionSettings-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi compiler not found: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$launcherTestDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.ConnectionSettings.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Connection Settings test $currentPlatform failed to compile: $LASTEXITCODE"
    }
    $executables[$currentPlatform] = Join-Path $outputDirectory 'Test.ConnectionSettings.exe'
}

$testPrefix = 'Software\DelphiAI\DAI-Launcher-Tests\'
$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)

function Invoke-IsolatedConnectionCheck {
    param([string[]]$TestExecutables, [string[]]$TestScenarios)

    if ($TestExecutables.Count -ne $TestScenarios.Count) {
        throw 'Each test executable must have exactly one scenario.'
    }
    # Only the test process redirects HKCU. Product units have no test overrides.
    # A fresh key per scenario also exercises one-time migration from scratch.
    $testGuid = [Guid]::NewGuid().ToString('B')
    $testRoot = $testPrefix + $testGuid
    if (-not $testRoot.StartsWith($testPrefix, [StringComparison]::Ordinal) -or
        $testRoot.Substring($testPrefix.Length) -ne $testGuid) {
        throw 'Invalid isolated registry test root.'
    }
    $testKey = $registry.CreateSubKey($testRoot)
    $testKey.Dispose()
    $previousTestRoot = [Environment]::GetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT', $testRoot, 'Process')
        for ($testIndex = 0; $testIndex -lt $TestExecutables.Count; $testIndex++) {
            & $TestExecutables[$testIndex] $TestScenarios[$testIndex]
            if ($LASTEXITCODE -ne 0) {
                throw "Connection Settings scenario '$($TestScenarios[$testIndex])' failed: $LASTEXITCODE"
            }
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT', $previousTestRoot, 'Process')
        # The validated absolute registry target is exactly one GUID child in the
        # dedicated test prefix, never the real DAI connection or IDE registry.
        $registry.DeleteSubKeyTree($testRoot, $false)
    }
}

try {
    foreach ($currentPlatform in $platforms) {
        foreach ($scenario in $scenarios) {
            Invoke-IsolatedConnectionCheck -TestExecutables @($executables[$currentPlatform]) -TestScenarios @($scenario)
        }
    }
    if ($Platform -eq 'Both') {
        # Each direction gets its own isolated HKCU, retained across the two
        # processes so the second architecture must read what the first wrote.
        Invoke-IsolatedConnectionCheck -TestExecutables @($executables['Win32'], $executables['Win64']) `
            -TestScenarios @('cross-write', 'cross-read')
        Invoke-IsolatedConnectionCheck -TestExecutables @($executables['Win64'], $executables['Win32']) `
            -TestScenarios @('cross-write', 'cross-read')
    }
}
finally {
    $registry.Dispose()
}
