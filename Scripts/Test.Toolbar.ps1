[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS,
    [ValidateSet('All', 'LegacyDrag', 'Stream', 'LayoutGrow', 'Popup')]
    [string]$Focus = 'All'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $projectRoot 'Source'
$fixtureDirectory = Join-Path $PSScriptRoot 'ToolbarTests'
$sdkSource = Join-Path $BdsRoot 'source\ToolsAPI\ToolsAPI.pas'
$sdkText = [IO.File]::ReadAllText($sdkSource)
if ($sdkText -notmatch "sDebugToolBar\s*=\s*'DebugToolBar'\s*;") {
    throw 'Der Toolbar-Bezeichner des isolierten Tests stimmt nicht mit dem installierten ToolsAPI-SDK ueberein.'
}
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\Toolbar\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    # Compile the production unit against designide.dcp's real ToolsAPI as well.
    # Only runtime dependencies are doubled here; no ToolsAPI double is copied.
    $sdkFixtureDirectory = Join-Path $outputDirectory 'SDKFixtures'
    $sdkDcuDirectory = Join-Path $outputDirectory 'SDKDcu'
    New-Item -ItemType Directory -Force -Path $sdkFixtureDirectory, $sdkDcuDirectory | Out-Null
    Get-ChildItem -LiteralPath $fixtureDirectory -File -Filter 'h5u.*.pas' |
        Copy-Item -Destination $sdkFixtureDirectory
    if (Test-Path -LiteralPath (Join-Path $sdkFixtureDirectory 'ToolsAPI.pas')) {
        throw 'Eine ToolsAPI-Testdouble darf nicht im SDK-Probenpfad liegen.'
    }
    $sdkArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;designide'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-N0$sdkDcuDirectory"
        "-U$sdkFixtureDirectory;$libraryDirectory"
        (Join-Path $sourceDirectory 'h5u.DAI.IDE.Toolbar.pas')
    )
    & $compiler @sdkArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Toolbar-SDK-Probe fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $packageArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-LE$outputDirectory"
        "-LN$outputDirectory"
        "-N0$dcuDirectory"
        "-U$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $fixtureDirectory 'DAI.Toolbar.TestPackage.dpk')
    )
    & $compiler @packageArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Toolbar-Probe-BPL fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $compilerArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;vclimg'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.Toolbar.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Toolbar-Test fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    # Only this process's disposable VCL toolbar and in-memory service doubles
    # are changed. No running IDE, client configuration or registry is touched.
    $runtimeDirectory = if ($currentPlatform -eq 'Win64') { Join-Path $BdsRoot 'bin64' } else { Join-Path $BdsRoot 'bin' }
    $previousProcessPath = $env:PATH
    try {
        $env:PATH = $runtimeDirectory + ';' + $previousProcessPath
        $testInfo = [Diagnostics.ProcessStartInfo]::new()
        $testInfo.FileName = Join-Path $outputDirectory 'Test.Toolbar.exe'
        $testInfo.ArgumentList.Add((Join-Path $outputDirectory 'DAI.Toolbar.TestPackage.bpl'))
        $testInfo.ArgumentList.Add((Join-Path $outputDirectory 'dai-status-glyphs.png'))
        $testInfo.ArgumentList.Add($Focus)
        $testInfo.UseShellExecute = $false
        $testInfo.CreateNoWindow = $true
        $testInfo.RedirectStandardOutput = $true
        $testInfo.RedirectStandardError = $true
        $testProcess = [Diagnostics.Process]::new()
        $testProcess.StartInfo = $testInfo
        try {
            [void]$testProcess.Start()
            $testOutputTask = $testProcess.StandardOutput.ReadToEndAsync()
            $testErrorTask = $testProcess.StandardError.ReadToEndAsync()
            # All includes hundreds of real VCL rendering/streaming cases;
            # focused regressions retain the tighter per-process bound.
            $timeoutSeconds = if ($Focus -eq 'All') { 300 } else { 120 }
            $completed = $testProcess.WaitForExit($timeoutSeconds * 1000)
            if (-not $completed) {
                $testProcess.Kill()
                $testProcess.WaitForExit()
            }
            $testOutput = $testOutputTask.GetAwaiter().GetResult()
            $testError = $testErrorTask.GetAwaiter().GetResult()
            Write-Output "$currentPlatform $($testOutput.TrimEnd())"
            if (-not $completed) {
                if (-not [string]::IsNullOrWhiteSpace($testError)) {
                    Write-Output $testError.TrimEnd()
                }
                throw "Toolbar-Test fuer $currentPlatform hat sein isoliertes $timeoutSeconds-Sekunden-Limit ueberschritten."
            }
            if ($testProcess.ExitCode -ne 0 -or -not $testOutput.Contains('checks passed.')) {
                throw "Toolbar-Test fuer $currentPlatform fehlgeschlagen (Exitcode $($testProcess.ExitCode)). $testError"
            }
        }
        finally {
            $testProcess.Dispose()
        }
    }
    finally {
        $env:PATH = $previousProcessPath
    }
}
