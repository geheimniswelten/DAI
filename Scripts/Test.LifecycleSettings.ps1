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
$stubDirectory = Join-Path $PSScriptRoot 'LifecycleSettingsTests'
$launcherTestDirectory = Join-Path $PSScriptRoot 'LauncherTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
$testPrefix = 'Software\DelphiAI\DAI-Launcher-Tests\'
$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
try {
    foreach ($currentPlatform in $platforms) {
        $outputDirectory = Join-Path $projectRoot "Build\Tests-LifecycleSettings-$currentPlatform"
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
            (Join-Path $PSScriptRoot 'Test.LifecycleSettings.dpr')
        )
        & $compiler @compilerArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Lifecycle Settings test $currentPlatform failed to compile: $LASTEXITCODE"
        }

        # Only the test process redirects HKCU to a fresh GUID child key. The actual
        # Settings and Policy units remain unchanged and have no test override API.
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
            & (Join-Path $outputDirectory 'Test.LifecycleSettings.exe')
            if ($LASTEXITCODE -ne 0) {
                throw "Lifecycle Settings test $currentPlatform failed: $LASTEXITCODE"
            }
        }
        finally {
            [Environment]::SetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT', $previousTestRoot, 'Process')
            # The complete deletion target is the validated GUID child within the
            # dedicated test prefix, never the actual DAI or BDS registry root.
            $registry.DeleteSubKeyTree($testRoot, $false)
        }
    }
}
finally {
    $registry.Dispose()
}
