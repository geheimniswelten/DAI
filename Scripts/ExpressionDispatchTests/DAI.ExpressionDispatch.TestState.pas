unit DAI.ExpressionDispatch.TestState;
interface
uses System.JSON, h5u.DAI.Types;
const
  CSourceFile = 'C:\OwningProject\ActualSource.pas';
  COwnerProject = 'C:\OwningProject\Actual.dproj';
var
  Events: TArray<string>;
  ContextFiles: TArray<string>;
  CurrentFile, CursorExpression, LastExpectedFile: string;
  CursorAvailable, SwitchFileDuringPermission, SwitchDebugDuringPermission: Boolean;
  CurrentProcessId, CurrentThreadId: Cardinal;
procedure RecordEvent(const AEvent: string);
procedure ResetState;
function ResolveArgumentsContext(const AArguments: TJSONObject; const AContext: TDAIRequestContext): TDAIRequestContext;
function ServiceResponse(const AName: string): TJSONObject;
implementation
uses System.SysUtils;
procedure RecordEvent(const AEvent: string);
begin Events := Events + [AEvent]; end;
procedure ResetState;
begin
  Events := nil; ContextFiles := nil; CurrentFile := CSourceFile; CursorExpression := 'Object.Field[2]';
  LastExpectedFile := ''; CursorAvailable := True; SwitchFileDuringPermission := False; SwitchDebugDuringPermission := False;
  CurrentProcessId := 4242; CurrentThreadId := 33;
end;
function ResolveArgumentsContext(const AArguments: TJSONObject; const AContext: TDAIRequestContext): TDAIRequestContext;
var LValue: TJSONValue;
begin
  Result := AContext;
  if AArguments = nil then Exit;
  LValue := AArguments.GetValue('file');
  if LValue is TJSONString then
  begin ContextFiles := ContextFiles + [LValue.Value]; Result.ProjectKey := COwnerProject; end;
end;
function ServiceResponse(const AName: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('service_response', AName);
  Result.AddPair('request_id', 'actual-final-request-id');
  Result.AddPair('status', 'pending');
  Result.AddPair('result_value', TJSONNull.Create);
  Result.AddPair('modified', TJSONBool.Create(False));
end;
end.
