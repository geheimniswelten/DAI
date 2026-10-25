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
$fixtureDirectory = Join-Path $PSScriptRoot 'SymbolsDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests-SymbolDispatch-ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"
$toolNames = @('ide_ai_status', 'project_index_status', 'project_index_build', 'project_index_delete', 'symbols_search', 'symbols_query')

function Extract-One([string]$pattern, [string]$description) {
    $found = [regex]::Matches($sourceText, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($found.Count -ne 1) {
        throw "Expected exactly one production $description; found $($found.Count)."
    }
    return $found[0].Groups['body'].Value
}

# Only the permission authority and final index service are replaced. Permission
# traversal, argument handling, service dispatch and schemas are production text.
$helpers = @()
foreach ($helper in @('JsonObjectFromText', 'AddTool', 'StrictArgumentString', 'RequiredArgumentString',
        'ArgumentInteger', 'RequirePermission', 'RequireIndexAccess')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $helper\(.*?^end;\r\n)" $helper
}
$branches = @()
foreach ($tool in @('ide_ai_status', 'project_index_status')) {
    $branches += Extract-One "(?<body>^  if SameText\(AName, '$tool'\) then\r\n.*?^  end;\r\n)" "$tool branch"
}
$branches += Extract-One "(?<body>^  if SameText\(AName, 'project_index_build'\).*?^  end;\r\n)" 'shared index branch'
$schemas = @()
foreach ($tool in $toolNames) {
    $schemas += Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$tool',.*?\);\r\n)" "$tool schema"
}
$header = @'
unit DAI.SymbolDispatch.ProductionBranch;
interface
uses System.JSON, h5u.DAI.Types;
function DispatchSymbols(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
function ListSymbolSchemas: TJSONArray;
implementation
uses System.Classes, System.SysUtils, h5u.DAI.Symbols.Service, h5u.DAI.Permissions.Manager;
'@
$dispatchStart = @'
function DispatchSymbols(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
  LContext: TDAIRequestContext;
  LIndexScope, LIndexIdentity, LRequestId: string;
  LIndexParameters: TJSONObject;
begin
  LContext := AContext;
'@
$dispatchEnd = @'
  raise EArgumentException.Create('This fixture exposes only the six symbol-index tools.');
end;
function ListSymbolSchemas: TJSONArray;
begin
  Result := TJSONArray.Create;
'@
$footer = "end;$crlf$crlf" + "end.$crlf"
$generatedText = ($header -replace '\r?\n', $crlf) + $crlf + ($helpers -join $crlf) + $crlf +
    ($dispatchStart -replace '\r?\n', $crlf) + $crlf + ($branches -join $crlf) + $crlf +
    ($dispatchEnd -replace '\r?\n', $crlf) + $crlf + ($schemas -join $crlf) + $footer
foreach ($region in @($helpers) + @($branches) + @($schemas)) {
    if (-not $generatedText.Contains($region)) {
        throw 'Every extracted production region must appear unchanged in the generated fixture.'
    }
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.SymbolDispatch.ProductionBranch.pas'), $generatedText, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)
$resourceOutput = Join-Path $generatedDirectory 'dai-test-as-invoker.res'
Push-Location -LiteralPath $fixtureDirectory
try {
    & (Join-Path $BdsRoot 'bin\brcc32.exe') "-fo$resourceOutput" 'dai-test-as-invoker.rc'
    if ($LASTEXITCODE -ne 0) { throw 'The asInvoker test manifest failed to compile.' }
}
finally { Pop-Location }
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-SymbolDispatch-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerArguments = @('-B', '-Q', '-$B+', '-$Q+', '-$R+', "-E$outputDirectory", "-N0$dcuDirectory", "-R$generatedDirectory",
        "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory", (Join-Path $PSScriptRoot 'Test.SymbolDispatch.dpr'))
    & (Join-Path $BdsRoot "bin\$compilerName") @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "Symbol dispatch test for $currentPlatform failed to compile (exit code $LASTEXITCODE)." }
    & (Join-Path $outputDirectory 'Test.SymbolDispatch.exe')
    if ($LASTEXITCODE -ne 0) { throw "Symbol dispatch test for $currentPlatform failed (exit code $LASTEXITCODE)." }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production source changed during the extracted-branch test; rerun against the new source.'
}
