program Test.ProjectTools;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.JSON, System.Generics.Collections, Vcl.Forms,
  DAI.ProjectTools.IndependentAPI,
  h5u.DAI.ProjectTools, h5u.DAI.OTA.Helpers;
const
  CProject = 'C:\Workspace\Main.dproj';
  CTools = '[{"name":"lookup","description":"Read a cached value","inputSchema":{"type":"object",' +
    '"properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}}]';
type
  TProvider = class(TComponent)
  public
    Info, Tools, Response: string;
    ProjectSupported: Boolean;
    SupportCalls, InfoCalls, ToolCalls, Calls: Integer;
    LastProject, LastTool, LastArguments: string;
    constructor Create(AOwner: TComponent); override;
    procedure RequireDispatch;
    function GetInfoJSON: string; stdcall;
    function SupportsProject(const AProjectFile: string): Boolean; stdcall;
    function GetToolsJSON(const AProjectFile: string): string; stdcall;
    function CallToolJSON(const AProjectFile, AToolName, AArgumentsJSON: string): string; stdcall;
  end;

  TProviderV1 = class(TProvider, DAI.ProjectTools.IndependentAPI.IDAIMCPReadOnlyExtensionV1)
  end;

  TProviderV2 = class(TProvider, DAI.ProjectTools.IndependentAPI.IDAIMCPProjectExtensionV2)
  end;
var
  Checks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then raise EInvalidOperation.Create(AMessage);
end;

constructor TProvider.Create(AOwner: TComponent);
begin
  inherited;
  Info := '{"id":"sample","title":"Sample cache","instructions":"Look up existing values first."}';
  Tools := CTools;
  Response := '{"status":"ok","value":"example"}';
  ProjectSupported := True;
end;

procedure TProvider.RequireDispatch;
begin Check(TestDispatchDepth > 0, 'Provider callback outside host main-thread block.'); end;
function TProvider.GetInfoJSON: string;
begin RequireDispatch; Inc(InfoCalls); Result := Info; end;
function TProvider.SupportsProject(const AProjectFile: string): Boolean;
begin
  RequireDispatch; Inc(SupportCalls); LastProject := AProjectFile;
  Result := ProjectSupported and SameText(AProjectFile, CProject);
end;
function TProvider.GetToolsJSON(const AProjectFile: string): string;
begin RequireDispatch; Inc(ToolCalls); LastProject := AProjectFile; Result := Tools; end;
function TProvider.CallToolJSON(const AProjectFile, AToolName, AArgumentsJSON: string): string;
begin
  RequireDispatch; Inc(Calls);
  LastProject := AProjectFile; LastTool := AToolName; LastArguments := AArgumentsJSON;
  Result := Response;
end;

procedure ExpectFailure(const AAction: TProc; const AReason: string);
var Failed: Boolean;
begin
  Failed := False;
  try AAction(); except on E: Exception do Failed := True; end;
  Check(Failed, AReason);
end;

procedure List;
var Result: TJSONObject;
begin Result := TDAIProjectTools.ListTools(CProject); Result.Free; end;

procedure Call(const AExtension, ATool, AJSON: string; const AAuthorizeWrite: TProc = nil);
var Args, Response: TJSONObject;
begin
  Args := TJSONObject.ParseJSONValue(AJSON) as TJSONObject;
  try
    Response := TDAIProjectTools.CallTool(CProject, AExtension, ATool, Args, AAuthorizeWrite);
    Response.Free;
  finally Args.Free; end;
end;

procedure TestDiscoveryAndLifecycle;
var
  Provider, Hidden, Nested: TProvider;
  Owner: TComponent;
  Result, Info, Tool: TJSONObject;
  Extensions, Tools: TJSONArray;
begin
  Result := TDAIProjectTools.ListTools(CProject);
  try Check(Result.GetValue<TJSONArray>('extensions').Count = 0, 'Empty host has no fabricated extensions.'); finally Result.Free; end;
  Owner := TComponent.Create(Application);
  Nested := TProviderV1.Create(Owner);
  Hidden := TProviderV1.Create(Application);
  Hidden.ProjectSupported := False;
  Provider := TProviderV1.Create(Application);
  try
    Result := TDAIProjectTools.ListTools(CProject);
    try
      Extensions := Result.GetValue<TJSONArray>('extensions');
      Check(Extensions.Count = 1, 'Only direct application-owned matching providers are discovered.');
      Check(Result.GetValue<string>('project') = CProject, 'Resolved project identity retained.');
      Check(Result.GetValue<Boolean>('read_only'), 'Read-only contract disclosed.');
      Info := TJSONObject(Extensions.Items[0]);
      Check(Info.GetValue<string>('id') = 'sample', 'Provider information returned.');
      Check(Info.GetValue<string>('instructions') <> '', 'Project instructions remain available.');
      Tools := Info.GetValue<TJSONArray>('tools'); Tool := TJSONObject(Tools.Items[0]);
      Check(Tool.GetValue<string>('name') = 'lookup', 'Provider descriptor available.');
      Check(Tool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint'), 'Host declares read-only tools.');
      Check(not Tool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('destructiveHint'), 'Host rejects destructive semantics.');
      Check(Hidden.InfoCalls = 0, 'Foreign project does not receive provider metadata.');
      Check(Nested.SupportCalls = 0, 'Nested objects are not implicitly registered.');
    finally Result.Free; end;
    Call('SAMPLE', 'LOOKUP', '{"query":"value"}');
    Check(Provider.Calls = 1, 'Independently declared ABI dispatches once.');
    Check(Provider.LastTool = 'lookup', 'Canonical registered tool name is used.');
    Check(Provider.LastProject = CProject, 'Call receives actual project.');
    Check(Provider.LastArguments = '{"query":"value"}', 'Arguments preserved.');
    ExpectFailure(procedure begin Call('missing', 'lookup', '{"query":"value"}'); end, 'Missing provider must fail.');
    ExpectFailure(procedure begin Call('sample', 'missing', '{"query":"value"}'); end, 'Undeclared tool must fail.');
    ExpectFailure(procedure begin Call('sample', 'lookup', '{}'); end, 'Required property checked before provider.');
    ExpectFailure(procedure begin Call('sample', 'lookup', '{"query":"value","sql":"anything"}'); end, 'Unknown selectors checked before provider.');
    Check(Provider.Calls = 1, 'Invalid requests never invoke provider data calls.');
    TestProjectLoaded := False;
    try
      ExpectFailure(List, 'Closed project fails revalidation.');
      ExpectFailure(procedure begin Call('sample', 'lookup', '{"query":"value"}'); end, 'Closed project cannot call a provider.');
      Check(Provider.Calls = 1, 'Closed project invokes no data callback.');
    finally TestProjectLoaded := True; end;
  finally
    Provider.Free; Hidden.Free; Owner.Free;
  end;
  Result := TDAIProjectTools.ListTools(CProject);
  try Check(Result.GetValue<TJSONArray>('extensions').Count = 0, 'Provider destruction leaves no retained registration.'); finally Result.Free; end;
end;

procedure TestMalformedProviders;
const
  InvalidInfo: array[0..7] of string = ('null', '[]', '{}', '{"id":"bad id"}', '{"id":42}', '{"id":"sample","instructions":0}',
    '{"id":"sample","unexpected":"value"}', '{"id":"sample","id":"duplicate"}');
  InvalidTools: array[0..8] of string = ('{}', '[null]', '[{}]', '[{"name":"lookup"}]',
    '[{"name":"lookup","inputSchema":{"type":"array"}}]',
    '[{"name":"lookup","inputSchema":{"type":"object","additionalProperties":true}}]',
    '[{"name":"lookup","inputSchema":{"type":"object","additionalProperties":false,"required":["missing"]}}]',
    '[{"name":"lookup","inputSchema":{"type":"object","additionalProperties":false},"annotations":{"readOnlyHint":false}}]',
    '[{"name":"lookup","inputSchema":{"type":"object","additionalProperties":false},"annotations":{"destructiveHint":true}}]');
var
  Provider, Duplicate: TProvider;
  I: Integer;
begin
  Provider := TProviderV1.Create(Application);
  try
    for I := Low(InvalidInfo) to High(InvalidInfo) do
    begin Provider.Info := InvalidInfo[I]; ExpectFailure(List, 'Invalid provider info accepted: ' + IntToStr(I)); end;
    Provider.Info := '{"id":"sample"}';
    for I := Low(InvalidTools) to High(InvalidTools) do
    begin Provider.Tools := InvalidTools[I]; ExpectFailure(List, 'Invalid tool metadata accepted: ' + IntToStr(I)); end;
    Provider.Tools := CTools;
    Duplicate := TProviderV1.Create(Application);
    try
      Duplicate.Info := '{"id":"SAMPLE"}';
      ExpectFailure(List, 'Duplicate provider identities must fail closed.');
      ExpectFailure(procedure begin Call('sample', 'lookup', '{"query":"value"}'); end, 'Ambiguous call must fail closed.');
      Check(Provider.Calls = 0, 'Ambiguous provider never called.');
    finally Duplicate.Free; end;
    Provider.Tools := '[{"name":"lookup","inputSchema":{"type":"object","additionalProperties":false}},' +
      '{"name":"LOOKUP","inputSchema":{"type":"object","additionalProperties":false}}]';
    ExpectFailure(List, 'Case-insensitive duplicate tool names must fail.');
    Provider.Tools := CTools;
    Provider.Response := '[]';
    ExpectFailure(procedure begin Call('sample', 'lookup', '{"query":"value"}'); end, 'Non-object result rejected.');
    Provider.Response := StringOfChar('x', 1024 * 1024 + 1);
    ExpectFailure(procedure begin Call('sample', 'lookup', '{"query":"value"}'); end, 'Oversized result rejected before JSON parsing.');
    Provider.Response := '{"status":"ok"}';
    ExpectFailure(procedure begin Call('sample', 'lookup', '{"query":"' + StringOfChar('x', 65536) + '"}'); end,
      'Oversized client arguments rejected.');
  finally Provider.Free; end;
end;

procedure TestWriteAuthorization;
const
  CRead = '{"name":"lookup","inputSchema":{"type":"object","additionalProperties":false},"annotations":{"readOnlyHint":true}}';
  CWrite = '{"name":"change","inputSchema":{"type":"object","additionalProperties":false},"annotations":{"readOnlyHint":false}}';
var
  Provider: TProvider;
  Response, Annotations: TJSONObject;
  Extensions, Tools: TJSONArray;
  WriteChecks: Integer;
begin
  Provider := TProviderV2.Create(Application);
  WriteChecks := 0;
  try
    Check(not Supports(Provider, DAI.ProjectTools.IndependentAPI.IDAIMCPReadOnlyExtensionV1),
      'An old host must not discover the V2-only provider as V1.');
    Provider.Tools := '[' + CRead + ',' + CWrite + ']';
    Response := TDAIProjectTools.ListTools(CProject);
    try
      Check(not Response.GetValue<Boolean>('read_only'), 'Mixed discovery is not globally read-only.');
      Extensions := Response.GetValue<TJSONArray>('extensions');
      Tools := TJSONObject(Extensions.Items[0]).GetValue<TJSONArray>('tools');
      Annotations := TJSONObject(Tools.Items[0]).GetValue<TJSONObject>('annotations');
      Check(Annotations.GetValue<Boolean>('readOnlyHint'), 'V2 lookup retains read-only classification.');
      Annotations := TJSONObject(Tools.Items[1]).GetValue<TJSONObject>('annotations');
      Check(not Annotations.GetValue<Boolean>('readOnlyHint'), 'V2 change retains write classification.');
      Check(Annotations.GetValue<Boolean>('destructiveHint'), 'Writes default to potentially destructive.');
    finally Response.Free; end;

    Call('sample', 'lookup', '{}', procedure begin Inc(WriteChecks); end);
    Check((WriteChecks = 0) and (Provider.Calls = 1), 'V2 read executes without a write permission check.');
    ExpectFailure(procedure begin Call('sample', 'change', '{}'); end, 'Missing write authorizer fails closed.');
    ExpectFailure(
      procedure
      begin
        Call('sample', 'change', '{}',
          procedure
          begin
            Inc(WriteChecks);
            raise EAbort.Create('Write denied');
          end);
      end, 'Denied write must fail.');
    Check((WriteChecks = 1) and (Provider.Calls = 1), 'Denied writes invoke no data callback.');
    ExpectFailure(
      procedure
      begin
        Call('sample', 'change', '{}',
          procedure begin Provider.Tools := '[' + CRead + ']'; end);
      end, 'Tool removal during permission prompt must be detected.');
    Check(Provider.Calls = 1, 'Removed tool invokes no data callback.');
    Provider.Tools := '[' + CRead + ',' + CWrite + ']';
    ExpectFailure(
      procedure
      begin
        Call('sample', 'change', '{}',
          procedure
          begin
            Provider.Tools := '[' + CRead + ',' + StringReplace(CWrite, '"change"', '"change","description":"changed"', []) + ']';
          end);
      end, 'Changed tool metadata during the permission prompt must be detected.');
    Check(Provider.Calls = 1, 'Changed tool invokes no data callback.');
    Provider.Tools := '[' + CRead + ',' + CWrite + ']';
    try
      ExpectFailure(
        procedure
        begin
          Call('sample', 'change', '{}',
            procedure begin TestProjectLoaded := False; end);
        end, 'Project closure during permission prompt must be detected.');
    finally TestProjectLoaded := True; end;
    Check(Provider.Calls = 1, 'Closed project invokes no data callback.');
    Call('sample', 'change', '{}',
      procedure
      begin
        Check(TestDispatchDepth = 0, 'No package callback block is retained across authorization.');
        Check(Provider.Calls = 1, 'Provider write is preceded by authorization.');
        Inc(WriteChecks);
      end);
    Check((WriteChecks = 2) and (Provider.Calls = 2) and (Provider.LastTool = 'change'), 'Authorized write executes once.');
    Provider.Tools := CTools;
    ExpectFailure(List, 'V2 must explicitly declare access for each tool.');
  finally Provider.Free; end;
end;

begin
  try
    TestProjectFile := CProject;
    TestDiscoveryAndLifecycle;
    TestMalformedProviders;
    TestWriteAuthorization;
    Check(TestDispatchDepth = 0, 'Main-thread dispatch is balanced after failures.');
    Writeln('PASS ProjectTools: ', Checks, ' checks');
  except
    on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
end.
