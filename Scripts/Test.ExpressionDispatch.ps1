[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')][string]$Platform = 'Both',
    [string]$BdsRoot = $env:BDS
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($BdsRoot)) { $BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $projectRoot 'Source'
$sourcePath = Join-Path $sourceDirectory 'h5u.DAI.MCP.Tools.pas'
$sourceText = [IO.File]::ReadAllText($sourcePath)
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$fixtureDirectory = Join-Path $PSScriptRoot 'ExpressionDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests-ExpressionDispatch-ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"
$toolNames = @('debugger_cursor_expression', 'debugger_evaluate', 'debugger_modify', 'debugger_evaluation_status', 'debugger_expression_ui')
function Extract-One([string]$pattern, [string]$description) {
    $matchesFound = [regex]::Matches($sourceText, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($matchesFound.Count -ne 1) { throw "Expected one production $description; found $($matchesFound.Count)." }
    return $matchesFound[0].Groups['body'].Value
}
# Keep production parsing, context binding, dispatch and schemas unchanged.
# Replace only final SDK services, permission authority and transport context inference.
$helpers = @()
foreach ($helperName in @('JsonObjectFromText', 'AddTool', 'StrictArgumentString', 'RequiredArgumentString',
    'StrictArgumentInteger', 'StrictArgumentBoolean', 'ArgumentUInt32', 'RequirePermission', 'CursorFileContext', 'EvaluationArguments')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $helperName\(.*?^end;\r?\n)" $helperName
}
$branches = @()
foreach ($toolName in @('debugger_cursor_expression', 'debugger_evaluation_status', 'debugger_expression_ui')) {
    $branches += Extract-One "(?<body>^  if SameText\(AName, '$toolName'\) then\r?\n.*?^  end;\r?\n)" "$toolName branch"
}
$branches += Extract-One "(?<body>^  if SameText\(AName, 'debugger_evaluate'\) or SameText\(AName, 'debugger_modify'\) then\r?\n.*?^  end;\r?\n)" 'evaluate/modify branch'
$branchText = $branches -join $crlf
$schemas = @()
foreach ($toolName in $toolNames) {
    $schemas += Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$toolName',.*?\);\r?\n)" "$toolName schema"
    if (-not $branchText.Contains("'$toolName'")) { throw "Actual dispatch does not expose $toolName." }
}
$callHeader = Extract-One '(?<body>^class function TDAIMCPTools\.CallTool\(.*?\r?\nvar\r?\n.*?)(?=\r?\nbegin\r?\n)' 'CallTool declarations'
$localDeclarations = @()
foreach ($local in [regex]::Matches($callHeader, '(?m)^  (?<names>L\w+(?:, L\w+)*): (?<type>[^;]+);\r?$')) {
    $used = $false
    foreach ($localName in $local.Groups['names'].Value.Split(',').Trim()) {
        if ($localName -eq 'LContext' -or [regex]::IsMatch($branchText, "\b$localName\b")) { $used = $true }
    }
    if ($used) { $localDeclarations += $local.Value.TrimEnd("`r") }
}
$header = @'
unit DAI.ExpressionDispatch.ProductionBranch;
interface
uses System.JSON, h5u.DAI.Types;
function DispatchExpression(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
function ListExpressionSchemas: TJSONArray;
implementation
uses System.Classes, System.SysUtils, h5u.DAI.OTA.CursorExpression, h5u.DAI.OTA.Evaluation, h5u.DAI.OTA.ExpressionUI,
  h5u.DAI.Permissions.Manager, DAI.ExpressionDispatch.TestState;
function ContextForArguments(const AArguments: TJSONObject; const AContext: TDAIRequestContext): TDAIRequestContext;
begin Result := ResolveArgumentsContext(AArguments, AContext); end;
'@
$dispatchStart = @'
function DispatchExpression(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
'@
$dispatchBody = @'
begin
  LContext := ContextForArguments(AArguments, AContext);
'@
$dispatchEnd = @'
  raise EArgumentException.Create('This isolated fixture exposes only expression tools.');
end;
function ListExpressionSchemas: TJSONArray;
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
foreach ($region in @($helpers) + @($branchText) + @($schemas)) {
    if (-not $generatedText.Contains($region)) { throw 'An extracted production region was changed.' }
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.ExpressionDispatch.ProductionBranch.pas'), $generatedText, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)
$recordHashes = @{}
foreach ($record in @(@('h5u.DAI.OTA.Evaluation.pas', 'TDAIEvaluationRequest', 'Evaluation'),
    @('h5u.DAI.OTA.ExpressionUI.pas', 'TDAIExpressionUIRequest', 'UI'))) {
    $recordPath = Join-Path $sourceDirectory $record[0]
    $recordSource = [IO.File]::ReadAllText($recordPath)
    $recordHashes[$recordPath] = (Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash
    $recordMatches = [regex]::Matches($recordSource, "(?ms)^  $($record[1]) = record\r?\n.*?^  end;\r?\n")
    if ($recordMatches.Count -ne 1) { throw "Expected one production $($record[1]) record." }
    [IO.File]::WriteAllText((Join-Path $generatedDirectory "DAI.ExpressionDispatch.$($record[2]).inc"), $recordMatches[0].Value, $utf8Bom)
}
$resourceCompiler = Join-Path $BdsRoot 'bin\brcc32.exe'
$resourceOutput = Join-Path $generatedDirectory 'dai-test-as-invoker.res'
$resourceScript = Join-Path $generatedDirectory 'dai-test-as-invoker.rc'
[IO.File]::WriteAllText($resourceScript, [IO.File]::ReadAllText((Join-Path $fixtureDirectory 'dai-test-as-invoker.rc')), [Text.Encoding]::ASCII)
Push-Location -LiteralPath $fixtureDirectory
try {
    & $resourceCompiler "-fo$resourceOutput" $resourceScript
    if ($LASTEXITCODE -ne 0) { throw 'The asInvoker test resource failed to compile.' }
}
finally { Pop-Location }
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-ExpressionDispatch-$currentPlatform"
    $dcuDirectory = ($outputDirectory + '-Dcu')
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    & $compiler '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" "-I$generatedDirectory" "-R$generatedDirectory" `
        "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory" (Join-Path $PSScriptRoot 'Test.ExpressionDispatch.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Expression dispatch test $currentPlatform failed to compile." }
    $testInfo = [Diagnostics.ProcessStartInfo]::new()
    $testInfo.FileName = Join-Path $outputDirectory 'Test.ExpressionDispatch.exe'
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
        if ($testProcess.ExitCode -ne 0 -or -not $testOutput.Contains('PASS ExpressionDispatch:')) {
            throw "Expression dispatch test $currentPlatform failed. $testError"
        }
    }
    finally { $testProcess.Dispose() }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Production MCP changed during tests; rerun.' }
foreach ($recordPath in $recordHashes.Keys) {
    if ((Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash -ne $recordHashes[$recordPath]) {
        throw "Production $recordPath changed during tests; rerun."
    }
}
