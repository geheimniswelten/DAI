[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) { $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'Source'
$fixture = Join-Path $PSScriptRoot 'ProjectToolsTests'
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $output = Join-Path $projectRoot "Build\Tests-ProjectTools-$currentPlatform"
    $dcu = $output + '-Dcu'
    New-Item -ItemType Directory -Force -Path $output, $dcu | Out-Null
    $compiler = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    & (Join-Path $BdsRoot "bin\$compiler") '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$output" "-N0$dcu" `
        "-U$fixture;$source;$(Join-Path $BdsRoot "lib\$currentPlatform\release")" (Join-Path $PSScriptRoot 'Test.ProjectTools.dpr')
    if ($LASTEXITCODE -ne 0) { throw "ProjectTools $currentPlatform compilation failed." }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $output 'Test.ProjectTools.exe'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Write-Output "$currentPlatform $($stdout.TrimEnd())"
        if ($process.ExitCode -ne 0 -or -not $stdout.Contains('PASS ProjectTools:')) { throw "ProjectTools failed: $stderr" }
    }
    finally { $process.Dispose() }
}
