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
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$fixtureDirectory = Join-Path $PSScriptRoot 'ProjectOptionsDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests\ProjectOptionsDispatch\ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"
$toolNames = @('project_activate', 'project_options_configurations', 'project_options_read', 'project_option_set', 'project_option_remove')

function Extract-One([string]$pattern, [string]$description) {
    $matchesFound = [regex]::Matches($sourceText, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($matchesFound.Count -ne 1) {
        throw "Expected exactly one production $description; found $($matchesFound.Count)."
    }
    return $matchesFound[0].Groups['body'].Value
}

# Actual production code is copied verbatim. The fixture replaces only the
# permission authority and final OTA service. Initial transport/project context
# inference is outside this scope; each branch receives a fixed request context.
$helpers = @()
foreach ($helperName in @('JsonObjectFromText', 'AddTool', 'StrictArgumentString', 'RequiredArgumentString',
        'StrictArgumentStringArray', 'StrictArgumentInteger', 'RequirePermission')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $helperName\(.*?^end;\r\n)" $helperName
}
$branches = @()
$schemas = @()
$branches += Extract-One "(?<body>^  if SameText\(AName, 'project_activate'\) then\r\n.*?^  end;\r\n)" 'project_activate branch'
$branches += Extract-One "(?<body>^  if SameText\(AName, 'project_options_configurations'\).*?^  end;\r\n)" 'shared project-options branch'
foreach ($toolName in $toolNames) {
    $schemas += Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$toolName',.*?\);\r\n)" "$toolName schema"
}
$branchText = $branches -join $crlf
foreach ($toolName in $toolNames) {
    if (-not $branchText.Contains("'$toolName'")) {
        throw "The extracted production dispatch must contain $toolName."
    }
}
if (-not $branchText.Contains('TDAIProjectOptionsService.') -or -not $branchText.Contains('RequirePermission(pcReadAccess') -or
    -not $branchText.Contains('RequirePermission(pcEditInsideIDE')) {
    throw 'Expected read/edit permissions and final project-options service calls are missing.'
}
$callHeader = Extract-One '(?<body>^class function TDAIMCPTools\.CallTool\(.*?\r\nvar\r\n.*?)(?=\r\nbegin\r\n)' 'CallTool declarations'
$localDeclarations = @()
foreach ($local in [regex]::Matches($callHeader, '(?m)^  (?<names>L\w+(?:, L\w+)*): (?<type>[^;]+);\r?$')) {
    $used = $false
    foreach ($localName in $local.Groups['names'].Value.Split(',').Trim()) {
        if ($localName -eq 'LContext' -or [regex]::IsMatch($branchText, "\b$localName\b")) {
            $used = $true
        }
    }
    if ($used) {
        $localDeclarations += $local.Value.TrimEnd("`r")
    }
}
if (-not ($localDeclarations -join $crlf).Contains('LContext: TDAIRequestContext;')) {
    throw 'Production request-context declaration is missing.'
}
$header = @'
unit DAI.ProjectOptionsDispatch.ProductionBranch;

interface

uses
  System.JSON,
  h5u.DAI.Types;

function DispatchProjectOptions(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
function ListProjectOptionsSchemas: TJSONArray;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.SysUtils,
  h5u.DAI.OTA.ProjectOptions,
  h5u.DAI.Permissions.Manager;

'@
$dispatchStart = @'
function DispatchProjectOptions(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
'@
$dispatchBody = @'
begin
  LContext := AContext;

'@
$dispatchEnd = @'
  raise EArgumentException.Create('This isolated fixture exposes only the five project-options tools.');
end;

function ListProjectOptionsSchemas: TJSONArray;
begin
  Result := TJSONArray.Create;
'@
$footer = @'
end;

end.
'@
$generatedText = ($header -replace '\r?\n', $crlf) + $crlf + ($helpers -join $crlf) + $crlf +
    ($dispatchStart -replace '\r?\n', $crlf) + $crlf + ($localDeclarations -join $crlf) + $crlf +
    ($dispatchBody -replace '\r?\n', $crlf) + $crlf + $branchText + $crlf +
    ($dispatchEnd -replace '\r?\n', $crlf) + $crlf + ($schemas -join $crlf) + ($footer -replace '\r?\n', $crlf) + $crlf
foreach ($region in @($helpers) + @($branches) + @($schemas)) {
    if (-not $generatedText.Contains($region)) {
        throw 'Every extracted production region must appear unchanged in the generated fixture.'
    }
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.ProjectOptionsDispatch.ProductionBranch.pas'), $generatedText, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)

# Explicit asInvoker avoids Windows interpreting the executable's "Dispatch"
# substring as an installer name. Resource input uses BRCC32-compatible ASCII.
$resourceCompiler = Join-Path $BdsRoot 'bin\brcc32.exe'
$resourceOutput = Join-Path $generatedDirectory 'dai-test-as-invoker.res'
$resourceScript = Join-Path $generatedDirectory 'dai-test-as-invoker.rc'
[IO.File]::WriteAllText($resourceScript, [IO.File]::ReadAllText((Join-Path $fixtureDirectory 'dai-test-as-invoker.rc')),
    [Text.Encoding]::ASCII)
Push-Location -LiteralPath $fixtureDirectory
try {
    & $resourceCompiler "-fo$resourceOutput" $resourceScript
    if ($LASTEXITCODE -ne 0) {
        throw "The asInvoker test resource failed to compile (exit code $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\ProjectOptionsDispatch\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
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
        (Join-Path $PSScriptRoot 'Test.ProjectOptionsDispatch.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Project-options dispatch test for $currentPlatform failed to compile (exit code $LASTEXITCODE)."
    }
    $testInfo = [Diagnostics.ProcessStartInfo]::new()
    $testInfo.FileName = Join-Path $outputDirectory 'Test.ProjectOptionsDispatch.exe'
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
        if ($testProcess.ExitCode -ne 0 -or -not $testOutput.Contains('PASS ProjectOptionsDispatch:')) {
            throw "Project-options dispatch test for $currentPlatform failed (exit code $($testProcess.ExitCode)). $testError"
        }
    }
    finally {
        $testProcess.Dispose()
    }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production source changed while the extracted-branch test was running; rerun against the new source.'
}
