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
$sourcePath = Join-Path $source 'h5u.DAI.MCP.Tools.pas'
$sourceText = [IO.File]::ReadAllText($sourcePath)
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$generated = Join-Path $projectRoot 'Build\Tests-ProjectToolsDispatch-ProductionBranch'
$fixture = Join-Path $PSScriptRoot 'ProjectToolsDispatchTests'
$permissions = Join-Path $PSScriptRoot 'PermissionRoutingTests'
$crlf = "`r`n"
function Extract-One([string]$pattern, [string]$name) {
    $matches = [regex]::Matches($sourceText, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($matches.Count -ne 1) { throw "Expected one production $name; found $($matches.Count)." }
    return $matches[0].Groups['body'].Value
}
$helpers = foreach ($name in @('JsonObjectFromText', 'AddTool', 'ArgumentString', 'StrictArgumentString', 'RequiredArgumentString',
    'ValidateToolArguments', 'RequirePermission', 'ContextForArguments')) {
    Extract-One "(?<body>^(?:function|procedure) $name\(.*?^end;\r?\n)" $name
}
$needsProject = Extract-One '(?<body>^class function TDAIMCPTools.NeedsProjectContext\(.*?^end;\r?\n)' 'project context policy'
$context = Extract-One '(?<body>^  if NeedsProjectContext\(AName, AArguments\) then.*?)(?=^  TDAILog.Access)' 'context setup'
$branch = Extract-One "(?<body>^  if SameText\(AName, 'project_tools_list'\) or SameText\(AName, 'project_tool_call'\) then.*?^  end;\r?\n)" 'extension dispatch'
$schemas = foreach ($name in @('project_tools_list', 'project_tool_call')) {
    Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$name',.*?\);\r?\n)" "$name schema"
}
$header = @'
unit DAI.ProjectTools.DispatchBranch;
interface
uses System.JSON, h5u.DAI.Types;
type
  TDAIMCPTools = class sealed
  public
    class function ListTools: TJSONArray; static;
    class function NeedsProjectContext(const AName: string; const AArguments: TJSONObject): Boolean; static;
    class function CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject; static;
  end;
implementation
uses System.Classes, System.SysUtils, System.IOUtils, ToolsAPI, h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager, h5u.DAI.ProjectTools, h5u.DAI.Settings;
'@
$dispatch = @'
class function TDAIMCPTools.CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
  LProjectObject: IOTAProject;
  LProject, LExtensionId, LExtensionTool: string;
  LExtensionArguments: TJSONValue;
  LContext: TDAIRequestContext;
begin
  ValidateToolArguments(AName, AArguments);
'@
$list = @'
  raise EArgumentException.Create('This fixture exposes only project extension wrappers.');
end;
class function TDAIMCPTools.ListTools: TJSONArray;
begin
  Result := TJSONArray.Create;
'@
$content = ($header -replace '\r?\n', $crlf) + $crlf + ($helpers -join $crlf) + $crlf + $needsProject + $crlf +
    ($dispatch -replace '\r?\n', $crlf) + $crlf + $context + $branch + ($list -replace '\r?\n', $crlf) + $crlf +
    ($schemas -join $crlf) + "end;$crlf" + "end.$crlf"
foreach($region in @($helpers) + @($needsProject, $context, $branch) + @($schemas)) {
    if (-not $content.Contains($region)) { throw 'An extracted production region was altered.' }
}
New-Item -ItemType Directory -Force -Path $generated | Out-Null
[IO.File]::WriteAllText((Join-Path $generated 'DAI.ProjectTools.DispatchBranch.pas'), $content, [Text.UTF8Encoding]::new($true))
# Reuse the test manifest so Windows' installer-name heuristic never requests elevation.
$resourceFixture = Join-Path $PSScriptRoot 'DesignerDispatchTests'
Push-Location -LiteralPath $resourceFixture
try {
    & (Join-Path $BdsRoot 'bin\brcc32.exe') "-fo$(Join-Path $generated 'dai-test-as-invoker.res')" 'dai-test-as-invoker.rc'
    if ($LASTEXITCODE -ne 0) { throw 'Test manifest compilation failed.' }
}
finally { Pop-Location }
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $output = Join-Path $projectRoot "Build\Tests-ProjectToolsDispatch-$currentPlatform"
    $dcu = $output + '-Dcu'
    New-Item -ItemType Directory -Force -Path $output, $dcu | Out-Null
    $compiler = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    & (Join-Path $BdsRoot "bin\$compiler") '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$output" "-N0$dcu" `
        "-R$generated" "-U$generated;$fixture;$permissions;$source;$(Join-Path $BdsRoot "lib\$currentPlatform\release")" `
        (Join-Path $PSScriptRoot 'Test.ProjectToolsDispatch.dpr')
    if ($LASTEXITCODE -ne 0) { throw "ProjectToolsDispatch $currentPlatform compilation failed." }
    & (Join-Path $output 'Test.ProjectToolsDispatch.exe')
    if ($LASTEXITCODE -ne 0) { throw "ProjectToolsDispatch $currentPlatform failed." }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Production dispatch changed during tests; rerun.' }
