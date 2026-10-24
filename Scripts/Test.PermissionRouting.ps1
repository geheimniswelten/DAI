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
$fixtureDirectory = Join-Path $PSScriptRoot 'PermissionRoutingTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests-PermissionRouting-ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"

function Extract-One([string]$pattern, [string]$description) {
    $found = [regex]::Matches($sourceText, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)
    if ($found.Count -ne 1) {
        throw "Expected exactly one production $description; found $($found.Count)."
    }
    return $found[0].Groups['body'].Value
}

# Compile original source regions verbatim. Only permission storage and the
# final file/project services are doubles. No IDE or real files are touched.
$jsonObject = Extract-One '(?<body>function JsonObjectFromText\(.*?\r\nend;\r\n)(?=\r\nprocedure AddTool\()' 'JSON schema parser'
$addTool = Extract-One '(?<body>procedure AddTool\(.*?\r\nend;\r\n)(?=\r\nfunction ArgumentString\()' 'AddTool'
$validator = Extract-One '(?<body>procedure ValidateToolArguments\(.*?\r\nend;\r\n)(?=\r\nprocedure RequirePermission\()' 'argument validator'
$resolver = Extract-One '(?<body>function ContextForArguments\(.*?\r\nend;\r\n)(?=\r\nfunction CursorFileContext\()' 'permission context resolver'
$directorySchema = Extract-One '(?<body>function DirectoryFilesSchema\(.*?\r\nend;\r\n)(?=\r\nclass function TDAIMCPTools.ListTools)' 'directory schema'
$catalog = Extract-One '(?<body>class function TDAIMCPTools.ListTools.*?\r\nend;\r\n)(?=\r\nend\.)' 'full tool catalog'
$argumentString = Extract-One '(?<body>function ArgumentString\(.*?\r\nend;\r\n)(?=\r\nfunction StrictArgumentString\()' 'ArgumentString'
$argumentBoolean = Extract-One '(?<body>function ArgumentBoolean\(.*?\r\nend;\r\n)(?=\r\nfunction StrictArgumentBoolean\()' 'ArgumentBoolean'
$requirePermission = Extract-One '(?<body>procedure RequirePermission\(.*?\r\nend;\r\n)(?=\r\nprocedure RequireFileReadPermission\()' 'RequirePermission'
$readPermission = Extract-One '(?<body>procedure RequireFileReadPermission\(.*?\r\nend;\r\n)(?=\r\nprocedure EnsureDebuggerIdle;)' 'read permission classifier'
$argumentInteger = Extract-One '(?<body>function ArgumentInteger\(.*?\r\nend;\r\n)(?=\r\nfunction DirectoryFilesResult\()' 'ArgumentInteger'
$fileRead = Extract-One "(?<body>  if SameText\(AName, 'file_read'\) or SameText\(AName, 'reference_file_read'\) then\r\n.*?)(?=  if SameText\(AName, 'code_insight_status'\) then)" 'file_read branch'
$fileWrite = Extract-One "(?<body>  if SameText\(AName, 'file_write'\) then\r\n.*?)(?=  if SameText\(AName, 'project_create'\) then)" 'file_write branch'
$projectCreate = Extract-One "(?<body>  if SameText\(AName, 'project_create'\) then\r\n.*?)(?=  if SameText\(AName, 'project_open'\) then)" 'project_create branch'
$projectOpen = Extract-One "(?<body>  if SameText\(AName, 'project_open'\) then\r\n.*?)(?=  if SameText\(AName, 'project_save'\) then)" 'project_open branch'
$header = @'
unit DAI.PermissionRouting.ProductionBranch;

{$IF CompilerVersion >= 36.0}
{$TEXTBLOCK CRLF JSON}
{$IFEND}

interface

uses System.JSON, h5u.DAI.Types;

type
  TDAIMCPTools = class
    class function ListTools: TJSONArray; static;
  end;

function ResolveValidatedArguments(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TDAIRequestContext;
function DispatchProjectMutation(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;

implementation

uses System.IOUtils, System.SysUtils, ToolsAPI, h5u.DAI.OTA.Files, h5u.DAI.OTA.Helpers, h5u.DAI.OTA.Projects,
  h5u.DAI.Permissions.Manager, h5u.DAI.Settings;
'@
$wrapper = @'
function ResolveValidatedArguments(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TDAIRequestContext;
begin
  ValidateToolArguments(AName, AArguments);
  Result := ContextForArguments(AArguments, AContext);
end;

function DispatchProjectMutation(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
  LContext: TDAIRequestContext;
  LFileName: string;
  LUsedEditorBuffer: Boolean;
begin
  ValidateToolArguments(AName, AArguments);
  LContext := ContextForArguments(AArguments, AContext);
'@
$footer = @'
  raise EArgumentException.Create('This isolated fixture only exposes project_create, project_open and file_write.');
end;

end.
'@
$generated = ($header -replace '\r?\n', $crlf) + $crlf + $crlf + $jsonObject + $crlf + $addTool + $crlf +
    $argumentString + $crlf + $argumentBoolean + $crlf + $argumentInteger + $crlf + $validator + $crlf +
    $requirePermission + $crlf + $readPermission + $crlf + $resolver + $crlf +
    $directorySchema + $crlf + $catalog + $crlf + ($wrapper -replace '\r?\n', $crlf) + $crlf +
    $fileRead + $fileWrite + $projectCreate + $projectOpen + ($footer -replace '\r?\n', $crlf) + $crlf
foreach ($region in @($jsonObject, $addTool, $argumentString, $argumentBoolean, $validator, $requirePermission, $resolver,
        $directorySchema, $catalog, $readPermission, $argumentInteger, $fileRead, $fileWrite, $projectCreate, $projectOpen)) {
    if (-not $generated.Contains($region)) {
        throw 'Extracted production logic must remain byte-for-byte unchanged.'
    }
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.PermissionRouting.ProductionBranch.pas'), $generated, $utf8Bom)
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$manifest = '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security></trustInfo></assembly>'
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'dai-test-as-invoker.manifest'), $manifest, [Text.Encoding]::ASCII)
$resourceScript = Join-Path $generatedDirectory 'dai-test-as-invoker.rc'
[IO.File]::WriteAllText($resourceScript, '1 24 "dai-test-as-invoker.manifest"', [Text.Encoding]::ASCII)
Push-Location -LiteralPath $generatedDirectory
try {
    & (Join-Path $BdsRoot 'bin\brcc32.exe') '-fodai-test-as-invoker.res' $resourceScript
    if ($LASTEXITCODE -ne 0) {
        throw 'The isolated test manifest failed to compile.'
    }
}
finally {
    Pop-Location
}
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-PermissionRouting-$currentPlatform"
    $dcuDirectory = $outputDirectory + '-Dcu'
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    & $compiler '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" "-R$generatedDirectory" `
        "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory" (Join-Path $PSScriptRoot 'Test.PermissionRouting.dpr')
    if ($LASTEXITCODE -ne 0) {
        throw "Permission routing test $currentPlatform failed to compile: $LASTEXITCODE"
    }
    & (Join-Path $outputDirectory 'Test.PermissionRouting.exe')
    if ($LASTEXITCODE -ne 0) {
        throw "Permission routing test $currentPlatform failed: $LASTEXITCODE"
    }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production source changed during testing; rerun the production-branch tests.'
}
