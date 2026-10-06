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
$fixtureDirectory = Join-Path $PSScriptRoot 'DesignerDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests\DesignerDispatch\ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"
$toolNames = @('form_components_search', 'form_components_select', 'form_component_properties',
    'form_component_set_property', 'form_component_move', 'form_component_create', 'form_palette_list')
function Extract-One([string]$pattern, [string]$description, [string]$content = $sourceText) {
    $found = [regex]::Matches($content, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($found.Count -ne 1) { throw "Expected one production $description; found $($found.Count)." }
    return $found[0].Groups['body'].Value
}
# The production parsers, branches and schemas are kept verbatim. Only final OTA
# services and permission authority are stubbed; project-context inference is outside this fixture.
$helpers = @()
foreach ($name in @('JsonObjectFromText', 'AddTool', 'StrictArgumentString', 'RequiredArgumentString',
    'StrictArgumentStringArray', 'StrictArgumentInteger', 'StrictArgumentBoolean', 'ValidateDesignerNumber',
    'ValidateDesignerArguments', 'RequirePermission')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $name\(.*?^end;\r?\n)" $name
}
$dispatchSource = $sourceText.Substring($sourceText.IndexOf('class function TDAIMCPTools.CallTool('))
$branches = @(
    (Extract-One "(?<body>^  if SameText\(AName, 'form_palette_list'\) then\r?\n.*?^  end;\r?\n)" 'palette branch' $dispatchSource),
    (Extract-One "(?<body>^  if SameText\(AName, 'form_components_search'\) or SameText.*?^  end;\r?\n)" 'component branches' $dispatchSource)
)
$schemas = @()
foreach ($name in $toolNames) {
    $schemas += Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$name',.*?\);\r?\n)" "$name schema"
}
$header = @'
unit DAI.DesignerDispatch.ProductionBranch;
interface
uses System.JSON, h5u.DAI.Types;
function DispatchDesigner(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
function ListDesignerSchemas: TJSONArray;
implementation
uses System.Classes, System.SysUtils, System.Math, h5u.DAI.OTA.Designer, h5u.DAI.OTA.Palette, h5u.DAI.Permissions.Manager;
'@
$dispatch = @'
function DispatchDesigner(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
  LFileName: string;
  LContext: TDAIRequestContext;
begin
  LContext := AContext;
'@
$listStart = @'
  raise EArgumentException.Create('This fixture exposes only designer tools.');
end;
function ListDesignerSchemas: TJSONArray;
begin
  Result := TJSONArray.Create;
'@
$generatedText = ($header -replace '\r?\n', $crlf) + $crlf + ($helpers -join $crlf) + $crlf +
    ($dispatch -replace '\r?\n', $crlf) + $crlf + ($branches -join $crlf) + $crlf +
    ($listStart -replace '\r?\n', $crlf) + $crlf + ($schemas -join $crlf) + "end;$crlf" + "end.$crlf"
foreach ($region in @($helpers) + @($branches) + @($schemas)) {
    if (-not $generatedText.Contains($region)) { throw 'An extracted production region was changed.' }
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.DesignerDispatch.ProductionBranch.pas'), $generatedText, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)
$resourceOutput = Join-Path $generatedDirectory 'dai-test-as-invoker.res'
$resourceScript = Join-Path $generatedDirectory 'dai-test-as-invoker.rc'
[IO.File]::WriteAllText($resourceScript, [IO.File]::ReadAllText((Join-Path $fixtureDirectory 'dai-test-as-invoker.rc')), [Text.Encoding]::ASCII)
Push-Location -LiteralPath $fixtureDirectory
try {
    & (Join-Path $BdsRoot 'bin\brcc32.exe') "-fo$resourceOutput" $resourceScript
    if ($LASTEXITCODE -ne 0) { throw 'The asInvoker test resource failed to compile.' }
}
finally { Pop-Location }
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests\DesignerDispatch\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    & (Join-Path $BdsRoot "bin\$compilerName") '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" `
        "-I$generatedDirectory" "-R$generatedDirectory" "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory" `
        (Join-Path $PSScriptRoot 'Test.DesignerDispatch.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Designer dispatch $currentPlatform failed to compile." }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $outputDirectory 'Test.DesignerDispatch.exe'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $testOutput = $process.StandardOutput.ReadToEnd()
        $testError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Write-Output "$currentPlatform $($testOutput.TrimEnd())"
        if ($process.ExitCode -ne 0 -or -not $testOutput.Contains('PASS DesignerDispatch:')) {
            throw "Designer dispatch $currentPlatform failed. $testError"
        }
    }
    finally { $process.Dispose() }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production MCP changed during tests; rerun.'
}
