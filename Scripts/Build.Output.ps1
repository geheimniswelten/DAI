# Helpers for Build.ps1. Loading this file does not change build outputs.
Set-StrictMode -Version Latest

function Get-PackageOutputFailurePath {
    param([string[]]$OutputLines, [string]$ProjectRoot, [string]$OutputDirectory)

    $directory = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
    $paths = @{}
    # The compiler supplies the LIBSUFFIX AUTO filename. Do not guess its suffix
    # or react to an unrelated compile error while an older package is loaded.
    $pattern = '(?i)\bF2039\b\s*:?.*?(?<quote>[''"])(?<path>[^''"\r\n]+\.bpl)\k<quote>'
    foreach ($line in $OutputLines) {
        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) { continue }
        $reported = $match.Groups['path'].Value
        try {
            if ([System.IO.Path]::IsPathRooted($reported)) {
                $path = [System.IO.Path]::GetFullPath($reported)
            }
            elseif (-not [System.IO.Path]::GetDirectoryName($reported)) {
                $path = [System.IO.Path]::GetFullPath((Join-Path $directory $reported))
            }
            else {
                $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $reported))
            }
        }
        catch { continue }
        if ([System.IO.Path]::GetFileName($path) -notmatch '^DAI[0-9]+\.bpl$' -or
            -not [string]::Equals([System.IO.Path]::GetDirectoryName($path), $directory,
                                 [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $paths[$path] = $true
    }
    if ($paths.Count -eq 1) { return [string]@($paths.Keys)[0] }
    return $null
}

function Move-BlockedPackageOutput {
    param([string]$Path, [string]$OutputDirectory)

    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $directory = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
    if ([System.IO.Path]::GetFileName($pathFull) -notmatch '^DAI[0-9]+\.bpl$' -or
        -not [string]::Equals([System.IO.Path]::GetDirectoryName($pathFull), $directory,
                             [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "BPL liegt nicht im erwarteten Ausgabeverzeichnis: $pathFull"
    }
    if (-not (Test-Path -LiteralPath $pathFull -PathType Leaf)) { return $null }
    $file = Get-Item -LiteralPath $pathFull -Force
    if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "BPL ist eine Dateiverknüpfung und wird nicht umbenannt: $pathFull"
    }

    # Probe without truncating or changing the existing file. If exclusive write
    # access works, renaming cannot fix the compiler's output creation failure.
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($pathFull, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        return $null
    }
    catch [System.IO.IOException] { }
    catch [System.UnauthorizedAccessException] { }
    finally { if ($null -ne $stream) { $stream.Dispose() } }

    $backupBase = [System.IO.Path]::GetFileName($pathFull)
    $number = 0
    while ($true) {
        $backupName = if ($number -eq 0) { "$backupBase.deleted" } else {
            "$([System.IO.Path]::GetFileNameWithoutExtension($pathFull)).$number.bpl.deleted"
        }
        $backup = [System.IO.Path]::GetFullPath((Join-Path $directory $backupName))
        if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($backup), $directory,
                                 [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Ungültiger BPL-Sicherungsname: $backup"
        }
        if (Test-Path -LiteralPath $backup) {
            $existing = Get-Item -LiteralPath $backup -Force
            if ($existing.PSIsContainer -or
                ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $number++
                continue
            }
            try { Remove-Item -LiteralPath $backup -Force -ErrorAction Stop }
            catch {
                # A previous IDE process may still hold this backup too.
                $number++
                continue
            }
        }
        Rename-Item -LiteralPath $pathFull -NewName $backupName -ErrorAction Stop
        Write-Host "Blockierte BPL umbenannt: $backup"
        return $backup
    }
}
