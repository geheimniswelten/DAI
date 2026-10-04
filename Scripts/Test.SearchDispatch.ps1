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
$fixtureDirectory = Join-Path $PSScriptRoot 'SearchDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests\SearchDispatch\ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"
$toolNames = @('source_search', 'directory_files_list', 'project_directory_files_list', 'reference_files_list')

function Extract-One([string]$pattern, [string]$description) {
    $matchesFound = [regex]::Matches($sourceText, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($matchesFound.Count -ne 1) {
        throw "Expected exactly one production $description; found $($matchesFound.Count)."
    }
    return $matchesFound[0].Groups['body'].Value
}

# Actual production code is copied verbatim. The fixture replaces only the
# permission authority, final OTA services and project lookup boundary. Initial transport/project context
# inference is outside this scope; each branch receives a fixed request context.
$helpers = @()
foreach ($helperName in @('JsonObjectFromText', 'AddTool', 'ArgumentString', 'StrictArgumentString', 'ArgumentBoolean',
        'StrictArgumentBoolean', 'ArgumentInteger', 'ArgumentStringArray', 'RequirePermission', 'DirectoryFilesResult', 'DirectoryFilesSchema')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $helperName\(.*?^end;\r\n)" $helperName
}
$branches = @()
$schemas = @()
foreach ($toolName in $toolNames) {
    $branches += Extract-One "(?<body>^  if SameText\(AName, '$toolName'\) then\r\n.*?^  end;\r\n)" "$toolName branch"
    if ($toolName -eq 'source_search') {
        # Keep both compiler branches, including the final IFEND directive.
        $schemas += Extract-One '(?<body>^  AddTool\(Result, ''source_search'',.*?^    \{\$IFEND\}\r\n)' "$toolName schema"
    }
    else {
        $schemas += Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$toolName',.*?\);\r\n)" "$toolName schema"
    }
}
$branchText = $branches -join $crlf
foreach ($toolName in $toolNames) {
    if (-not $branchText.Contains("'$toolName'")) {
        throw "The extracted production dispatch must contain $toolName."
    }
}
if (-not $branchText.Contains('TDAISourceSearchService.') -or -not $branchText.Contains('DirectoryFilesResult(') -or
    -not $branchText.Contains('RequirePermission(pcReadAccess')) {
    throw 'Expected read permissions and final search/directory service calls are missing.'
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
unit DAI.SearchDispatch.ProductionBranch;

{$IF CompilerVersion >= 36.0}
{$TEXTBLOCK CRLF JSON}
{$IFEND}

interface

uses
  System.JSON,
  h5u.DAI.Types;

function DispatchSearch(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
function ListSearchSchemas: TJSONArray;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.SysUtils,
  System.IOUtils,
  ToolsAPI,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Search,
  h5u.DAI.Source.Search,
  h5u.DAI.Permissions.Manager;

'@
$dispatchStart = @'
function DispatchSearch(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
'@
$dispatchBody = @'
begin
  LContext := AContext;

'@
$dispatchEnd = @'
  raise EArgumentException.Create('This isolated fixture exposes only the four search tools.');
end;

function ListSearchSchemas: TJSONArray;
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
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.SearchDispatch.ProductionBranch.pas'), $generatedText, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)

# Use the actual production plan record, rather than duplicating its fields in a stub.
$planPath = Join-Path $sourceDirectory 'h5u.DAI.OTA.Search.pas'
$planSource = [IO.File]::ReadAllText($planPath)
$planHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
$planMatches = [regex]::Matches($planSource, '(?ms)^  TDAISourceSearchPlan = record\r\n.*?^  end;\r\n')
if ($planMatches.Count -ne 1) {
    throw "Expected exactly one production search plan record; found $($planMatches.Count)."
}
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.SearchDispatch.Plan.inc'), $planMatches[0].Value, $utf8Bom)

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
    $outputDirectory = Join-Path $projectRoot "Build\Tests\SearchDispatch\$currentPlatform"
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
        "-I$generatedDirectory"
        "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory"
        (Join-Path $PSScriptRoot 'Test.SearchDispatch.dpr')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Search dispatch test for $currentPlatform failed to compile (exit code $LASTEXITCODE)."
    }
    $testInfo = [Diagnostics.ProcessStartInfo]::new()
    $testInfo.FileName = Join-Path $outputDirectory 'Test.SearchDispatch.exe'
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
        if ($testProcess.ExitCode -ne 0 -or -not $testOutput.Contains('PASS SearchDispatch:')) {
            throw "Search dispatch test for $currentPlatform failed (exit code $($testProcess.ExitCode)). $testError"
        }
    }
    finally {
        $testProcess.Dispose()
    }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production source changed while the extracted-branch test was running; rerun against the new source.'
}

if ((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -ne $planHash) {
    throw 'Production plan record changed during the test; rerun against the new source.'
}
