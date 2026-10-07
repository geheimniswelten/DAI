[CmdletBinding()]
param([string]$BdsRoot = $env:BDS)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
    $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $projectRoot 'Source'
foreach ($currentPlatform in @('Win32', 'Win64')) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-ReadOnlyPolicy-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $toolsApiDirectory = Join-Path $BdsRoot 'source\ToolsAPI'
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerArguments = @(
        '-B'
        '-Q'
        '-LUrtl;vcl;designide'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$sourceDirectory;$toolsApiDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.ReadOnlyPolicy.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "ReadOnly-Policy-Test fuer $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $fixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) ('DAI-ReadOnlyPolicy-Fixture-' + [guid]::NewGuid().ToString('N'))
    $fixtureTarget = Join-Path $fixtureDirectory 'ReadOnlySource'
    $fixtureLink = Join-Path $fixtureDirectory 'WorkspaceAlias'
    New-Item -ItemType Directory -Path $fixtureTarget | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureTarget 'Existing.pas'), 'fixture original')
    New-Item -ItemType Junction -Path $fixtureLink -Target $fixtureTarget | Out-Null
    try {
        & (Join-Path $outputDirectory 'Test.ReadOnlyPolicy.exe') $fixtureLink $fixtureTarget
        if ($LASTEXITCODE -ne 0) {
            throw "ReadOnly-Policy-Test fuer $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
    } finally {
        $resolvedLink = [IO.Path]::GetFullPath($fixtureLink)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureDirectory)
        $linkItem = Get-Item -LiteralPath $resolvedLink -Force
        if (-not $resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedFixture) -notmatch '^DAI-ReadOnlyPolicy-Fixture-[0-9a-f]{32}$' -or
            -not $resolvedLink.StartsWith($resolvedFixture + '\', [StringComparison]::OrdinalIgnoreCase) -or
            ($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
            $linkItem.Target -ne $fixtureTarget) {
            throw 'Die isolierte Junction stimmt nicht mit dem Testziel ueberein; automatische Entfernung abgebrochen.'
        }
        Remove-Item -LiteralPath $resolvedLink -Force
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
