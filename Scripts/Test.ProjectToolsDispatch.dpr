program Test.ProjectToolsDispatch;
{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}
uses
  System.Classes, System.JSON, System.SysUtils, System.Generics.Collections,
  DAI.ProjectTools.DispatchBranch,
  h5u.DAI.OTA.Helpers, h5u.DAI.Permissions.Manager, h5u.DAI.ProjectTools, h5u.DAI.Types;
const
  CCurrent = 'C:\SyntheticDAITest\Current.dproj';
  COther = 'C:\SyntheticDAITest\Denied\Other.dproj';
var
  Checks: Integer;
  Context: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then raise EInvalidOperation.Create(AMessage);
end;

procedure Reset(const AAllowed: Boolean = True);
begin
  TDAIOTA.Reset;
  TDAIPermissionManager.Instance.Reset(not AAllowed, AAllowed);
  TDAIProjectTools.Reset;
  Context.ProjectKey := 'C:\Stale\Unrelated.dproj';
  Context.ThreadId := 'project-tools-thread'; Context.TransportSessionId := 'project-tools-transport';
  Context.ClientName := 'project-tools-client';
end;

function Arguments(const ACall: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  if ACall then
  begin
    Result.AddPair('extension', 'sample'); Result.AddPair('tool', 'lookup');
    Result.AddPair('arguments', TJSONObject.Create.AddPair('query', 'a literal query'));
  end;
end;

function ToolName(const ACall: Boolean): string;
begin if ACall then Result := 'project_tool_call' else Result := 'project_tools_list'; end;

procedure TestForwarding(const ACall, AExplicit: Boolean);
var
  Args, Response: TJSONObject;
  Original, Project: string;
  Request: TPermissionRequest;
begin
  Reset;
  Args := Arguments(ACall);
  try
    Project := CCurrent;
    if AExplicit then begin Project := COther; Args.AddPair('project', Project); end;
    Original := Args.ToJSON;
    Response := TDAIMCPTools.CallTool(ToolName(ACall), Args, Context);
    try
      Check(TDAIProjectTools.Calls = 1, 'Exactly one provider dispatch.');
      Check(Args.ToJSON = Original, 'Client arguments are not rewritten.');
      Check(TDAIProjectTools.LastProject = Project, 'Actual selected loaded project forwarded.');
      Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'One explicit permission decision.');
      Request := TDAIPermissionManager.Instance.Requests[0];
      Check(Request.Category = pcProjectRead, 'Project reads, not unrestricted reference reads.');
      Check(Request.Resource = Project, 'Permission resource is actual project path.');
      Check(Request.Context.ProjectKey = Project, 'Permission ownership uses actual selected project.');
      Check(Request.Context.ThreadId = Context.ThreadId, 'Chat identity retained.');
      Check(Request.Context.TransportSessionId = Context.TransportSessionId, 'Transport identity retained.');
      Check(Request.Context.ClientName = Context.ClientName, 'Client identity retained.');
      if ACall then
      begin
        Check(Response.GetValue<string>('kind') = 'call', 'Call service selected.');
        Check(TDAIProjectTools.LastExtension = 'sample', 'Extension forwarded.');
        Check(TDAIProjectTools.LastTool = 'lookup', 'Tool forwarded.');
        Check(TDAIProjectTools.LastArguments = '{"query":"a literal query"}', 'Nested arguments forwarded without conversion.');
      end
      else Check(Response.GetValue<string>('kind') = 'list', 'List service selected.');
    finally Response.Free; end;
  finally Args.Free; end;
end;

procedure TestDenied(const ACall: Boolean);
var Args, Response: TJSONObject; Failed: Boolean;
begin
  Reset(False); Args := Arguments(ACall);
  try
    Failed := False;
    try Response := TDAIMCPTools.CallTool(ToolName(ACall), Args, Context); Response.Free;
    except on E: EAbort do Failed := True; end;
    Check(Failed, 'Denied project permission aborts the request.');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'Denial recorded under project read policy.');
    Check(TDAIProjectTools.Calls = 0, 'Denied permission prevents provider lookup/data calls.');
  finally Args.Free; end;
end;

procedure TestWritePermission(const AAllowed: Boolean);
var
  Args, Response: TJSONObject;
  Requests: TArray<TPermissionRequest>;
  Denied: Boolean;
begin
  Reset;
  TDAIPermissionManager.Instance.ProjectWriteAllowed := AAllowed;
  Args := Arguments(True);
  try
    Args.RemovePair('tool').Free;
    Args.AddPair('tool', 'change');
    Args.AddPair('project', COther);
    Denied := False;
    try
      Response := TDAIMCPTools.CallTool(ToolName(True), Args, Context);
      Response.Free;
    except
      on E: EAbort do Denied := True;
    end;
    Check(Denied = not AAllowed, 'Dispatch honors the project write decision.');
    Check(TDAIProjectTools.Calls = Ord(AAllowed), 'Write callback executes once only with authorization.');
    Requests := TDAIPermissionManager.Instance.Requests;
    Check(Length(Requests) = 2, 'A write requires two permission decisions.');
    Check(Requests[0].Category = pcProjectRead, 'Project read precedes write authorization.');
    Check(Requests[1].Category = pcProjectWrite, 'Second decision uses the project write category.');
    Check(Requests[1].Context.ProjectKey = COther, 'Write authorization uses the actual selected project.');
    Check(Requests[1].Resource = COther, 'Write authorization names the actual project resource.');
    Check(Requests[1].Context.ThreadId = Context.ThreadId, 'Write authorization preserves chat identity.');
    Check(Requests[1].Context.TransportSessionId = Context.TransportSessionId, 'Write authorization preserves transport identity.');
  finally Args.Free; end;
end;

procedure ExpectRejected(const ACall: Boolean; const AArguments: TJSONObject);
var Response: TJSONObject; Failed: Boolean;
begin
  Reset;
  Failed := False;
  try Response := TDAIMCPTools.CallTool(ToolName(ACall), AArguments, Context); Response.Free;
  except on E: Exception do Failed := True; end;
  Check(Failed, 'Malformed or unloaded selector must be rejected.');
  Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'Invalid input rejected before prompting.');
  Check(TDAIProjectTools.Calls = 0, 'Invalid input never reaches provider.');
end;

procedure TestValidation(const ACall: Boolean);
var Args: TJSONObject; I: Integer;
begin
  for I := 0 to 5 do
  begin
    Args := Arguments(ACall);
    try
      case I of
        0: Args.AddPair('project', 'C:\NotLoaded\Missing.dproj');
        1: Args.AddPair('project', TJSONNumber.Create(42));
        2: Args.AddPair('project', TJSONBool.Create(False));
        3: Args.AddPair('project', TJSONNull.Create);
        4: Args.AddPair('filename', 'C:\Injected\Project.dproj');
        5: Args.AddPair('Project', CCurrent);
      end;
      ExpectRejected(ACall, Args);
    finally Args.Free; end;
  end;
  if not ACall then Exit;
  for I := 0 to 8 do
  begin
    Args := Arguments(True);
    try
      case I of
        0: Args.RemovePair('extension').Free;
        1: begin Args.RemovePair('extension').Free; Args.AddPair('extension', TJSONNumber.Create(1)); end;
        2: begin Args.RemovePair('extension').Free; Args.AddPair('extension', '  '); end;
        3: Args.RemovePair('tool').Free;
        4: begin Args.RemovePair('tool').Free; Args.AddPair('tool', TJSONBool.Create(True)); end;
        5: Args.RemovePair('arguments').Free;
        6: begin Args.RemovePair('arguments').Free; Args.AddPair('arguments', TJSONArray.Create); end;
        7: begin Args.RemovePair('arguments').Free; Args.AddPair('arguments', TJSONNull.Create); end;
        8: begin Args.RemovePair('arguments').Free; Args.AddPair('arguments', TJSONObject.Create.AddPair('query', StringOfChar('x', 65536))); end;
      end;
      ExpectRejected(True, Args);
    finally Args.Free; end;
  end;
end;

procedure TestSchemas;
var Tools: TJSONArray; ListTool, CallTool, Schema, Props: TJSONObject;
begin
  Tools := TDAIMCPTools.ListTools;
  try
    Check(Tools.Count = 2, 'Both real production schemas extracted.');
    ListTool := TJSONObject(Tools.Items[0]); CallTool := TJSONObject(Tools.Items[1]);
    Check(ListTool.GetValue<string>('name') = 'project_tools_list', 'List schema name retained.');
    Check(CallTool.GetValue<string>('name') = 'project_tool_call', 'Call schema name retained.');
    Check(ListTool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint'), 'List annotation is read-only.');
    Check(not CallTool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint'), 'Call annotation allows writes.');
    Schema := CallTool.GetValue<TJSONObject>('inputSchema'); Props := Schema.GetValue<TJSONObject>('properties');
    Check(Schema.GetValue<TJSONArray>('required').Count = 3, 'Extension/tool/arguments required in real schema.');
    Check(not Schema.GetValue<Boolean>('additionalProperties'), 'Wrapper selectors are closed.');
    Check(Props.GetValue<TJSONObject>('arguments').GetValue<string>('type') = 'object', 'Nested arguments must be object.');
    Check(Props.GetValue<TJSONObject>('extension').GetValue<Integer>('maxLength') = 64, 'Extension identifier bound advertised.');
    Check(Props.GetValue<TJSONObject>('tool').GetValue<Integer>('maxLength') = 128, 'Tool identifier bound advertised.');
    Check(TDAIMCPTools.NeedsProjectContext('project_tools_list', nil), 'List keeps project context.');
    Check(TDAIMCPTools.NeedsProjectContext('project_tool_call', nil), 'Call keeps project context.');
  finally Tools.Free; end;
end;

begin
  try
    TestSchemas;
    TestForwarding(False, False); TestForwarding(False, True);
    TestForwarding(True, False); TestForwarding(True, True);
    TestDenied(False); TestDenied(True);
    TestWritePermission(False); TestWritePermission(True);
    TestValidation(False); TestValidation(True);
    Writeln('PASS ProjectToolsDispatch: ', Checks, ' checks');
  except
    on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
end.
