[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Build.Output.ps1')

# These files and locks are isolated fixtures; no loaded IDE package is touched.
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DAI-BuildOutput-' + [guid]::NewGuid().ToString('N'))
$checkCount = 0
function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Test failed: $Message" }
    $script:checkCount++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-Test $failed $Message
}
function New-FixtureFile {
    param([string]$Path, [string]$Content)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content)
}
function Get-FailurePath {
    param([string[]]$Lines)
    return Get-PackageOutputFailurePath -OutputLines $Lines -ProjectRoot $script:projectRoot -OutputDirectory $script:outputDirectory
}

try {
    $projectRoot = Join-Path $fixtureRoot 'Project with spaces'
    $outputDirectory = Join-Path $projectRoot 'Build\Win32'
    $packagePath = Join-Path $outputDirectory 'DAI370.bpl'
    $backupPath = "$packagePath.deleted"
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

    $absoluteDiagnostic = "[dcc32 Fatal Error] F2039 Could not create output file '$packagePath'"
    Assert-Test ((Get-FailurePath @($absoluteDiagnostic)) -eq $packagePath) 'A quoted absolute F2039 target identifies the current output.'
    Assert-Test ((Get-FailurePath @("DAI.dpk(124): error F2039: Ausgabedatei '.\Build\Win32\DAI370.bpl' kann nicht erstellt werden")) -eq $packagePath) 'A localized MSBuild diagnostic with a colon identifies the current output.'
    Assert-Test ((Get-FailurePath @("F2039 Could not create output file '.\Build\Win32\DAI370.bpl'")) -eq $packagePath) 'A relative output target resolves against the project directory.'
    Assert-Test ((Get-FailurePath @('F2039 Could not create output file "DAI370.bpl"')) -eq $packagePath) 'A quoted bare filename resolves against the output directory.'
    Assert-Test ((Get-FailurePath @($absoluteDiagnostic, $absoluteDiagnostic)) -eq $packagePath) 'Repeated diagnostics for one target are unambiguous.'
    Assert-Test ($null -eq (Get-FailurePath @('E2003 Undeclared identifier: Broken'))) 'An ordinary compiler error does not trigger a fallback.'
    Assert-Test ($null -eq (Get-FailurePath @("E2003 Could not create output file '$packagePath'"))) 'The target filename alone does not qualify an ordinary error.'
    Assert-Test ($null -eq (Get-FailurePath @('F2039 Could not create output file DAI370.bpl'))) 'An unquoted target does not qualify.'
    Assert-Test ($null -eq (Get-FailurePath @("F2039 Could not create output file 'DAI.bpl'"))) 'An unsuffixed package is not renamed.'
    Assert-Test ($null -eq (Get-FailurePath @("F2039 Could not create output file 'Unrelated370.bpl'"))) 'An unrelated package is not renamed.'
    Assert-Test ($null -eq (Get-FailurePath @("F2039 Could not create output file 'DAI.McpBridge.exe'"))) 'An executable is not renamed.'
    Assert-Test ($null -eq (Get-FailurePath @("F2039 Could not create output file '..\Other\DAI370.bpl'"))) 'A target outside the current output directory is rejected.'
    Assert-Test ($null -eq (Get-FailurePath @($absoluteDiagnostic, "F2039 Could not create output file 'DAI280.bpl'"))) 'Two distinct output targets are ambiguous.'
    Assert-Test ($null -eq (Get-FailurePath @("F2039 Could not create output file '.\Build\Win32\Release\Bpl\DAI370.bpl'"))) 'An old Release output does not qualify for the shared-output fallback.'
    Assert-Test ($null -eq (Get-FailurePath @("F2039 Could not create output file '.\Build\Win32\Debug\Bpl\DAI370.bpl'"))) 'An old Debug output does not qualify for the shared-output fallback.'
    Assert-Test ($null -eq (Get-FailurePath @())) 'No compiler output means no fallback.'

    Assert-Test ($null -eq (Move-BlockedPackageOutput -Path $packagePath -OutputDirectory $outputDirectory)) 'A missing package is not renamed.'
    New-FixtureFile $packagePath 'unlocked current package'
    Assert-Test ($null -eq (Move-BlockedPackageOutput -Path $packagePath -OutputDirectory $outputDirectory)) 'An unlocked package is not renamed.'
    Assert-Test ([System.IO.File]::ReadAllText($packagePath) -eq 'unlocked current package') 'The unlocked package is unchanged.'
    Assert-Test (-not (Test-Path -LiteralPath $backupPath)) 'An unlocked package produces no deleted backup.'
    Assert-Throws { Move-BlockedPackageOutput -Path (Join-Path $fixtureRoot 'DAI370.bpl') -OutputDirectory $outputDirectory } 'A move outside the intended output folder is rejected.'
    Assert-Throws { Move-BlockedPackageOutput -Path (Join-Path $outputDirectory 'Unrelated370.bpl') -OutputDirectory $outputDirectory } 'A move of an unrelated filename is rejected.'

    $renameableLock = [System.IO.File]::Open($packagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))
    try {
        $moved = Move-BlockedPackageOutput -Path $packagePath -OutputDirectory $outputDirectory
        Assert-Test ($moved -eq $backupPath) 'A write-blocked package that shares deletion can be renamed.'
        Assert-Test (-not (Test-Path -LiteralPath $packagePath)) 'The original filename is free after renaming.'
        Assert-Test ([System.IO.File]::ReadAllText($backupPath) -eq 'unlocked current package') 'Renaming preserves the package contents.'
        New-FixtureFile $packagePath 'replacement package'
        Assert-Test ([System.IO.File]::ReadAllText($packagePath) -eq 'replacement package') 'A replacement can be written while the renamed package remains open.'
    }
    finally { $renameableLock.Dispose() }

    $renameableLock = [System.IO.File]::Open($packagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))
    try {
        $moved = Move-BlockedPackageOutput -Path $packagePath -OutputDirectory $outputDirectory
        Assert-Test ($moved -eq $backupPath) 'An existing unlocked deleted backup is replaced using the same name.'
        Assert-Test ([System.IO.File]::ReadAllText($backupPath) -eq 'replacement package') 'The replaced backup contains the latest blocked package.'
    }
    finally { $renameableLock.Dispose() }

    New-FixtureFile $packagePath 'next package'
    $lockedBackup = [System.IO.File]::Open($backupPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $renameableLock = [System.IO.File]::Open($packagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))
    try {
        $moved = Move-BlockedPackageOutput -Path $packagePath -OutputDirectory $outputDirectory
        Assert-Test ($moved -eq (Join-Path $outputDirectory 'DAI370.1.bpl.deleted')) 'A locked existing deleted backup uses a numbered backup.'
        Assert-Test ([System.IO.File]::ReadAllText($backupPath) -eq 'replacement package') 'A locked older backup is preserved.'
        Assert-Test ([System.IO.File]::ReadAllText($moved) -eq 'next package') 'The numbered backup contains the blocked package.'
    }
    finally { $renameableLock.Dispose(); $lockedBackup.Dispose() }

    New-FixtureFile $packagePath 'cannot rename'
    $nonrenameableLock = [System.IO.File]::Open($packagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        Assert-Throws { Move-BlockedPackageOutput -Path $packagePath -OutputDirectory $outputDirectory } 'A package that forbids renaming reports failure.'
        Assert-Test ([System.IO.File]::ReadAllText($packagePath) -eq 'cannot rename') 'A failed rename preserves the original package.'
    }
    finally { $nonrenameableLock.Dispose() }

    foreach ($scriptPath in @((Join-Path $PSScriptRoot 'Build.Output.ps1'), $PSCommandPath)) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-Test ($parseErrors.Count -eq 0) "PowerShell syntax is valid: $scriptPath"
    }
    Write-Host "Build output tests passed: $checkCount checks. No IDE packages were changed."
}
finally {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedFixture) -like 'DAI-BuildOutput-*' -and
        (Test-Path -LiteralPath $resolvedFixture)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
