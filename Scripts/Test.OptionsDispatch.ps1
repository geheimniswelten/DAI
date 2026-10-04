[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')][string]$Platform = 'Both',
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
$fixtureDirectory = Join-Path $PSScriptRoot 'OptionsDispatchTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests\OptionsDispatch\ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = "`r`n"
$toolNames = @('options_search', 'options_open')

function Extract-One([string]$pattern, [string]$description) {
    $matchesFound = [regex]::Matches($sourceText, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($matchesFound.Count -ne 1) {
        throw "Expected exactly one production $description; found $($matchesFound.Count)."
    }
    return $matchesFound[0].Groups['body'].Value
}

# Copy the actual production helpers, branch, local declarations and schemas verbatim.
# Only the permission authority and final options services are replaced. Initial transport
# context inference is outside this test; the branch receives a captured request context.
$helpers = @()
foreach ($helperName in @('JsonObjectFromText', 'AddTool', 'StrictArgumentString', 'RequiredArgumentString', 'StrictArgumentInteger', 'RequirePermission')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $helperName\(.*?^end;\r\n)" $helperName
}
$branches = @()
$schemas = @()
foreach ($toolName in $toolNames) {
    $branches += Extract-One "(?<body>^  if SameText\(AName, '$toolName'\) then\r\n.*?^  end;\r\n)" "$toolName branch"
}
$branchText = $branches -join $crlf
$schemas = @()
foreach ($toolName in $toolNames) {
    $schemas += Extract-One "(?<body>^  AddTool\(\s*Result,\s*'$toolName',.*?\);\r\n)" "$toolName schema"
    if (-not $branchText.Contains("'$toolName'")) {
        throw "The actual extracted dispatch must expose $toolName."
    }
}
$callHeader = Extract-One '(?<body>^class function TDAIMCPTools\.CallTool\(.*?\r\nvar\r\n.*?)(?=\r\nbegin\r\n)' 'CallTool declarations'
$localDeclarations = @()
foreach ($local in [regex]::Matches($callHeader, '(?m)^  (?<names>L\w+(?:, L\w+)*): (?<type>[^;]+);\r?$')) {
    $used = $false
    foreach ($localName in $local.Groups['names'].Value.Split(',').Trim()) {
        if ($localName -eq 'LContext' -or [regex]::IsMatch($branchText, "\b$localName\b")) { $used = $true }
    }
    if ($used) { $localDeclarations += $local.Value.TrimEnd("`r") }
}
if (-not ($localDeclarations -join $crlf).Contains('LNavigationRequest: TDAIOptionsNavigationRequest;')) {
    throw 'Production options navigation request declaration is missing.'
}
$header = @'
unit DAI.OptionsDispatch.ProductionBranch;

interface

uses System.JSON, h5u.DAI.Types;

function DispatchOptions(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
function ListOptionsSchemas: TJSONArray;

implementation

uses System.SysUtils, h5u.DAI.Options.Search, h5u.DAI.Options.Navigation, h5u.DAI.Permissions.Manager;

'@
$dispatchStart = @'
function DispatchOptions(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
'@
$dispatchBody = @'
begin
  LContext := AContext;

'@
$dispatchEnd = @'
  raise EArgumentException.Create('This isolated fixture exposes only options tools.');
end;

function ListOptionsSchemas: TJSONArray;
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
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.OptionsDispatch.ProductionBranch.pas'), $generatedText, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)

# The plan record also comes from production, preventing fixture/implementation drift.
$targetPath = Join-Path $sourceDirectory 'h5u.DAI.Options.Navigation.pas'
$targetSource = [IO.File]::ReadAllText($targetPath)
$targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
$targetMatches = [regex]::Matches($targetSource, '(?ms)^  TDAIOptionsNavigationRequest = record\r\n.*?^  end;\r\n')
if ($targetMatches.Count -ne 1) { throw 'Expected exactly one production options navigation request record.' }
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.OptionsDispatch.Request.inc'), $targetMatches[0].Value, $utf8Bom)

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
    $outputDirectory = Join-Path $projectRoot "Build\Tests\OptionsDispatch\$currentPlatform"
    $dcuDirectory = Join-Path $outputDirectory 'Dcu'
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $compiler = Join-Path $BdsRoot "bin\$compilerName"
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    & $compiler '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$outputDirectory" "-N0$dcuDirectory" "-R$generatedDirectory" `
        "-I$generatedDirectory" "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory" `
        (Join-Path $PSScriptRoot 'Test.OptionsDispatch.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Package dispatch test for $currentPlatform failed to compile." }
    $testInfo = [Diagnostics.ProcessStartInfo]::new()
    $testInfo.FileName = Join-Path $outputDirectory 'Test.OptionsDispatch.exe'
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
        if ($testProcess.ExitCode -ne 0 -or -not $testOutput.Contains('PASS OptionsDispatch:')) {
            throw "Package dispatch test for $currentPlatform failed. $testError"
        }
    }
    finally { $testProcess.Dispose() }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash -or
    (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ne $targetHash) {
    throw 'Production source changed during testing; rerun against the updated source.'
}
