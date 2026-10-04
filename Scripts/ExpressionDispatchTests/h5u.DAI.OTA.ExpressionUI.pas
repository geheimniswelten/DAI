unit h5u.DAI.OTA.ExpressionUI;
interface
uses System.JSON, ToolsAPI;
type
{$I DAI.ExpressionDispatch.UI.inc}
  TDAIExpressionUIService = class sealed
  public
    class var MetadataCalls, PrepareCalls, InvokeCalls, StatusCalls, PreparePermissionCount, FinalPermissionCount: Integer;
    class var LastRequest: TDAIExpressionUIRequest;
    class var LastAction, LastRequestId: string;
    class var LastResponse: TJSONObject;
    class procedure Reset; static;
    class function CurrentFileName: string; static;
    class function Prepare(const AAction: string; const AExpectedFile: string = ''): TDAIExpressionUIRequest; static;
    class function Invoke(const ARequest: TDAIExpressionUIRequest): TJSONObject; static;
    class function Status(const ARequestId: string): TJSONObject; static;
  end;
implementation
uses System.Classes, System.SysUtils, DAI.ExpressionDispatch.TestState, h5u.DAI.Permissions.Manager;
class procedure TDAIExpressionUIService.Reset;
begin
  MetadataCalls := 0; PrepareCalls := 0; InvokeCalls := 0; StatusCalls := 0;
  PreparePermissionCount := -1; FinalPermissionCount := -1; LastRequest := Default(TDAIExpressionUIRequest);
  LastAction := ''; LastRequestId := ''; LastResponse := nil;
end;
class function TDAIExpressionUIService.CurrentFileName: string;
begin Inc(MetadataCalls); RecordEvent('ui:metadata'); Result := CurrentFile; end;
class function TDAIExpressionUIService.Prepare(const AAction, AExpectedFile: string): TDAIExpressionUIRequest;
begin
  Inc(PrepareCalls); RecordEvent('ui:prepare'); LastExpectedFile := AExpectedFile; LastAction := AAction;
  PreparePermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  if AExpectedFile <> CurrentFile then raise EInvalidOperation.Create('Expected-file mismatch before source read.');
  if (AAction <> 'add_watch') and (AAction <> 'watch_at_cursor') and
     (AAction <> 'evaluate_modify') and (AAction <> 'inspect_at_cursor') then raise EArgumentException.Create('Invalid action.');
  Result := Default(TDAIExpressionUIRequest); Result.Action := AAction; Result.FileName := CurrentFile; Result.SourceSha256 := 'exact-source-hash';
  Result.Cursor.Line := 12; Result.Cursor.Col := 7; Result.BlockVisible := True;
  if (AAction = 'evaluate_modify') or (AAction = 'inspect_at_cursor') then
  begin Result.ProcessId := CurrentProcessId; Result.ThreadId := CurrentThreadId; end;
end;
class function TDAIExpressionUIService.Invoke(const ARequest: TDAIExpressionUIRequest): TJSONObject;
begin
  Inc(InvokeCalls); RecordEvent('ui:invoke'); LastRequest := ARequest;
  FinalPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := ServiceResponse('ui'); Result.AddPair('action_invoked', TJSONBool.Create(False)); LastResponse := Result;
end;
class function TDAIExpressionUIService.Status(const ARequestId: string): TJSONObject;
begin
  Inc(StatusCalls); RecordEvent('ui:status'); LastRequestId := ARequestId;
  FinalPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := ServiceResponse('ui-status'); LastResponse := Result;
end;
end.
