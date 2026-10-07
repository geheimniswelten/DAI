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
$sourceDirectory = Join-Path $projectRoot 'Source'
$sourcePath = Join-Path $sourceDirectory 'h5u.DAI.MCP.Tools.pas'
$sourceText = [IO.File]::ReadAllText($sourcePath)
$fixtureDirectory = Join-Path $PSScriptRoot 'ToolDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests-ToolDispatch-ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)

function Extract-One([string]$pattern, [string]$description) {
    $matchesFound = [regex]::Matches($sourceText, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)
    if ($matchesFound.Count -ne 1) {
        throw "Expected exactly one production $description; found $($matchesFound.Count)."
    }
    return $matchesFound[0].Groups['body'].Value
}

# Scope: this compiles the actual window dispatch branch, ArgumentString and
# RequirePermission, not the complete MCP catalog/transport or unrelated OTA
# services. Their original source bytes are inserted without rewriting logic.
# Only the permission authority and final window action are isolated doubles.
$argumentString = Extract-One '(?<body>function ArgumentString\(.*?\r\nend;\r\n)(?=\r\nfunction ArgumentBoolean\()' 'ArgumentString'
$requirePermission = Extract-One '(?<body>procedure RequirePermission\(.*?\r\nend;\r\n)(?=\r\nprocedure EnsureDebuggerIdle;)' 'RequirePermission'
$branch = Extract-One "(?<body>  if SameText\(AName, 'ide_window_control'\) then\r\n.*?)(?=  if SameText\(AName, 'ide_logs_read'\) then)" 'window branch'
$callHeader = Extract-One '(?<body>class function TDAIMCPTools\.CallTool\(.*?\r\nvar\r\n.*?)(?=\r\nbegin\r\n)' 'CallTool declarations'
$actionDeclaration = [regex]::Match($callHeader, '(?m)^  LAction: string;\r?$').Value.TrimEnd("`r")
$contextDeclaration = [regex]::Match($callHeader, '(?m)^  LContext: TDAIRequestContext;\r?$').Value.TrimEnd("`r")
if ([string]::IsNullOrWhiteSpace($actionDeclaration) -or [string]::IsNullOrWhiteSpace($contextDeclaration)) {
    throw 'Production locals changed: update the isolated wrapper explicitly instead of silently replacing logic.'
}
if (-not $branch.Contains('RequirePermission(pcExecute') -or -not $branch.Contains('TDAIIDEControl.Control(')) {
    throw 'The expected permission/action production branch is missing.'
}
$header = @'
unit DAI.ToolDispatch.ProductionBranch;

interface

uses
  System.JSON,
  h5u.DAI.Types;

function DispatchWindowControl(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;

implementation

uses
  System.SysUtils,
  h5u.DAI.IDE.Control,
  h5u.DAI.Permissions.Manager;

'@
$wrapperStart = @'
function DispatchWindowControl(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
'@
$wrapperBody = @'
begin
  LContext := AContext;

'@
$footer = @'
  raise EArgumentException.Create('This isolated fixture only exposes ide_window_control.');
end;

end.
'@
# Wrapper context is supplied by the test; project/transport context inference
# is intentionally outside this branch contract. Production Types are real.
$crlf = "`r`n"
$generatedText = ($header -replace '\r?\n', $crlf) + $crlf + $argumentString + $crlf + $requirePermission + $crlf +
    ($wrapperStart -replace '\r?\n', $crlf) + $crlf + $actionDeclaration + $crlf + $contextDeclaration + $crlf +
    ($wrapperBody -replace '\r?\n', $crlf) + $crlf + $branch + ($footer -replace '\r?\n', $crlf) + $crlf
if (-not $generatedText.Contains($argumentString) -or -not $generatedText.Contains($requirePermission) -or
    -not $generatedText.Contains($branch)) {
    throw 'The generated fixture must contain all three original source regions verbatim.'
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
$generatedPath = Join-Path $generatedDirectory 'DAI.ToolDispatch.ProductionBranch.pas'
[IO.File]::WriteAllText($generatedPath, $generatedText, $utf8Bom)
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)

# Win32 installer detection mistakes the filename's "patch" substring for an
# installer. An explicit asInvoker manifest keeps this console test unelevated.
$resourceCompiler = Join-Path $BdsRoot 'bin\brcc32.exe'
$resourceOutput = Join-Path $generatedDirectory 'dai-test-as-invoker.res'
$resourceScript = Join-Path $generatedDirectory 'dai-test-as-invoker.rc'
# BRCC32 predates UTF-8 BOM support; convert only its build input to ASCII.
[IO.File]::WriteAllText($resourceScript, [IO.File]::ReadAllText((Join-Path $fixtureDirectory 'dai-test-as-invoker.rc')),
    [Text.Encoding]::ASCII)
Push-Location -LiteralPath $fixtureDirectory
try {
    & $resourceCompiler "-fo$resourceOutput" $resourceScript
    if ($LASTEXITCODE -ne 0) {
        throw "The test's asInvoker manifest failed to compile (exit code $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-ToolDispatch-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerArguments = @(
        '-B'
        '-Q'
        '-$B+'
        '-$Q+'
        '-$R+'
        "-E$outputDirectory"
        "-N0$dcuDirectory"
        "-R$generatedDirectory"
        "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.ToolDispatch.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Tool-dispatch test for $currentPlatform failed to compile (exit code $LASTEXITCODE)."
    }
    # No running IDE, window, registry, client configuration or server is used.
    $testInfo = [Diagnostics.ProcessStartInfo]::new()
    $testInfo.FileName = Join-Path $outputDirectory 'Test.ToolDispatch.exe'
    $testInfo.UseShellExecute = $false
    $testInfo.CreateNoWindow = $true
    $testInfo.RedirectStandardOutput = $true
    $testInfo.RedirectStandardError = $true
    $testProcess = [Diagnostics.Process]::new()
    $testProcess.StartInfo = $testInfo
    try {
        [void]$testProcess.Start()
        $testOutput = $testProcess.StandardOutput.ReadToEnd()
        $testError = $testProcess.StandardError.ReadToEnd()
        $testProcess.WaitForExit()
        Write-Output "$currentPlatform $($testOutput.TrimEnd())"
        if ($testProcess.ExitCode -ne 0 -or -not $testOutput.Contains('PASS ToolDispatch:')) {
            throw "Tool-dispatch test for $currentPlatform failed (exit code $($testProcess.ExitCode)). $testError"
        }
    }
    finally {
        $testProcess.Dispose()
    }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production source changed while the extracted-branch regression was running; rerun against the new source.'
}
