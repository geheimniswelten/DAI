unit h5u.DAI.OTA.Evaluation;
interface
uses System.JSON;
type
{$I DAI.ExpressionDispatch.Evaluation.inc}
  TDAIEvaluationService = class sealed
  public
    class var PrepareCalls, EvaluateCalls, ModifyCalls, StatusCalls, PreparePermissionCount, FinalPermissionCount: Integer;
    class var LastPrepared, LastRequest: TDAIEvaluationRequest;
    class var LastValue, LastRequestId: string;
    class var LastResponse: TJSONObject;
    class procedure Reset; static;
    class function Prepare(const ARequest: TDAIEvaluationRequest): TDAIEvaluationRequest; static;
    class function Evaluate(const ARequest: TDAIEvaluationRequest): TJSONObject; static;
    class function Modify(const ARequest: TDAIEvaluationRequest; const AValue: string): TJSONObject; static;
    class function Status(const ARequestId: string): TJSONObject; static;
  end;
implementation
uses System.SysUtils, DAI.ExpressionDispatch.TestState, h5u.DAI.Permissions.Manager;
procedure RequirePreparedBinding(const ARequest, APrepared: TDAIEvaluationRequest);
begin
  if not ARequest.FPrepared or (ARequest.FExpectedProcess <> APrepared.FExpectedProcess) or
     (ARequest.FExpectedThread <> APrepared.FExpectedThread) then raise Exception.Create('Prepared SDK identity binding was lost.');
end;
class procedure TDAIEvaluationService.Reset;
begin
  PrepareCalls := 0; EvaluateCalls := 0; ModifyCalls := 0; StatusCalls := 0;
  PreparePermissionCount := -1; FinalPermissionCount := -1;
  LastPrepared := Default(TDAIEvaluationRequest); LastRequest := Default(TDAIEvaluationRequest);
  LastValue := ''; LastRequestId := ''; LastResponse := nil;
end;
class function TDAIEvaluationService.Prepare(const ARequest: TDAIEvaluationRequest): TDAIEvaluationRequest;
begin
  Inc(PrepareCalls); RecordEvent('evaluation:prepare'); PreparePermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := ARequest;
  if Result.ProcessId = 0 then Result.ProcessId := CurrentProcessId;
  if Result.ThreadId = 0 then Result.ThreadId := CurrentThreadId;
  Result.FPrepared := True; Result.FExpectedProcess := TInterfacedObject.Create; Result.FExpectedThread := TInterfacedObject.Create;
  LastPrepared := Result;
end;
class function TDAIEvaluationService.Evaluate(const ARequest: TDAIEvaluationRequest): TJSONObject;
begin
  RequirePreparedBinding(ARequest, LastPrepared);
  Inc(EvaluateCalls); RecordEvent('evaluation:evaluate'); LastRequest := ARequest;
  FinalPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := ServiceResponse('evaluation'); LastResponse := Result;
end;
class function TDAIEvaluationService.Modify(const ARequest: TDAIEvaluationRequest; const AValue: string): TJSONObject;
begin
  RequirePreparedBinding(ARequest, LastPrepared);
  Inc(ModifyCalls); RecordEvent('evaluation:modify'); LastRequest := ARequest; LastValue := AValue;
  FinalPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := ServiceResponse('modify'); LastResponse := Result;
end;
class function TDAIEvaluationService.Status(const ARequestId: string): TJSONObject;
begin
  Inc(StatusCalls); RecordEvent('evaluation:status'); LastRequestId := ARequestId;
  FinalPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := ServiceResponse('evaluation-status'); LastResponse := Result;
end;
end.
