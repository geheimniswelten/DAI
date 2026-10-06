[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# All installation files and registry keys below are fixtures. This test never
# writes to the real Delphi registry and does not invoke a Delphi compiler.
. (Join-Path $PSScriptRoot 'Build.Registration.ps1')

class BuildRegistrationTestKey {
    [string] $SubKey
    [hashtable] $Values
    [System.Collections.Generic.List[object]] $Changes
    [bool] $Disposed

    BuildRegistrationTestKey([string] $subKey, [hashtable] $values,
                             [System.Collections.Generic.List[object]] $changes) {
        $this.SubKey = $subKey
        $this.Values = $values
        $this.Changes = $changes
    }

    [string[]] GetValueNames() {
        return [string[]] @($this.Values.Keys)
    }

    [object] GetValue([string] $name) {
        return $this.Values[$name]
    }

    [object] GetValue([string] $name, [object] $defaultValue) {
        if ($this.Values.ContainsKey($name)) { return $this.Values[$name] }
        return $defaultValue
    }

    [object] GetValue([string] $name, [object] $defaultValue,
                      [Microsoft.Win32.RegistryValueOptions] $options) {
        if ($this.Values.ContainsKey($name)) { return $this.Values[$name] }
        return $defaultValue
    }

    [void] SetValue([string] $name, [object] $value,
                    [Microsoft.Win32.RegistryValueKind] $kind) {
        $this.Values[$name] = $value
        $this.Changes.Add([pscustomobject] @{ Operation = 'Set'; SubKey = $this.SubKey;
                Name = $name; Value = $value; Kind = $kind })
    }

    [void] DeleteValue([string] $name) {
        $this.DeleteValue($name, $true)
    }

    [void] DeleteValue([string] $name, [bool] $throwOnMissingValue) {
        if (-not $this.Values.ContainsKey($name)) {
            if ($throwOnMissingValue) { throw "Fixture value not found: $name" }
            return
        }
        $this.Values.Remove($name)
        $this.Changes.Add([pscustomobject] @{ Operation = 'Delete'; SubKey = $this.SubKey;
                Name = $name })
    }

    [void] Dispose() { $this.Disposed = $true }
    [void] Close() { $this.Disposed = $true }
}

$script:CheckCount = 0
function Assert-Test {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Test failed: $Message" }
    $script:CheckCount++
}

function New-TestBinary {
    param([string] $Path, [string] $Platform = 'Win32', [switch] $Package)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $bytes = New-Object byte[] 512
    [BitConverter]::GetBytes([uint16] 0x5A4D).CopyTo($bytes, 0)
    [BitConverter]::GetBytes([uint32] 128).CopyTo($bytes, 60)
    [BitConverter]::GetBytes([uint32] 0x00004550).CopyTo($bytes, 128)
    $machine = if ($Platform -eq 'Win64') { 0x8664 } else { 0x014C }
    [BitConverter]::GetBytes([uint16] $machine).CopyTo($bytes, 132)
    $characteristics = if ($Package) { 0x2000 } else { 0 }
    [BitConverter]::GetBytes([uint16] $characteristics).CopyTo($bytes, 150)
    $magic = if ($Platform -eq 'Win64') { 0x020B } else { 0x010B }
    [BitConverter]::GetBytes([uint16] $magic).CopyTo($bytes, 152)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function New-TestInstallation {
    param([string] $Name, [switch] $Win64)
    $root = Join-Path $script:FixtureRoot $Name
    $app = Join-Path $root 'bin\bds.exe'
    $appX64 = Join-Path $root 'bin64\bds.exe'
    New-TestBinary -Path $app
    New-TestBinary -Path (Join-Path $root 'bin\dcc32.exe')
    New-TestBinary -Path (Join-Path $root 'bin\dcc64.exe') -Platform Win64
    [System.IO.File]::WriteAllText((Join-Path $root 'bin\rsvars.bat'), '@exit /b 0')
    if ($Win64) { New-TestBinary -Path $appX64 -Platform Win64 }
    return [pscustomobject] @{ RootDir = $root; App = $app; AppX64 = $appX64 }
}

function Invoke-BuildRegistrationFixtureCompiler {
    param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Arguments)
    $state = $global:DAIBuildRegistrationFixture
    $command = [string] $Arguments[-1]
    $state.Commands.Add($command)
    $global:LASTEXITCODE = 0
    if ($command -match '\bmsbuild\b') {
        if ($command -notmatch '/p:Platform=(Win32|Win64)') { throw 'Fixture package platform missing.' }
        $platform = $Matches[1]
        if ($state.Mode -eq 'package-failure') { $global:LASTEXITCODE = 41; return }
        if ($state.Mode -eq 'stale-package') { return }
        $binaryPlatform = if ($state.Mode -eq 'wrong-package-architecture') { 'Win64' } else { $platform }
        New-TestBinary -Path (Join-Path $state.ProjectRoot "Build\$platform\Release\Bpl\DAI$($state.PackageSuffix).bpl") -Platform $binaryPlatform -Package
    }
    else {
        if ($command -notmatch '-E"([^"]+)"') { throw 'Fixture bridge output missing.' }
        $output = $Matches[1]
        $platform = if ($output -match '\\Win64\\') { 'Win64' } else { 'Win32' }
        if ($state.Mode -eq 'bridge-failure' -or
            ($state.Mode -eq 'second-bridge-failure' -and $platform -eq 'Win64')) {
            $global:LASTEXITCODE = 42
            return
        }
        $binaryPlatform = if ($state.Mode -eq 'wrong-bridge-architecture') { 'Win64' } else { $platform }
        New-TestBinary -Path (Join-Path $output 'DAI.McpBridge.exe') -Platform $binaryPlatform
    }
}

function Test-BuildPipeline {
    param([string] $Mode, [string] $Version = '13', [string] $Platform = 'IDE',
          [bool] $Register = $true, [bool] $ExpectFailure = $false,
          [int] $ExpectedRegistrations = 0, [int] $ExpectedCommands = 0,
          [switch] $SkipMissing, [string] $BdsRoot = '')

    $fixtureProject = Join-Path $script:FixtureRoot ('Pipeline-' + $Mode)
    [System.IO.Directory]::CreateDirectory((Join-Path $fixtureProject 'Scripts')) | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Build.ps1') -Destination (Join-Path $fixtureProject 'Build.ps1')
    [System.IO.File]::WriteAllText((Join-Path $fixtureProject 'DAI.dproj'), '<Project />')
    $helperPath = (Join-Path $PSScriptRoot 'Build.Registration.ps1').Replace("'", "''")
    $mockHelpers = @'
. '__HELPER_PATH__'
function Get-BdsRegistryValues {
    param([string] $BdsVersion)
    if ($global:DAIBuildRegistrationFixture.RegistryRows.ContainsKey($BdsVersion)) {
        return $global:DAIBuildRegistrationFixture.RegistryRows[$BdsVersion]
    }
}
function Open-BdsUserRegistryKey { throw 'Real registry access is forbidden in this fixture.' }
function Register-DAIPackage {
    param([string] $PackageFile, [string] $TargetPlatform, [string] $BdsVersion, [string] $ProjectRoot)
    $global:DAIBuildRegistrationFixture.Registrations.Add([pscustomobject] @{
        Path = $PackageFile; Platform = $TargetPlatform; BdsVersion = $BdsVersion })
}
'@
    [System.IO.File]::WriteAllText((Join-Path $fixtureProject 'Scripts\Build.Registration.ps1'),
                                  $mockHelpers.Replace('__HELPER_PATH__', $helperPath))
    $suffix = if ($Version -eq '11') { '280' } elseif ($Version -eq '12') { '290' } else { '370' }
    $global:DAIBuildRegistrationFixture = [pscustomobject] @{
        ProjectRoot = $fixtureProject; Mode = $Mode; PackageSuffix = $suffix;
        RegistryRows = $script:RegistryRows;
        Commands = [System.Collections.Generic.List[string]]::new();
        Registrations = [System.Collections.Generic.List[object]]::new()
    }
    if ($Mode -eq 'stale-package') {
        New-TestBinary -Path (Join-Path $fixtureProject "Build\Win32\Release\Bpl\DAI$suffix.bpl") -Package
    }
    $arguments = @{ DelphiVersion = $Version; Platform = $Platform;
        Register = $Register; SkipMissing = $SkipMissing.IsPresent }
    if ($BdsRoot) { $arguments.BdsRoot = $BdsRoot }
    $failed = $false
    try { & (Join-Path $fixtureProject 'Build.ps1') @arguments | Out-Null }
    catch { $failed = $true }
    Assert-Test ($failed -eq $ExpectFailure) "Pipeline '$Mode' has the expected success/failure status."
    Assert-Test ($global:DAIBuildRegistrationFixture.Commands.Count -eq $ExpectedCommands) "Pipeline '$Mode' invokes only the expected build commands."
    Assert-Test ($global:DAIBuildRegistrationFixture.Registrations.Count -eq $ExpectedRegistrations) "Pipeline '$Mode' performs only the expected registration writes."
    foreach ($registration in $global:DAIBuildRegistrationFixture.Registrations) {
        Assert-Test ($registration.BdsVersion -eq (Get-BdsVersion $Version)) "Pipeline '$Mode' registers the correct IDE version."
    }
}

$originalRegistryReader = ${function:Get-BdsRegistryValues}
$originalRegistryOpener = ${function:Open-BdsUserRegistryKey}
$originalBdsEnvironment = $env:BDS
$originalComSpec = $env:ComSpec
$originalLastExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$originalFixtureVariable = Get-Variable -Name DAIBuildRegistrationFixture -Scope Global -ErrorAction SilentlyContinue
$script:FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'DAI-BuildRegistration-' + [guid]::NewGuid().ToString('N'))
$script:RegistryRows = @{}
$script:RegistryKeys = @{}
$script:OpenedKeys = [System.Collections.Generic.List[object]]::new()
$script:RegistryChanges = [System.Collections.Generic.List[object]]::new()

function Get-BdsRegistryValues {
    param([string] $BdsVersion)
    if ($script:RegistryRows.ContainsKey($BdsVersion)) {
        return $script:RegistryRows[$BdsVersion]
    }
    return @()
}

function Open-BdsUserRegistryKey {
    param([string] $SubKey, [switch] $Writable)
    if (-not $script:RegistryKeys.ContainsKey($SubKey)) {
        if (-not $Writable) { return $null }
        $script:RegistryKeys[$SubKey] = @{}
    }
    $key = [BuildRegistrationTestKey]::new($SubKey, $script:RegistryKeys[$SubKey],
                                          $script:RegistryChanges)
    $script:OpenedKeys.Add($key)
    return $key
}

try {
    [System.IO.Directory]::CreateDirectory($script:FixtureRoot) | Out-Null
    Assert-Test ((Get-BdsVersion -DelphiVersion 11) -eq '22.0') 'Delphi 11 uses IDE 22.0.'
    Assert-Test ((Get-BdsVersion -DelphiVersion 12) -eq '23.0') 'Delphi 12 uses IDE 23.0.'
    Assert-Test ((Get-BdsVersion -DelphiVersion 13) -eq '37.0') 'Delphi 13 uses IDE 37.0.'

    $delphi11 = New-TestInstallation -Name 'Delphi11'
    $delphi13 = New-TestInstallation -Name 'Delphi13' -Win64
    $script:RegistryRows['22.0'] = @($delphi11)
    $script:RegistryRows['37.0'] = @($delphi13)
    $env:BDS = $delphi13.RootDir

    $installation11 = Get-DelphiInstallation -DelphiVersion 11
    Assert-Test ($installation11.RootDir -eq $delphi11.RootDir) 'Requested Delphi version overrides inherited BDS.'
    Assert-Test ($installation11.BdsVersion -eq '22.0') 'Installation carries the IDE registry version.'
    Assert-Test ((Get-DelphiInstallation -DelphiVersion 12) -eq $null) 'Unavailable Delphi 12 has no installation.'
    $installation13 = Get-DelphiInstallation -DelphiVersion 13
    Assert-Test ($installation13.RootDir -eq $delphi13.RootDir) 'Delphi 13 resolves its own installation.'
    Assert-Test ((@(Get-IDEPlatforms -Installation $installation11) -join ',') -eq 'Win32') 'Delphi 11 has only a Win32 IDE.'
    Assert-Test ((@(Get-IDEPlatforms -Installation $installation13) -join ',') -eq 'Win32,Win64') 'Delphi 13 has both IDE architectures.'
    $withoutWin32 = [pscustomobject] @{ RootDir = $delphi13.RootDir;
        App = (Join-Path $script:FixtureRoot 'missing-bds.exe'); AppX64 = $delphi13.AppX64 }
    Assert-Test ((@(Get-IDEPlatforms -Installation $withoutWin32) -join ',') -eq 'Win64') 'IDE architecture detection checks actual executable files.'

    $explicit = Get-DelphiInstallation -DelphiVersion 11 -BdsRoot ($delphi11.RootDir + '\')
    Assert-Test ($explicit.BdsVersion -eq '22.0') 'Explicit root tolerates a trailing separator.'
    Assert-Test ((Get-DelphiInstallation -DelphiVersion 11 -BdsRoot $delphi13.RootDir) -eq $null) 'An explicit root for a different requested version is rejected.'
    New-TestBinary -Path $delphi11.AppX64 -Platform Win64
    $script:RegistryRows['22.0'] = @([pscustomobject] @{ RootDir = $delphi11.RootDir;
        App = $delphi11.App; AppX64 = '' })
    $installation11 = Get-DelphiInstallation -DelphiVersion 11
    Assert-Test ((@(Get-IDEPlatforms -Installation $installation11) -join ',') -eq 'Win32') 'dcc64 and a bin64 executable do not identify an installed x64 IDE without App x64.'
    $staleInstallationRoot = Join-Path $script:FixtureRoot 'StaleDelphi13'
    [System.IO.Directory]::CreateDirectory($staleInstallationRoot) | Out-Null
    $staleInstallation = [pscustomobject] @{ RootDir = $staleInstallationRoot; App = ''; AppX64 = '' }
    $script:RegistryRows['37.0'] = @($staleInstallation, $delphi13)
    Assert-Test ((Get-DelphiInstallation -DelphiVersion 13).RootDir -eq $delphi13.RootDir) 'A stale earlier registry record does not hide a working installation.'
    Assert-Test ((Get-DelphiInstallation -DelphiVersion 13 -BdsRoot $staleInstallationRoot) -eq $null) 'A stale existing installation directory without an IDE is unavailable.'

    $project = Join-Path $script:FixtureRoot 'Project with spaces'
    $package32 = Join-Path $project 'Build\Win32\Release\Bpl\DAI370.bpl'
    $package64 = Join-Path $project 'Build\Win64\Release\Bpl\DAI370.bpl'
    $stale32 = Join-Path $project 'Build\Win32\Debug\Bpl\DAI370.bpl'
    $legacy32 = Join-Path $project 'Build\Win32\Release\Bpl\DAI.bpl'
    $otherVersion = Join-Path $project 'Build\Win32\Release\Bpl\DAI280.bpl'
    $external = Join-Path $script:FixtureRoot 'OtherProject\Build\Win32\Release\Bpl\DAI370.bpl'
    $otherPackage = Join-Path $project 'Build\Win32\Release\Bpl\Unrelated370.bpl'
    New-TestBinary -Path $package32 -Package
    New-TestBinary -Path $package64 -Platform Win64 -Package

    $known32Path = 'Software\Embarcadero\BDS\37.0\Known Packages'
    $known64Path = 'Software\Embarcadero\BDS\37.0\Known Packages x64'
    $disabled32Path = 'Software\Embarcadero\BDS\37.0\Disabled Packages'
    $disabled64Path = 'Software\Embarcadero\BDS\37.0\Disabled Packages x64'
    $script:RegistryKeys[$known32Path] = @{
        $stale32 = 'previous config'; $legacy32 = 'old package'; $otherVersion = 'Delphi 11';
        $external = 'another project'; $package64 = 'another architecture'; $otherPackage = 'unrelated'
    }
    $script:RegistryKeys[$disabled32Path] = @{
        $package32 = 'disabled'; $stale32 = 'disabled'; $legacy32 = 'disabled';
        $external = 'disabled'; $otherPackage = 'disabled'
    }
    $script:RegistryKeys[$known64Path] = @{ $external = 'another project' }
    $script:RegistryKeys[$disabled64Path] = @{ $package64 = 'disabled'; $external = 'disabled' }

    Register-DAIPackage -PackageFile $package32 -TargetPlatform Win32 -BdsVersion '37.0' -ProjectRoot $project | Out-Null
    $known32 = $script:RegistryKeys[$known32Path]
    $disabled32 = $script:RegistryKeys[$disabled32Path]
    Assert-Test ($known32.ContainsKey($package32)) 'Win32 registration uses the absolute built package path.'
    Assert-Test ($known32[$package32] -eq 'DelphiAI (DAI)') 'Package registration has its description.'
    Assert-Test (-not $known32.ContainsKey($stale32)) 'Previous configuration registration is removed.'
    Assert-Test (-not $known32.ContainsKey($legacy32)) 'Legacy unsuffixed registration is removed.'
    Assert-Test ($known32.ContainsKey($otherVersion)) 'Different compiler package is preserved.'
    Assert-Test ($known32.ContainsKey($external)) 'A package from another project is preserved.'
    Assert-Test ($known32.ContainsKey($package64)) 'Another architecture is preserved.'
    Assert-Test ($known32.ContainsKey($otherPackage)) 'An unrelated package is preserved.'
    Assert-Test (-not $disabled32.ContainsKey($package32)) 'The new package is enabled.'
    Assert-Test (-not $disabled32.ContainsKey($stale32)) 'Stale disabled registration is removed.'
    Assert-Test (-not $disabled32.ContainsKey($legacy32)) 'Legacy disabled registration is removed.'
    Assert-Test ($disabled32.ContainsKey($external) -and $disabled32.ContainsKey($otherPackage)) 'Unrelated disabled entries are preserved.'
    Assert-Test (-not $script:RegistryKeys[$known64Path].ContainsKey($package64)) 'Win32 registration does not write the x64 package key.'

    Register-DAIPackage -PackageFile $package64 -TargetPlatform Win64 -BdsVersion '37.0' -ProjectRoot $project | Out-Null
    Assert-Test ($script:RegistryKeys[$known64Path].ContainsKey($package64)) 'Win64 registration uses Known Packages x64.'
    Assert-Test (-not $script:RegistryKeys[$disabled64Path].ContainsKey($package64)) 'Win64 registration enables its package.'
    Assert-Test ($script:RegistryKeys[$known64Path].ContainsKey($external)) 'Unrelated Win64 registrations are preserved.'
    $writes = @($script:RegistryChanges | Where-Object { $_.Operation -eq 'Set' })
    Assert-Test ($writes.Count -eq 2) 'Only the two requested packages are written.'
    Assert-Test (@($writes | Where-Object { $_.Kind -ne [Microsoft.Win32.RegistryValueKind]::String }).Count -eq 0) 'Package descriptions are REG_SZ values.'
    Assert-Test (@($script:OpenedKeys | Where-Object { -not $_.Disposed }).Count -eq 0) 'Registry keys are disposed.'

    $env:ComSpec = 'Invoke-BuildRegistrationFixtureCompiler'
    Test-BuildPipeline -Mode success -ExpectedRegistrations 2 -ExpectedCommands 4
    Test-BuildPipeline -Mode no-registration -Register $false -ExpectedCommands 4
    Test-BuildPipeline -Mode missing-version -Version 12 -SkipMissing
    Test-BuildPipeline -Mode explicit-mismatched-root -Version 11 -BdsRoot $delphi13.RootDir -SkipMissing -ExpectFailure $true
    Test-BuildPipeline -Mode package-failure -ExpectFailure $true -ExpectedCommands 1
    Test-BuildPipeline -Mode bridge-failure -ExpectFailure $true -ExpectedCommands 2
    Test-BuildPipeline -Mode wrong-package-architecture -ExpectFailure $true -ExpectedCommands 1
    Test-BuildPipeline -Mode wrong-bridge-architecture -ExpectFailure $true -ExpectedCommands 2
    Test-BuildPipeline -Mode stale-package -ExpectFailure $true -ExpectedCommands 1
    Test-BuildPipeline -Mode second-bridge-failure -ExpectFailure $true -ExpectedCommands 4
    Test-BuildPipeline -Mode win32-only-ide -Version 11 -ExpectedRegistrations 1 -ExpectedCommands 2
    Test-BuildPipeline -Mode missing-x64-ide -Version 11 -Platform Both -ExpectFailure $true

    # Parse the executable scripts with the same Windows PowerShell grammar used
    # by BUILD+REGISTER.cmd; helper tests above exercise their mutable behavior.
    foreach ($scriptPath in @((Join-Path $PSScriptRoot 'Build.Registration.ps1'),
                              (Join-Path (Split-Path -Parent $PSScriptRoot) 'Build.ps1'))) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $tokens,
                                                                  [ref] $parseErrors) | Out-Null
        Assert-Test ($parseErrors.Count -eq 0) "PowerShell syntax is valid: $scriptPath"
    }
    Write-Host "Build registration tests passed: $script:CheckCount checks. No Delphi registry keys were changed."
}
finally {
    Set-Item -Path Function:Get-BdsRegistryValues -Value $originalRegistryReader
    Set-Item -Path Function:Open-BdsUserRegistryKey -Value $originalRegistryOpener
    $env:BDS = $originalBdsEnvironment
    $env:ComSpec = $originalComSpec
    if ($null -ne $originalLastExitCode) {
        Set-Variable -Name LASTEXITCODE -Scope Global -Value $originalLastExitCode.Value
    }
    else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    if ($null -ne $originalFixtureVariable) {
        Set-Variable -Name DAIBuildRegistrationFixture -Scope Global -Value $originalFixtureVariable.Value
    }
    else { Remove-Variable -Name DAIBuildRegistrationFixture -Scope Global -ErrorAction SilentlyContinue }
    $resolvedFixture = [System.IO.Path]::GetFullPath($script:FixtureRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedFixture.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedFixture) -like 'DAI-BuildRegistration-*' -and
        (Test-Path -LiteralPath $resolvedFixture)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
