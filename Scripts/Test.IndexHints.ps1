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
$fixtureDirectory = Join-Path $PSScriptRoot 'IndexHintsTests'
$generatedDirectory = Join-Path $projectRoot 'Build\Tests-IndexHints-ProductionBranch'
$utf8Bom = [Text.UTF8Encoding]::new($true)
$crlf = [string][char]13 + [char]10

function Extract-One([string]$pattern, [string]$description) {
    $found = [regex]::Matches($sourceText, $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($found.Count -ne 1) {
        throw "Expected exactly one production $description; found $($found.Count)."
    }
    return $found[0].Groups['body'].Value
}

# Compile the real complete status builder, both metadata dispatch branches and
# fail-soft hint helpers. Only external state/services are in-memory doubles.
# The fixture has no SQLite/registry/IDE/transport dependencies or index writer.
$helpers = @()
foreach ($helper in @('RequirePermission', 'AddIndexContext', 'AddProjectIndexSummaries', 'ToolStatus')) {
    $helpers += Extract-One "(?<body>^(?:function|procedure) $helper\(.*?^end;\r\n)" $helper
}
$branches = @()
foreach ($tool in @('ide_status', 'projects_list')) {
    $branches += Extract-One "(?<body>^  if SameText\(AName, '$tool'\) then\r\n.*?^  end;\r\n)" "$tool branch"
}
$header = @'
unit DAI.IndexHints.ProductionBranch;
interface
uses System.JSON, h5u.DAI.Types;
function DispatchMetadata(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
implementation
uses System.IOUtils, System.SysUtils, Winapi.Windows, h5u.DAI.Consts, h5u.DAI.Lifecycle.Policy,
  h5u.DAI.Runtime, h5u.DAI.OTA.Files, h5u.DAI.OTA.Helpers, h5u.DAI.Permissions.Manager,
  h5u.DAI.Settings, h5u.DAI.Symbols.Service;
'@
$wrapper = @'
function DispatchMetadata(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
  LContext: TDAIRequestContext;
begin
  LContext := AContext;
'@
$footer = @'
  raise EArgumentException.Create('This isolated fixture exposes ide_status and projects_list.');
end;
end.
'@
$generated = ($header -replace '\r?\n', $crlf) + $crlf + ($helpers -join $crlf) + $crlf +
    ($wrapper -replace '\r?\n', $crlf) + $crlf + ($branches -join $crlf) + $crlf + ($footer -replace '\r?\n', $crlf) + $crlf
foreach ($region in @($helpers) + @($branches)) {
    if (-not $generated.Contains($region)) {
        throw 'Every extracted production region must appear unchanged in the generated fixture.'
    }
}
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'DAI.IndexHints.ProductionBranch.pas'), $generated, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $generatedDirectory 'production-source.sha256'), "$sourceHash  $sourcePath$crlf", $utf8Bom)
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $outputDirectory = Join-Path $projectRoot "Build\Tests-IndexHints-$currentPlatform"
    $dcuDirectory = $outputDirectory + '-Dcu'
    New-Item -ItemType Directory -Force -Path $outputDirectory, $dcuDirectory | Out-Null
    $compilerName = if ($currentPlatform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
    $libraryDirectory = Join-Path $BdsRoot "lib\$currentPlatform\release"
    $compilerArguments = @('-B', '-Q', '-$B+', '-$Q+', '-$R+', "-E$outputDirectory", "-N0$dcuDirectory",
        "-U$generatedDirectory;$fixtureDirectory;$sourceDirectory;$libraryDirectory", (Join-Path $PSScriptRoot 'Test.IndexHints.dpr'))
    & (Join-Path $BdsRoot "bin\$compilerName") @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "Index-hint tests failed to compile for $currentPlatform ($LASTEXITCODE)." }
    & (Join-Path $outputDirectory 'Test.IndexHints.exe')
    if ($LASTEXITCODE -ne 0) { throw "Index-hint tests failed for $currentPlatform ($LASTEXITCODE)." }
}
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Production source changed during the extracted-source test; rerun against the final source.'
}
