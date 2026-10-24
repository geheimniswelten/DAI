program TestToolUsage;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.RegularExpressions,
  System.SysUtils,
  h5u.DAI.MCP.ToolUsage;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure ExpectUsage(const AName, AJSON: string; const AExpectedActivity: Boolean);
var
  LActivity: Boolean;
  LArguments: TJSONObject;
  LBefore, LCanonical: string;
begin
  LArguments := nil;
  if AJSON <> '' then
    LArguments := TJSONObject(TJSONObject.ParseJSONValue(AJSON));
  try
    LBefore := '';
    if Assigned(LArguments) then
      LBefore := LArguments.ToJSON;
    LCanonical := 'previous';
    LActivity := not AExpectedActivity;
    Check(TDAIMCPToolUsage.TryClassify(AName, LArguments, LCanonical, LActivity), 'known tool: ' + AName);
    Check(LCanonical = LowerCase(AName), 'canonical name: ' + AName);
    Check(LActivity = AExpectedActivity, 'activity classification: ' + AName + ' ' + AJSON);
    if Assigned(LArguments) then
      Check(LArguments.ToJSON = LBefore, 'classification preserves arguments: ' + AName);
  finally
    LArguments.Free;
  end;
end;

procedure ExpectUnknown(const AName: string);
var
  LActivity: Boolean;
  LCanonical: string;
begin
  LCanonical := 'previous';
  LActivity := True;
  Check(not TDAIMCPToolUsage.TryClassify(AName, nil, LCanonical, LActivity), 'unknown name rejected');
  Check(LCanonical = '', 'unknown name leaves no persistent key');
  Check(not LActivity, 'unknown name does not show activity');
end;

function IsQuietDefault(const AName: string): Boolean;
const
  CQuietNames: array[0..13] of string = (
    'clients_registration_status', 'code_insight_status', 'codex_registration_status', 'debugger_status',
    'directory_files_list', 'ide_status', 'open_files_list', 'package_is_installed', 'project_directory_files_list',
    'project_files_list', 'project_options_configurations', 'projects_list', 'reference_files_list', 'reference_roots_list'
  );
var
  LName: string;
begin
  for LName in CQuietNames do
    if AName = LName then
      Exit(True);
  Result := False;
end;

procedure CatalogChecks(const AToolsSource, AUsageSource: string);
var
  LActivity: Boolean;
  LCanonical, LName: string;
  LCatalog, LDefinitions: TStringList;
  LMatch: TMatch;
  LMatches: TMatchCollection;
  LIndex: Integer;
begin
  LCatalog := TStringList.Create;
  LDefinitions := TStringList.Create;
  try
    LCatalog.Sorted := True;
    LDefinitions.Sorted := True;
    LMatches := TRegEx.Matches(TFile.ReadAllText(AToolsSource), 'AddTool\(\s*Result,\s*''([^'']+)''');
    for LMatch in LMatches do
    begin
      LName := LMatch.Groups[1].Value;
      Check(LCatalog.IndexOf(LName) = -1, 'production catalog has unique name: ' + LName);
      LCatalog.Add(LName);
      ExpectUsage(LName, '', not IsQuietDefault(LName));
      ExpectUsage(UpperCase(LName), '{}', not IsQuietDefault(LName));
      ExpectUnknown(' ' + LName);
      ExpectUnknown(LName + ' ');
    end;
    Check(LCatalog.Count > 0, 'production tool catalog was discovered');
    LMatches := TRegEx.Matches(TFile.ReadAllText(AUsageSource), 'Name:\s*''([^'']+)''');
    for LMatch in LMatches do
    begin
      LName := LMatch.Groups[1].Value;
      Check(LDefinitions.IndexOf(LName) = -1, 'usage catalog has unique name: ' + LName);
      LDefinitions.Add(LName);
    end;
    Check(LDefinitions.Count = LCatalog.Count, 'usage catalog covers production exactly');
    for LIndex := 0 to LCatalog.Count - 1 do
      Check(LDefinitions[LIndex] = LCatalog[LIndex], 'no missing or invented usage name: ' + LCatalog[LIndex]);
    LCanonical := 'previous';
    LActivity := True;
    Check(not TDAIMCPToolUsage.TryClassify('tools/list', nil, LCanonical, LActivity), 'MCP method is not a tool');
  finally
    LDefinitions.Free;
    LCatalog.Free;
  end;
end;

procedure ArgumentChecks;
const
  CDirectoryNames: array[0..2] of string = ('directory_files_list', 'project_directory_files_list', 'reference_files_list');
var
  LName: string;
begin
  for LName in CDirectoryNames do
  begin
    ExpectUsage(LName, '{}', False);
    ExpectUsage(LName, '{"filename_regex":".*\\.pas","recursive":true}', False);
    ExpectUsage(LName, '{"content_query":""}', False);
    ExpectUsage(LName, '{"content_query":" "}', True);
    ExpectUsage(LName, '{"content_query":"\t"}', True);
    ExpectUsage(LName, '{"content_query":" TCustomer "}', True);
    ExpectUsage(LName, '{"content_query":"日本語","content_use_regex":true}', True);
    ExpectUsage(LName, '{"content_query":true}', False);
    ExpectUsage(LName, '{"content_query":null}', False);
  end;
  ExpectUsage('project_context', '{}', True);
  ExpectUsage('project_context', '{"include_compiler_options":true}', True);
  ExpectUsage('project_context', '{"include_compiler_options":false}', False);
  ExpectUsage('project_context', '{"include_compiler_options":"FALSE"}', False);
  ExpectUsage('project_context', '{"include_compiler_options":null}', True);
  ExpectUsage('project_context', '{"include_compiler_options":42}', True);
  ExpectUsage('project_context', '{"include_compiler_options":{},"include_files":true}', True);
  ExpectUsage('project_context', '{"include_compiler_options":false,"include_files":true}', False);
  ExpectUsage('options_open', '{"request_id":"previous-request"}', True);
  ExpectUsage('debugger_evaluation_status', '{"request_id":"previous-request"}', True);
  ExpectUsage('file_read', '{"file":"example.pas"}', True);
  ExpectUsage('project_options_read', '{}', True);
  ExpectUnknown('');
  ExpectUnknown('initialize');
  ExpectUnknown('ping');
  ExpectUnknown('tools/call');
  ExpectUnknown('file_read\\OtherRegistryKey');
  ExpectUnknown('file_read' + #0 + 'suffix');
  ExpectUnknown('file_read' + #13#10);
  ExpectUnknown(StringOfChar('x', 100000));
end;

begin
  try
    if ParamCount <> 2 then
      raise Exception.Create('Expected production Tools.pas and ToolUsage.pas paths.');
    CatalogChecks(ParamStr(1), ParamStr(2));
    ArgumentChecks;
    Writeln('PASS: ', CheckCount, ' tool-usage checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
