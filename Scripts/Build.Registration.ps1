# Helpers for Build.ps1. Loading this file does not build or change the registry.
Set-StrictMode -Version Latest

function Get-BdsVersion {
    param([ValidateSet('11', '12', '13')][string]$DelphiVersion)
    return @{ '11' = '22.0'; '12' = '23.0'; '13' = '37.0' }[$DelphiVersion]
}

function Get-NormalizedBuildPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\', '/')
}

function Get-BdsRegistryValues {
    param([string]$BdsVersion)

    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
            $key = $null
            try {
                $key = $baseKey.OpenSubKey("Software\Embarcadero\BDS\$BdsVersion")
                if ($null -ne $key) {
                    [pscustomobject]@{
                        RootDir = [string]$key.GetValue('RootDir', '')
                        App = [string]$key.GetValue('App', '')
                        AppX64 = [string]$key.GetValue('App x64', '')
                    }
                }
            }
            finally {
                if ($null -ne $key) { $key.Dispose() }
                $baseKey.Dispose()
            }
        }
    }
}

function Get-DelphiInstallation {
    param([string]$DelphiVersion = '', [string]$BdsRoot = '')

    $requestedRoot = if ([string]::IsNullOrWhiteSpace($BdsRoot)) { '' } else { Get-NormalizedBuildPath $BdsRoot }
    $versions = if ($DelphiVersion) { @($DelphiVersion) } else { @('11', '12', '13') }
    foreach ($version in $versions) {
        $bdsVersion = Get-BdsVersion -DelphiVersion $version
        $records = @(Get-BdsRegistryValues -BdsVersion $bdsVersion)
        foreach ($record in $records) {
            $root = $record.RootDir
            if ([string]::IsNullOrWhiteSpace($root) -and -not [string]::IsNullOrWhiteSpace($record.App)) {
                $root = Split-Path -Parent (Split-Path -Parent $record.App)
            }
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            $root = Get-NormalizedBuildPath $root
            if (($requestedRoot -and $root -ine $requestedRoot) -or
                -not (Test-Path -LiteralPath $root -PathType Container)) { continue }

            $app = ''
            $appX64 = ''
            foreach ($candidate in $records) {
                $candidateRoot = $candidate.RootDir
                if ([string]::IsNullOrWhiteSpace($candidateRoot) -and $candidate.App) {
                    $candidateRoot = Split-Path -Parent (Split-Path -Parent $candidate.App)
                }
                if (-not $candidateRoot -or (Get-NormalizedBuildPath $candidateRoot) -ine $root) { continue }
                if ($candidate.App -and (Test-Path -LiteralPath $candidate.App -PathType Leaf)) {
                    $app = Get-NormalizedBuildPath $candidate.App
                }
                # App x64, not the presence of dcc64.exe, identifies the 64-bit IDE.
                if ($candidate.AppX64 -and (Test-Path -LiteralPath $candidate.AppX64 -PathType Leaf)) {
                    $appX64 = Get-NormalizedBuildPath $candidate.AppX64
                }
            }
            if (-not $app) {
                $defaultApp = Join-Path $root 'bin\bds.exe'
                if (Test-Path -LiteralPath $defaultApp -PathType Leaf) { $app = $defaultApp }
            }
            # A leftover directory/key must not hide a working installation in another hive.
            if (-not $app -and -not $appX64) { continue }
            return [pscustomobject]@{
                DelphiVersion = $version
                BdsVersion = $bdsVersion
                RootDir = $root
                App = $app
                AppX64 = $appX64
            }
        }
    }
    return $null
}

function Get-IDEPlatforms {
    param([object]$Installation)
    if ($Installation.App -and (Test-Path -LiteralPath $Installation.App -PathType Leaf)) { 'Win32' }
    if ($Installation.AppX64 -and (Test-Path -LiteralPath $Installation.AppX64 -PathType Leaf)) { 'Win64' }
}

function Open-BdsUserRegistryKey {
    param([string]$SubKey, [switch]$Writable)
    # HKCU\Software\Embarcadero is shared between registry views. x64 is a key suffix.
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry32)
    try {
        if ($Writable) { return $baseKey.CreateSubKey($SubKey) }
        return $baseKey.OpenSubKey($SubKey)
    }
    finally { $baseKey.Dispose() }
}

function Test-OwnedDAIPackage {
    param([string]$Path, [string]$PackageFile, [string]$TargetPlatform, [string]$ProjectRoot)
    try {
        $pathName = Get-NormalizedBuildPath $Path
        $fileName = [System.IO.Path]::GetFileName($pathName)
        if ($fileName -ine [System.IO.Path]::GetFileName($PackageFile) -and $fileName -ine 'DAI.bpl') { return $false }
        $buildRoot = (Get-NormalizedBuildPath (Join-Path $ProjectRoot "Build\$TargetPlatform")) + '\'
        if (-not $pathName.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $relativePath = $pathName.Substring($buildRoot.Length)
        return $relativePath -match '^(?:(?:Debug|Release)\\Bpl\\)?DAI(?:[0-9]+)?\.bpl$'
    }
    catch { return $false }
}

function Register-DAIPackage {
    param([string]$PackageFile, [string]$TargetPlatform, [string]$BdsVersion, [string]$ProjectRoot)

    $packagePath = Get-NormalizedBuildPath $PackageFile
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw "BPL fehlt: $packagePath" }
    $suffix = if ($TargetPlatform -eq 'Win64') { ' x64' } else { '' }
    $profileKey = "Software\Embarcadero\BDS\$BdsVersion"
    $knownPath = "$profileKey\Known Packages$suffix"
    $knownKey = Open-BdsUserRegistryKey -SubKey $knownPath -Writable
    try {
        $knownKey.SetValue($packagePath, 'DelphiAI (DAI)', [Microsoft.Win32.RegistryValueKind]::String)
        foreach ($valueName in $knownKey.GetValueNames()) {
            if ($valueName -ine $packagePath -and
                (Test-OwnedDAIPackage -Path $valueName -PackageFile $packagePath -TargetPlatform $TargetPlatform -ProjectRoot $ProjectRoot)) {
                $knownKey.DeleteValue($valueName, $false)
                Write-Host "Alten DAI-Eintrag ersetzt: $valueName"
            }
        }
    }
    finally { $knownKey.Dispose() }

    # Use a writable handle only for an existing Disabled Packages key.
    $disabledKey = Open-BdsUserRegistryKey -SubKey "$profileKey\Disabled Packages$suffix"
    if ($null -ne $disabledKey) {
        $disabledKey.Dispose()
        $disabledKey = Open-BdsUserRegistryKey -SubKey "$profileKey\Disabled Packages$suffix" -Writable
        try {
            foreach ($valueName in $disabledKey.GetValueNames()) {
                if ($valueName -ieq $packagePath -or
                    (Test-OwnedDAIPackage -Path $valueName -PackageFile $packagePath -TargetPlatform $TargetPlatform -ProjectRoot $ProjectRoot)) {
                    $disabledKey.DeleteValue($valueName, $false)
                }
            }
        }
        finally { $disabledKey.Dispose() }
    }
    Write-Host "Registriert: HKCU\$knownPath -> $packagePath"
}
