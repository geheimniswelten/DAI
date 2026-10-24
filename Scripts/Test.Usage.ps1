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
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
$executables = @{}

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-Usage-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi compiler not found: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerArguments = @(
        '-B', '-Q', '-$B+', '-$Q+', '-$R+', '-DDAI_USAGE_TESTS'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Usage.dpr')
    )
    Push-Location -LiteralPath $PSScriptRoot
    try {
        & $compiler @compilerArguments
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Usage test $currentPlatform failed to compile: $LASTEXITCODE"
    }
    $executables[$currentPlatform] = Join-Path $outputDirectory 'Test.Usage.exe'
}

$testPrefix = 'Software\DelphiAI\DAI-Launcher-Tests\'
$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)

function Invoke-IsolatedUsageCheck {
    param([scriptblock]$Action)

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
        # The test fixture redirects HKCU only inside each test process.
        [Environment]::SetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT', $testRoot, 'Process')
        & $Action
    }
    finally {
        [Environment]::SetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT', $previousTestRoot, 'Process')
        # This is exactly one validated GUID child under the dedicated tests root.
        $registry.DeleteSubKeyTree($testRoot, $false)
    }
}

try {
    foreach ($currentPlatform in $platforms) {
        Invoke-IsolatedUsageCheck {
            & $executables[$currentPlatform]
            if ($LASTEXITCODE -ne 0) {
                throw "Usage tests failed for ${currentPlatform}: $LASTEXITCODE"
            }
        }
    }
    Invoke-IsolatedUsageCheck {
        $processes = @()
        foreach ($currentPlatform in $platforms) {
            for ($instance = 0; $instance -lt 2; $instance++) {
                $processes += Start-Process -FilePath $executables[$currentPlatform] -ArgumentList 'increment' `
                    -WindowStyle Hidden -PassThru
            }
        }
        foreach ($process in $processes) {
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw "Concurrent usage process failed: $($process.ExitCode)"
            }
            $process.Dispose()
        }
        $expectedCount = 2 * $platforms.Count * 300
        foreach ($currentPlatform in $platforms) {
            & $executables[$currentPlatform] check $expectedCount
            if ($LASTEXITCODE -ne 0) {
                throw "Shared registry view check failed for ${currentPlatform}: $LASTEXITCODE"
            }
        }
    }
}
finally {
    $registry.Dispose()
}
