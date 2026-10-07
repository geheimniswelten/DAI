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
$stubDirectory = Join-Path $PSScriptRoot 'DirectorySearchTests'
$sourceDirectory = Join-Path $projectRoot 'Source'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }

foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-DirectorySearch-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Delphi-Compiler nicht gefunden: $compiler"
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null

    # Exercise the real directory file service and encoding policy with isolated editor/designer doubles.
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-U$stubDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.DirectorySearch.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Dateisuchtest für $currentPlatform konnte nicht kompiliert werden (Exitcode $LASTEXITCODE)."
    }
    $fixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) ('DAI-DirectorySearch-JunctionFixture-' + [guid]::NewGuid().ToString('N'))
    $fixtureRoot = Join-Path $fixtureDirectory 'Workspace'
    $fixtureTarget = Join-Path $fixtureDirectory 'Outside'
    $fixtureLink = Join-Path $fixtureRoot 'Alias'
    New-Item -ItemType Directory -Path $fixtureRoot, $fixtureTarget | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureTarget 'Outside.pas'), 'MARK_OUTSIDE')
    New-Item -ItemType Junction -Path $fixtureLink -Target $fixtureTarget | Out-Null
    try {
        & (Join-Path $outputDirectory 'Test.DirectorySearch.exe') $fixtureRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Dateisuchtest für $currentPlatform fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
    } finally {
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureDirectory)
        $resolvedLink = [IO.Path]::GetFullPath($fixtureLink)
        $linkItem = Get-Item -LiteralPath $resolvedLink -Force
        if (-not $resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedFixture) -notmatch '^DAI-DirectorySearch-JunctionFixture-[0-9a-f]{32}$' -or
            -not $resolvedLink.StartsWith($resolvedFixture + '\', [StringComparison]::OrdinalIgnoreCase) -or
            ($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
            $linkItem.Target -ne $fixtureTarget) {
            throw 'Das isolierte Junction-Testziel stimmt nicht überein; automatische Entfernung abgebrochen.'
        }
        Remove-Item -LiteralPath $resolvedLink -Force
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
