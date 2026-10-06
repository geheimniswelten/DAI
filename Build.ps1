[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [ValidateSet('Win32', 'Win64', 'Both', 'IDE')]
    [string]$Platform = 'Win32',

    [string]$BdsRoot = $env:BDS,

    [ValidateSet('11', '12', '13')]
    [string]$DelphiVersion,

    [switch]$Register,

    [switch]$SkipMissing
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PackageSnapshot {
    param([string]$Directory)

    $snapshot = @{}
    if (Test-Path -LiteralPath $Directory -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $Directory -File) {
            if ($file.Name -match '^DAI[0-9]+\.bpl$') {
                $snapshot[$file.FullName] = "$($file.LastWriteTimeUtc.Ticks):$($file.Length)"
            }
        }
    }
    return $snapshot
}

function Assert-TargetBinary {
    param([string]$Path, [string]$TargetPlatform, [bool]$IsPackage)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Build-Ausgabe fehlt: $Path"
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                   [System.IO.FileShare]::Read)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw "Kein gültiges Windows-Binary: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = [long]$reader.ReadUInt32()
        if ($peOffset -lt 64 -or $peOffset + 26 -gt $stream.Length) {
            throw "Ungültiger PE-Header: $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Ungültige PE-Signatur: $Path"
        }
        $machine = $reader.ReadUInt16()
        $expectedMachine = if ($TargetPlatform -eq 'Win64') { 0x8664 } else { 0x014C }
        $stream.Position = $peOffset + 22
        $characteristics = $reader.ReadUInt16()
        $magic = $reader.ReadUInt16()
        $expectedMagic = if ($TargetPlatform -eq 'Win64') { 0x020B } else { 0x010B }
        if ($machine -ne $expectedMachine -or $magic -ne $expectedMagic) {
            throw "Build-Ausgabe hat die falsche Architektur für ${TargetPlatform}: $Path"
        }
        if (($IsPackage -and ($characteristics -band 0x2000) -eq 0) -or
            (-not $IsPackage -and ($characteristics -band 0x2000) -ne 0)) {
            throw "Build-Ausgabe hat den falschen DLL-/EXE-Typ: $Path"
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectFile = Join-Path $projectRoot 'DAI.dproj'
. (Join-Path $projectRoot 'Scripts\Build.Registration.ps1')
. (Join-Path $projectRoot 'Scripts\Build.Output.ps1')

if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "DAI.dproj wurde nicht gefunden: $projectFile"
}

$installation = $null
if ($DelphiVersion) {
    # A selected version must never inherit another compiler's BDS environment.
    $requestedRoot = if ($PSBoundParameters.ContainsKey('BdsRoot')) { $BdsRoot } else { '' }
    $installation = Get-DelphiInstallation -DelphiVersion $DelphiVersion -BdsRoot $requestedRoot
    if ($null -eq $installation) {
        $message = "Delphi $DelphiVersion (BDS $(Get-BdsVersion $DelphiVersion)) ist nicht installiert"
        if ($requestedRoot) { $message += " oder passt nicht zum BdsRoot '$requestedRoot'" }
        if ($SkipMissing -and -not $requestedRoot) {
            Write-Host "$message; Build und Registrierung werden übersprungen."
            return
        }
        throw "$message."
    }
    $BdsRoot = $installation.RootDir
}
else {
    if ([string]::IsNullOrWhiteSpace($BdsRoot)) {
        $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
    }
    if ($Register -or $Platform -eq 'IDE') {
        $installation = Get-DelphiInstallation -BdsRoot $BdsRoot
        if ($null -eq $installation) {
            throw "Für BdsRoot '$BdsRoot' wurde keine registrierte Delphi-11/12/13-Installation gefunden. Verwende -DelphiVersion."
        }
    }
}

$rsvars = Join-Path $BdsRoot 'bin\rsvars.bat'
if (-not (Test-Path -LiteralPath $rsvars)) {
    throw "rsvars.bat wurde nicht gefunden: $rsvars"
}

[string[]]$idePlatforms = @(if ($null -ne $installation) { Get-IDEPlatforms -Installation $installation })
[string[]]$platforms = @(if ($Platform -eq 'IDE') { $idePlatforms } elseif ($Platform -eq 'Both') { 'Win32'; 'Win64' } else { $Platform })
if ($platforms.Count -eq 0) { throw "Keine IDE in der Delphi-Installation '$BdsRoot' gefunden." }
if ($Platform -eq 'IDE' -and $idePlatforms -notcontains 'Win64') {
    Write-Host 'Keine 64-Bit-IDE installiert; Win64-Build und Known Packages x64 werden übersprungen.'
}
if ($Register) {
    foreach ($target in $platforms) {
        if ($idePlatforms -notcontains $target) {
            throw "Für $target ist keine passende IDE installiert. Verwende -Platform IDE für die vorhandenen IDE-Architekturen."
        }
    }
}
# Check all tools before starting any build or registration.
foreach ($target in $platforms) {
    $compilerName = if ($target -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "Compiler fehlt: $compiler" }
}
$packagesToRegister = @()

foreach ($currentPlatform in $platforms) {
    Write-Host "Baue DAI: Configuration=$Configuration Platform=$currentPlatform"
    $bridgeOutput = Join-Path $projectRoot "Build\$currentPlatform\$Configuration\Bpl"
    $previousPackages = Get-PackageSnapshot -Directory $bridgeOutput

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

    $buildLines = [System.Collections.Generic.List[string]]::new()
    & $env:ComSpec /d /s /c $command | ForEach-Object {
        $line = $_.ToString()
        $buildLines.Add($line)
        Write-Host $line
    }
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -ne 0) {
        $failedOutput = Get-PackageOutputFailurePath -OutputLines $buildLines.ToArray() `
            -ProjectRoot $projectRoot -OutputDirectory $bridgeOutput
        $renamedPackage = $null
        if ($failedOutput) {
            try {
                $renamedPackage = Move-BlockedPackageOutput -Path $failedOutput -OutputDirectory $bridgeOutput
            }
            catch { Write-Warning "Blockierte BPL konnte nicht umbenannt werden: $($_.Exception.Message)" }
        }
        if ($renamedPackage) {
            # The moved package must not count as a successful fresh build.
            $previousPackages = Get-PackageSnapshot -Directory $bridgeOutput
            Write-Host "Wiederhole den DAI-Build für $currentPlatform einmal."
            & $env:ComSpec /d /s /c $command
            $buildExitCode = $LASTEXITCODE
        }
        if ($buildExitCode -ne 0) {
            $backupMessage = if ($renamedPackage) { " Die bisherige BPL liegt unter '$renamedPackage'." } else { '' }
            throw "Der DAI-Build für $currentPlatform ist mit Exitcode $buildExitCode fehlgeschlagen.$backupMessage"
        }
    }

    # LIBSUFFIX AUTO is resolved by the compiler. Accept only its current output,
    # never an older unsuffixed BPL or an unchanged build from another compiler.
    $currentPackages = Get-PackageSnapshot -Directory $bridgeOutput
    $builtPackages = @($currentPackages.Keys | Where-Object {
        -not $previousPackages.ContainsKey($_) -or $previousPackages[$_] -ne $currentPackages[$_]
    })
    if ($builtPackages.Count -ne 1) {
        throw "Der Build muss genau eine versionierte DAI-BPL neu schreiben; gefunden: $($builtPackages.Count)."
    }
    $packageFile = $builtPackages[0]
    Assert-TargetBinary -Path $packageFile -TargetPlatform $currentPlatform -IsPackage $true

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

    Assert-TargetBinary -Path (Join-Path $bridgeOutput 'DAI.McpBridge.exe') -TargetPlatform $currentPlatform -IsPackage $false
    Write-Host "Package $([System.IO.Path]::GetFileName($packageFile)) und Bridge als $currentPlatform geprüft."
    $packagesToRegister += [pscustomobject]@{ Path = $packageFile; Platform = $currentPlatform }
}

if ($Register) {
    # No registry writes until all requested packages and bridges passed validation.
    foreach ($package in $packagesToRegister) {
        Register-DAIPackage -PackageFile $package.Path -TargetPlatform $package.Platform `
            -BdsVersion $installation.BdsVersion -ProjectRoot $projectRoot
    }
    Write-Host 'DAI wurde für den aktuellen Benutzer registriert. Die jeweilige IDE zum Laden des Packages neu starten.'
}

Write-Host 'DAI wurde erfolgreich gebaut.'
