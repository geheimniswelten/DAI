unit h5u.DAI.OTA.Evaluation;

interface

uses
  System.JSON;

type
  TDAIEvaluationRequest = record
  private
    FExpectedProcess, FExpectedThread: IInterface;
    FPrepared: Boolean;
  public
    Expression, SideEffects, FormatSpecifiers, SourceFile: string;
    ProcessId, ThreadId: Cardinal;
    Line, MaximumCharacters, TimeoutMs: Integer;
  end;

  TDAIEvaluationService = class sealed
  public
    class function Prepare(const ARequest: TDAIEvaluationRequest): TDAIEvaluationRequest; static;
    class function Evaluate(const ARequest: TDAIEvaluationRequest): TJSONObject; static;
    class function Modify(const ARequest: TDAIEvaluationRequest; const AValue: string): TJSONObject; static;
    class function Status(const ARequestId: string): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Helpers;

const
  CMaximumOutstanding = 32;
  CMaximumHistory = 64;
  CMaximumExpression = 16384;

type
  TEvaluationPhase = (epPreparing, epEvaluateCall, epEvaluatePending, epModifyCall, epModifyPending, epFinished);

  TEvaluationSnapshot = record
    Id, Operation, Expression, Status, SDKResult, ReasonCode, MessageText, ResultText: string;
    ProcessId, ThreadId: Cardinal;
    CanModify, Modified, ReturnCode: Integer;
    ResultAddress: TOTAAddress;
    ResultSize: LongWord;
    ResultValue: Int64;
    HasAddress, HasSize, HasValue, HasReturnCode, Truncated, Retryable, ModifyAttempted, Outstanding, Destroyed: Boolean;
    ContextChanged, CallActive: Boolean;
    RegistrationUncertain: Boolean;
  end;

  IEvaluationBroker = interface;

  IEvaluationJob = interface
    ['{EE379FE2-D18F-4D5A-B2AA-8DBBD26413D4}']
    function Snapshot: TEvaluationSnapshot;
    procedure Cancel;
    procedure Expire;
    procedure Detach;
    procedure MarkReentrant;
  end;

  TEvaluationJob = class(TInterfacedObject, IEvaluationJob, IOTAThreadNotifier, IOTAThreadNotifier160)
  private
    FLock: TCriticalSection;
    FBroker: IEvaluationBroker;
    FRequest: TDAIEvaluationRequest;
    FBuffer: TArray<Char>;
    FFormat: AnsiString;
    FRawCanModify: Boolean;
    FRawAddress: TOTAAddress;
    FRawSize, FRawValue: LongWord;
    FRawModifyValue: Integer;
    FModifyText: string;
    FState: TEvaluationSnapshot;
    FPhase: TEvaluationPhase;
    FThread: IOTAThread;
    FProcess: IOTAProcess;
    FNotifierIndex: Integer;
    FDeadline: UInt64;
    FEpoch, FAtomicEpoch: Cardinal;
    FReceived, FPrecheckDeferred, FAttaching: Boolean;
    FCompletion: TEvaluationSnapshot;
    procedure Receive(const AExpression, AResult: string; const ACanModify: Integer;
      const AAddress: TOTAAddress; const ASize: LongWord; const AReturnCode: Integer; const AModify: Boolean);
    procedure UseCompletion;
  public
    constructor Create(const ARequest: TDAIEvaluationRequest; const AModify: Boolean; const ABroker: IEvaluationBroker);
    destructor Destroy; override;
    function Snapshot: TEvaluationSnapshot;
    procedure Cancel;
    procedure Expire;
    procedure Detach;
    procedure MarkReentrant;
    procedure SetTarget(const AProcess: IOTAProcess; const AThread: IOTAThread);
    procedure Attach;
    procedure BeginCall(const AModify: Boolean; const AValue: string = '');
    procedure FinishCall(const AResult: TOTAEvaluateResult; const AText: string; const ATruncated: Boolean;
      const ACanModify: Boolean; const AAddress: TOTAAddress; const ASize: LongWord; const AValue: Int64; const AModify: Boolean);
    procedure SDKException(const AMessage: string);
    function MayModify: Boolean;
    procedure Fail(const ACode, AMessage: string; const ARetryable: Boolean = False);
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    procedure ThreadNotify(Reason: TOTANotifyReason);
    procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean; ResultAddress, ResultSize: LongWord; ReturnCode: Integer); overload;

    procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean; ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer); overload;

    procedure ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
  end;

  IEvaluationBroker = interface
    ['{A1EB8060-ED63-4B87-9EB5-F251B5CE92A1}']
    function Execute(const ARequest: TDAIEvaluationRequest; const AValue: string; const AModify: Boolean): TJSONObject;
    function Status(const AId: string): TJSONObject;
    procedure Stop;
  end;

  TEvaluationBroker = class(TInterfacedObject, IEvaluationBroker)
  private
    FJobs: TList<IEvaluationJob>;
    FInSDK, FStopped, FModulePinned, FSweeping: Boolean;
    FExecuting: IEvaluationJob;
    procedure Sweep;
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(const ARequest: TDAIEvaluationRequest; const AValue: string; const AModify: Boolean): TJSONObject;
    function Status(const AId: string): TJSONObject;
    procedure Stop;
  end;

var
  GBroker: IEvaluationBroker;
  GStopped: Boolean;

function EvaluationGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure PinEvaluationModule;
var
  LModule: HMODULE;
begin
  LModule := 0;
  // Interface receivers can outlive package finalization while the SDK completes.
  if not EvaluationGetModuleHandleExW($00000004 or $00000001, PChar(Pointer(@PinEvaluationModule)), LModule) then
    RaiseLastOSError;
end;

function BoundedText(const AText: string; const AMaximum: Integer; out ATruncated: Boolean): string;
var
  LCount: Integer;
begin
  LCount := Length(AText);
  ATruncated := LCount > AMaximum;
  if LCount > AMaximum then LCount := AMaximum;
  if LCount > 0 then
    if (Ord(AText[LCount]) >= $D800) and (Ord(AText[LCount]) <= $DBFF) then
    begin
      Dec(LCount);
      ATruncated := True;
    end;
  Result := Copy(AText, 1, LCount);
end;

function BufferText(const ABuffer: TArray<Char>; const AMaximum: Integer; out ATruncated: Boolean): string;
var
  LCount: Integer;
begin
  LCount := 0;
  while LCount < AMaximum do
  begin
    if ABuffer[LCount] = #0 then Break;
    Inc(LCount);
  end;
  ATruncated := LCount = AMaximum;
  if LCount > 0 then
    if (Ord(ABuffer[LCount - 1]) >= $D800) and (Ord(ABuffer[LCount - 1]) <= $DBFF) then
    begin
      Dec(LCount);
      ATruncated := True;
    end;
  SetString(Result, PChar(ABuffer), LCount);
end;

procedure NullableInteger(const AJson: TJSONObject; const AName: string; const AValue: Integer);
begin
  if AValue < 0 then AJson.AddPair(AName, TJSONNull.Create)
  else AJson.AddPair(AName, TJSONBool.Create(AValue <> 0));
end;

function SnapshotJson(const AState: TEvaluationSnapshot): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('request_id', AState.Id);
    Result.AddPair('operation', AState.Operation);
    Result.AddPair('expression', AState.Expression);
    Result.AddPair('status', AState.Status);
    Result.AddPair('sdk_result', AState.SDKResult);
    Result.AddPair('process_id', TJSONNumber.Create(Int64(AState.ProcessId)));
    Result.AddPair('thread_id', TJSONNumber.Create(Int64(AState.ThreadId)));
    Result.AddPair('retryable', TJSONBool.Create(AState.Retryable));
    Result.AddPair('sdk_pending', TJSONBool.Create(AState.Outstanding and not AState.RegistrationUncertain));
    Result.AddPair('receiver_retained', TJSONBool.Create(AState.Outstanding));
    Result.AddPair('registration_uncertain', TJSONBool.Create(AState.RegistrationUncertain));
    Result.AddPair('reason_code', AState.ReasonCode);
    Result.AddPair('message', AState.MessageText);
    Result.AddPair('result_text', AState.ResultText);
    Result.AddPair('truncated', TJSONBool.Create(AState.Truncated));
    Result.AddPair('context_changed', TJSONBool.Create(AState.ContextChanged));
    NullableInteger(Result, 'can_modify', AState.CanModify);
    if AState.HasAddress then Result.AddPair('result_address', '0x' + IntToHex(AState.ResultAddress, 16))
    else Result.AddPair('result_address', TJSONNull.Create);
    if AState.HasSize then Result.AddPair('result_size', TJSONNumber.Create(Int64(AState.ResultSize)))
    else Result.AddPair('result_size', TJSONNull.Create);
    if AState.HasValue then Result.AddPair('result_value', TJSONNumber.Create(Int64(AState.ResultValue)))
    else Result.AddPair('result_value', TJSONNull.Create);
    if AState.HasReturnCode then Result.AddPair('return_code', TJSONNumber.Create(AState.ReturnCode))
    else Result.AddPair('return_code', TJSONNull.Create);
    if AState.Operation = 'modify' then
    begin
      Result.AddPair('modify_attempted', TJSONBool.Create(AState.ModifyAttempted));
      NullableInteger(Result, 'modified', AState.Modified);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function CheckedRequest(const ARequest: TDAIEvaluationRequest; const AModify: Boolean; const AValue: string): TDAIEvaluationRequest;
var
  LText: string;
  I: Integer;
begin
  Result := ARequest;
  if (Trim(Result.Expression) = '') or (Length(Result.Expression) > CMaximumExpression) or (Pos(#0, Result.Expression) <> 0) then
    raise EArgumentException.Create('expression muss 1 bis 16384 Zeichen ohne NUL enthalten.');
  Result.SideEffects := LowerCase(Result.SideEffects);
  if Result.SideEffects = '' then Result.SideEffects := 'none';
  if (Result.SideEffects <> 'none') and (Result.SideEffects <> 'properties') and (Result.SideEffects <> 'all') then
    raise EArgumentException.Create('side_effects muss none, properties oder all sein.');
  if AModify and (Result.SideEffects <> 'none') then
    raise EArgumentException.Create('Modify erfordert einen Vorab-Evaluate mit side_effects none.');
  if AModify then
    if (Trim(AValue) = '') or (Length(AValue) > CMaximumExpression) or (Pos(#0, AValue) <> 0) then
      raise EArgumentException.Create('value muss 1 bis 16384 Zeichen ohne NUL enthalten.');
  if Result.MaximumCharacters = 0 then Result.MaximumCharacters := 4096;
  if (Result.MaximumCharacters < 1) or (Result.MaximumCharacters > 65536) then
    raise EArgumentOutOfRangeException.Create('maximum_characters muss zwischen 1 und 65536 liegen.');
  if Result.TimeoutMs = 0 then Result.TimeoutMs := 5000;
  if (Result.TimeoutMs < 100) or (Result.TimeoutMs > 30000) then
    raise EArgumentOutOfRangeException.Create('timeout_ms muss zwischen 100 und 30000 liegen.');
  if (Result.SourceFile = '') <> (Result.Line = 0) then
    raise EArgumentException.Create('sourcefile und eine positive line müssen gemeinsam angegeben werden.');
  if (Result.Line < 0) or (Length(Result.SourceFile) > 32767) or (Pos(#0, Result.SourceFile) <> 0) then
    raise EArgumentException.Create('Ungültiger lexikalischer Quellkontext.');
  LText := Result.FormatSpecifiers;
  if Length(LText) > 256 then raise EArgumentException.Create('format_specifiers darf höchstens 256 ASCII-Zeichen enthalten.');
  for I := 1 to Length(LText) do
    if (Ord(LText[I]) < 32) or (Ord(LText[I]) > 126) then
      raise EArgumentException.Create('format_specifiers erwartet druckbare ASCII-Zeichen.');
end;

constructor TEvaluationJob.Create(const ARequest: TDAIEvaluationRequest; const AModify: Boolean; const ABroker: IEvaluationBroker);
var
  LId: TGUID;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FBroker := ABroker;
  FRequest := ARequest;
  SetLength(FBuffer, ARequest.MaximumCharacters + 1);
  FFormat := AnsiString(ARequest.FormatSpecifiers);
  FNotifierIndex := -1;
  CreateGUID(LId);
  FState.Id := GUIDToString(LId);
  FState.Expression := ARequest.Expression;
  if AModify then FState.Operation := 'modify' else FState.Operation := 'evaluate';
  FState.Status := 'unavailable';
  FState.CanModify := -1;
  FState.Modified := 0;
  FDeadline := GetTickCount64 + UInt64(ARequest.TimeoutMs);
end;

destructor TEvaluationJob.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TEvaluationJob.Snapshot: TEvaluationSnapshot;
begin
  FLock.Acquire;
  try Result := FState; finally FLock.Release; end;
end;

procedure TEvaluationJob.SetTarget(const AProcess: IOTAProcess; const AThread: IOTAThread);
begin
  FProcess := AProcess;
  FThread := AThread;
  FState.ProcessId := AProcess.OSProcessId;
  FState.ThreadId := AThread.OSThreadID;
end;

procedure TEvaluationJob.Attach;
var
  LIndex: Integer;
  LNotifier: IOTAThreadNotifier;
begin
  LNotifier := Self;
  FState.Outstanding := True;
  FAttaching := True;
  LIndex := FThread.AddNotifier(LNotifier);
  FLock.Acquire;
  try
    FAttaching := False;
    if not FState.Destroyed then FNotifierIndex := LIndex;
    if LIndex < 0 then FState.Outstanding := False;
  finally FLock.Release; end;
  if LIndex < 0 then raise EInvalidOperation.Create('Der Debugger hat den Threadnotifier nicht registriert.');
end;

procedure TEvaluationJob.Detach;
var
  LThread: IOTAThread;
  LProcess: IOTAProcess;
  LIndex: Integer;
  LTruncated: Boolean;
begin
  LThread := nil;
  LIndex := -1;
  FLock.Acquire;
  try
    if FState.Outstanding or FState.CallActive then Exit;
    if not FState.Destroyed then
    begin
      LThread := FThread;
      LProcess := FProcess;
      LIndex := FNotifierIndex;
    end;
    FNotifierIndex := -1;
    FThread := nil;
    FProcess := nil;
  finally FLock.Release; end;
  try
    if LThread <> nil then
      if LIndex >= 0 then LThread.RemoveNotifier(LIndex);
  except
    on E: Exception do
    begin
      FLock.Acquire;
      try
        if not FState.Destroyed then
        begin
          // The SDK may have removed the index before throwing. Do not retry
          // that unknown index or free a potentially still registered receiver.
          FThread := LThread;
          FProcess := LProcess;
          FState.Outstanding := True;
          FState.RegistrationUncertain := True;
          FState.ReasonCode := 'notifier_cleanup_uncertain';
          FState.MessageText := BoundedText(E.Message, 4096, LTruncated);
          FState.Retryable := False;
          Exit;
        end;
      finally FLock.Release; end;
    end;
  end;
  FRequest.FExpectedProcess := nil;
  FRequest.FExpectedThread := nil;
  FBroker := nil;
end;

procedure TEvaluationJob.Fail(const ACode, AMessage: string; const ARetryable: Boolean);
var
  LTruncated: Boolean;
begin
  FLock.Acquire;
  try
    if FState.Status = 'cancelled' then Exit;
    FState.Status := 'error';
    FState.ReasonCode := ACode;
    FState.MessageText := BoundedText(AMessage, 4096, LTruncated);
    FState.Retryable := ARetryable;
    FPhase := epFinished;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.SDKException(const AMessage: string);
var
  LTruncated: Boolean;
begin
  FLock.Acquire;
  try
    FState.CallActive := False;
    if FState.Status <> 'cancelled' then
    begin
      FState.Status := 'error';
      FState.ReasonCode := 'sdk_exception';
      FState.MessageText := BoundedText(AMessage, 4096, LTruncated);
    end;
    // An exception cannot prove that an already-entered SDK call has retired.
    // Keep its receiver reserved until completion or Destroyed, never reuse it.
    if FPhase = epEvaluateCall then FPhase := epEvaluatePending;
    if FPhase = epModifyCall then FPhase := epModifyPending;
    if FPhase = epPreparing then
    begin
      if FAttaching and not FState.Destroyed then
      begin
        FState.RegistrationUncertain := True;
        FState.Outstanding := True;
        FState.MessageText := 'Ungewisse Threadnotifier-Registrierung; kein Evaluate gestartet. ' + FState.MessageText;
      end
      else
      begin
        FState.Outstanding := False;
        FPhase := epFinished;
      end;
    end;
    if FReceived then UseCompletion;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.Cancel;
begin
  FLock.Acquire;
  try
    if FState.Outstanding or FState.CallActive then
    begin
      FState.Status := 'cancelled';
      FState.ReasonCode := 'service_stopped';
      FState.MessageText := 'Der Evaluator wurde beendet; die SDK-Operation wurde nicht abgebrochen.';
      FState.Retryable := False;
      Inc(FEpoch);
    end;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.Expire;
begin
  FLock.Acquire;
  try
    if (FState.Status = 'deferred') and (GetTickCount64 >= FDeadline) then
    begin
      FState.Status := 'timed_out';
      FState.ReasonCode := 'timeout';
      FState.MessageText := 'Die SDK-Operation ist noch offen; Timeout bricht den Debuggee nicht ab.';
      FState.Retryable := False;
    end;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.MarkReentrant;
begin
  FLock.Acquire;
  try Inc(FEpoch); FState.ContextChanged := True; finally FLock.Release; end;
end;

procedure TEvaluationJob.BeginCall(const AModify: Boolean; const AValue: string);
begin
  FLock.Acquire;
  try
    FState.CallActive := True;
    FReceived := False;
    if AModify then
    begin
      FPhase := epModifyCall;
      FModifyText := AValue;
      FState.ModifyAttempted := True;
      FState.Modified := -1;
      FState.CanModify := -1;
      FState.HasAddress := False;
      FState.HasSize := False;
      FState.HasValue := False;
      FState.ResultText := '';
      FState.Truncated := False;
      FState.HasReturnCode := False;
    end
    else
    begin
      FPhase := epEvaluateCall;
      FAtomicEpoch := FEpoch;
    end;
  finally FLock.Release; end;
end;

function TEvaluationJob.MayModify: Boolean;
begin
  FLock.Acquire;
  try
    Result := (FState.Status = 'ok') and (FState.CanModify = 1) and not FState.Destroyed and
      not FState.ContextChanged and (FAtomicEpoch = FEpoch) and (FPhase = epFinished);
  finally FLock.Release; end;
end;

procedure TEvaluationJob.UseCompletion;
var
  LTerminalStatus: string;
begin
  // FLock is held. The callback payload belongs to this request, not SDK out vars.
  FState.Outstanding := False;
  FPhase := epFinished;
  LTerminalStatus := '';
  if (FState.Status = 'timed_out') or (FState.Status = 'cancelled') then LTerminalStatus := FState.Status;
  FState.ResultText := FCompletion.ResultText;
  FState.Truncated := FCompletion.Truncated;
  FState.ReturnCode := FCompletion.ReturnCode;
  FState.HasReturnCode := True;
  if FCompletion.ReturnCode <> 0 then
  begin
    if FState.ModifyAttempted then FState.Modified := 0;
    FState.Status := 'error';
    FState.ReasonCode := 'sdk_error';
    FState.SDKResult := 'error';
  end;
  if FCompletion.ReturnCode = 0 then
  begin
    FState.SDKResult := 'ok';
    FState.Status := 'ok';
    FState.ReasonCode := '';
    FState.MessageText := '';
    FState.CanModify := FCompletion.CanModify;
    FState.HasAddress := FCompletion.HasAddress;
    FState.ResultAddress := FCompletion.ResultAddress;
    FState.HasSize := FCompletion.HasSize;
    FState.ResultSize := FCompletion.ResultSize;
    if FState.ModifyAttempted then FState.Modified := 1;
    if FPrecheckDeferred then
    begin
      FState.Status := 'error';
      FState.ReasonCode := 'precheck_deferred';
      FState.MessageText := 'Der Vorab-Evaluate war deferred; Modify wurde nicht gestartet. Erneut ausdrücklich anfordern.';
      FState.Retryable := True;
    end;
  end;
  if LTerminalStatus <> '' then
  begin
    FState.Status := LTerminalStatus;
    FState.MessageText := 'Der SDK-Callback ist nach Timeout oder Abbruch eingetroffen; das tatsächliche SDK-Ergebnis ist enthalten.';
    FState.Retryable := False;
  end;
end;

procedure TEvaluationJob.FinishCall(const AResult: TOTAEvaluateResult; const AText: string; const ATruncated: Boolean;
  const ACanModify: Boolean; const AAddress: TOTAAddress; const ASize: LongWord; const AValue: Int64; const AModify: Boolean);
begin
  FLock.Acquire;
  try
    FState.CallActive := False;
    if (FState.Status = 'cancelled') or FState.Destroyed then
    begin
      FState.Outstanding := (AResult = erDeferred) and not FReceived and not FState.Destroyed;
      Exit;
    end;
    FState.CanModify := -1;
    FState.HasAddress := False;
    FState.HasSize := False;
    FState.HasValue := False;
    case AResult of
      erDeferred:
        begin
          FState.SDKResult := 'deferred';
          FState.Status := 'deferred';
          FState.Outstanding := True;
          if AModify then FPhase := epModifyPending else FPhase := epEvaluatePending;
          FPrecheckDeferred := not AModify and (FState.Operation = 'modify');
          if FPrecheckDeferred then
          begin
            FState.ReasonCode := 'precheck_deferred';
            FState.MessageText := 'Modify wurde nicht gestartet; nur der Vorab-Evaluate ist noch offen.';
          end;
          if FReceived then UseCompletion;
        end;
      erBusy:
        begin
          FState.SDKResult := 'busy';
          FState.Status := 'busy';
          FState.ReasonCode := 'evaluator_busy';
          FState.Retryable := True;
          FState.Outstanding := False;
          if AModify then FState.Modified := 0;
          FPhase := epFinished;
        end;
      erError, erOK:
        begin
          FState.Outstanding := False;
          FPhase := epFinished;
          FState.ResultText := AText;
          FState.Truncated := ATruncated;
          if AResult = erError then
          begin
            if AModify then FState.Modified := 0;
            FState.Status := 'error';
            FState.SDKResult := 'error';
            FState.ReasonCode := 'sdk_error';
          end
          else
          begin
            FState.Status := 'ok';
            FState.SDKResult := 'ok';
            FState.HasValue := True;
            FState.ResultValue := AValue;
            if AModify then FState.Modified := 1
            else
            begin
              FState.CanModify := Ord(ACanModify);
              FState.ResultAddress := AAddress;
              FState.ResultSize := ASize;
              FState.HasAddress := True;
              FState.HasSize := True;
            end;
          end;
        end;
    end;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.Receive(const AExpression, AResult: string; const ACanModify: Integer;
  const AAddress: TOTAAddress; const ASize: LongWord; const AReturnCode: Integer; const AModify: Boolean);
var
  LKeepAlive: IOTAThreadNotifier;
  LMatchesPhase: Boolean;
begin
  LKeepAlive := Self;
  FLock.Acquire;
  try
    if AModify then LMatchesPhase := FPhase in [epModifyCall, epModifyPending]
    else LMatchesPhase := FPhase in [epEvaluateCall, epEvaluatePending];
    if not LMatchesPhase then
    begin
      if FState.CallActive then begin Inc(FEpoch); FState.ContextChanged := True; end;
      Exit;
    end;
    if AExpression <> FRequest.Expression then
      if not AModify or (AExpression <> FModifyText) then
      begin
        if FState.CallActive then begin Inc(FEpoch); FState.ContextChanged := True; end;
        Exit;
      end;
    if FReceived then Exit;
    FReceived := True;
    FCompletion := Default(TEvaluationSnapshot);
    FCompletion.ResultText := BoundedText(AResult, FRequest.MaximumCharacters, FCompletion.Truncated);
    FCompletion.ReturnCode := AReturnCode;
    FCompletion.CanModify := ACanModify;
    if not AModify and (AReturnCode = 0) then
    begin
      FCompletion.HasAddress := True;
      FCompletion.ResultAddress := AAddress;
      FCompletion.HasSize := True;
      FCompletion.ResultSize := ASize;
    end;
    if not FState.CallActive then UseCompletion;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.AfterSave; begin end;
procedure TEvaluationJob.BeforeSave; begin end;
procedure TEvaluationJob.Modified; begin end;

procedure TEvaluationJob.Destroyed;
var
  LKeepAlive: IOTAThreadNotifier;
begin
  LKeepAlive := Self;
  FLock.Acquire;
  try
    FState.Destroyed := True;
    FState.RegistrationUncertain := False;
    FState.Outstanding := False;
    FNotifierIndex := -1;
    FThread := nil;
    FProcess := nil;
    FRequest.FExpectedProcess := nil;
    FRequest.FExpectedThread := nil;
    Inc(FEpoch);
    if FPhase <> epFinished then
    begin
      FState.Status := 'cancelled';
      FState.ReasonCode := 'thread_destroyed';
      FState.MessageText := 'Der zugeordnete Debug-Thread wurde zerstört.';
    end;
  finally FLock.Release; end;
end;

procedure TEvaluationJob.ThreadNotify(Reason: TOTANotifyReason);
begin
  if Reason in [nrRunning, nrException, nrFault] then MarkReentrant;
end;

procedure TEvaluationJob.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean; ResultAddress, ResultSize: LongWord; ReturnCode: Integer);

begin Receive(ExprStr, ResultStr, Ord(CanModify), TOTAAddress(ResultAddress), ResultSize, ReturnCode, False); end;

procedure TEvaluationJob.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean; ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer);

begin Receive(ExprStr, ResultStr, Ord(CanModify), ResultAddress, ResultSize, ReturnCode, False); end;

procedure TEvaluationJob.ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
begin Receive(ExprStr, ResultStr, -1, 0, 0, ReturnCode, True); end;

function ResolveTarget(const ARequest: TDAIEvaluationRequest; out AProcess: IOTAProcess; out AThread: IOTAThread): string;
var
  LDebugger: IOTADebuggerServices;
  LOwner: IOTAProcess;
  I, LCount: Integer;
begin
  AProcess := nil;
  AThread := nil;
  Result := 'debugger_unavailable';
  if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then Exit;
  Result := 'process_not_found';
  LCount := LDebugger.ProcessCount;
  if (LCount < 0) or (LCount > 10000) then Exit;
  if ARequest.ProcessId = 0 then AProcess := LDebugger.CurrentProcess
  else
    for I := 0 to LCount - 1 do
    begin
      AProcess := LDebugger.Processes[I];
      if AProcess <> nil then if AProcess.OSProcessId = ARequest.ProcessId then Break;
      AProcess := nil;
    end;
  if AProcess = nil then Exit;
  Result := 'process_running';
  if not (AProcess.ProcessState in [psStopped, psFault, psResFault, psException]) then Exit;
  Result := 'thread_not_found';
  LCount := AProcess.ThreadCount;
  if (LCount < 0) or (LCount > 100000) then Exit;
  if ARequest.ThreadId = 0 then AThread := AProcess.CurrentThread
  else
    for I := 0 to LCount - 1 do
    begin
      AThread := AProcess.Threads[I];
      if AThread <> nil then if AThread.OSThreadID = ARequest.ThreadId then Break;
      AThread := nil;
    end;
  if AThread = nil then Exit;
  Result := 'thread_running';
  if AThread.State <> tsStopped then Exit;
  Result := 'thread_owner_mismatch';
  LOwner := AThread.OwningProcess;
  if LOwner = nil then Exit;
  if LOwner <> AProcess then Exit;
  if LOwner.OSProcessId <> AProcess.OSProcessId then Exit;
  if ARequest.FPrepared then
    if (IInterface(AProcess) <> ARequest.FExpectedProcess) or (IInterface(AThread) <> ARequest.FExpectedThread) then
    begin
      Result := 'prepared_target_changed';
      Exit;
    end;
  Result := '';
end;

constructor TEvaluationBroker.Create;
begin inherited; FJobs := TList<IEvaluationJob>.Create; end;

destructor TEvaluationBroker.Destroy;
begin FJobs.Free; inherited; end;

procedure TEvaluationBroker.Sweep;
var
  LJob: IEvaluationJob;
  LState: TEvaluationSnapshot;
  I, LCompleted: Integer;
begin
  if FSweeping or FInSDK then Exit;
  FSweeping := True;
  try
  LCompleted := 0;
  for LJob in FJobs do
  begin
    LJob.Expire;
    LState := LJob.Snapshot;
    if not LState.Outstanding and not LState.CallActive then
    begin
      FInSDK := True;
      FExecuting := LJob;
      try LJob.Detach; finally FExecuting := nil; FInSDK := False; end;
      LState := LJob.Snapshot;
      if not LState.Outstanding then Inc(LCompleted);
    end;
  end;
  I := 0;
  while (LCompleted > CMaximumHistory) and (I < FJobs.Count) do
  begin
    LState := FJobs[I].Snapshot;
    if not LState.Outstanding and not LState.CallActive then
    begin FJobs.Delete(I); Dec(LCompleted); end else Inc(I);
  end;
  finally FSweeping := False; end;
end;

function TEvaluationBroker.Execute(const ARequest: TDAIEvaluationRequest; const AValue: string; const AModify: Boolean): TJSONObject;
var
  LJob: TEvaluationJob;
  LKeepJob, LExisting: IEvaluationJob;
  LState: TEvaluationSnapshot;
  LProcess, LCheckProcess: IOTAProcess;
  LThread, LCheckThread: IOTAThread;
  LRequest: TDAIEvaluationRequest;
  LResult: TOTAEvaluateResult;
  LBuffer: TArray<Char>;
  LFormat: AnsiString;
  LSideEffects: TOTAEvalSideEffects;
  LCanModify, LTruncated: Boolean;
  LAddress: TOTAAddress;
  LSize, LValue: LongWord;
  LModifyValue: Integer;
  LReason, LText: string;
  LCount: Integer;
begin
  if FStopped or GStopped then raise EInvalidOperation.Create('Der Evaluator wurde beendet; ein IDE-Neustart ist erforderlich.');
  LRequest := CheckedRequest(ARequest, AModify, AValue);
  LJob := TEvaluationJob.Create(LRequest, AModify, Self);
  LKeepJob := LJob;
  if FInSDK then
  begin
    if FExecuting <> nil then FExecuting.MarkReentrant;
    LJob.Fail('evaluator_reentrant', 'Eine SDK-Auswertung ist bereits aktiv.', True);
    Exit(SnapshotJson(LJob.Snapshot));
  end;
  Sweep;
  LCount := 0;
  for LExisting in FJobs do if LExisting.Snapshot.Outstanding then Inc(LCount);
  if LCount >= CMaximumOutstanding then
  begin
    LJob.Fail('pending_capacity', '32 SDK-Auswertungen sind noch nicht abgeschlossen.', False);
    Exit(SnapshotJson(LJob.Snapshot));
  end;
  LReason := ResolveTarget(LRequest, LProcess, LThread);
  if LReason <> '' then
  begin
    LJob.Fail(LReason, 'Ein eigener angehaltener Debug-Prozess und Thread sind erforderlich.',
      (LReason = 'process_running') or (LReason = 'thread_running'));
    Exit(SnapshotJson(LJob.Snapshot));
  end;
  for LExisting in FJobs do
  begin
    LState := LExisting.Snapshot;
    if LState.Outstanding and (LState.ProcessId = LProcess.OSProcessId) and (LState.ThreadId = LThread.OSThreadID) then
    begin
      LJob.Fail('thread_pending', 'Für diesen Thread ist eine SDK-Auswertung noch offen.', True);
      Exit(SnapshotJson(LJob.Snapshot));
    end;
  end;
  LJob.SetTarget(LProcess, LThread);
  FJobs.Add(LKeepJob);
  FInSDK := True;
  FExecuting := LKeepJob;
  try
    try
      if not FModulePinned then begin PinEvaluationModule; FModulePinned := True; end;
      LJob.Attach;
      LState := LJob.Snapshot;
      if LState.Destroyed or (LState.Status = 'cancelled') then Exit(SnapshotJson(LState));
      LReason := ResolveTarget(LRequest, LCheckProcess, LCheckThread);
      if (LReason <> '') or (LCheckProcess <> LProcess) or (LCheckThread <> LThread) then
        raise EInvalidOperation.Create('Das Debug-Ziel hat sich vor dem SDK-Aufruf geändert.');
      LState := LJob.Snapshot;
      if LState.Destroyed or (LState.Status = 'cancelled') then Exit(SnapshotJson(LState));
      // The receiver retains all pointer-backed storage even after deferred or
      // ambiguous SDK exceptions; providers must never receive stack out vars.
      LBuffer := LJob.FBuffer;
      LFormat := LJob.FFormat;
      LSideEffects := eseNone;
      if LRequest.SideEffects = 'properties' then LSideEffects := esePropertiesOnly;
      if LRequest.SideEffects = 'all' then LSideEffects := eseAll;
      LJob.BeginCall(False);
      LResult := LThread.Evaluate(LRequest.Expression, PChar(LBuffer), Length(LBuffer), LJob.FRawCanModify,
        LSideEffects, PAnsiChar(LFormat), LJob.FRawAddress, LJob.FRawSize, LJob.FRawValue, LRequest.SourceFile, LRequest.Line);
      LText := ''; LTruncated := False;
      if LResult in [erOK, erError] then LText := BufferText(LBuffer, LRequest.MaximumCharacters, LTruncated);
      LCanModify := False; LAddress := 0; LSize := 0; LValue := 0;
      if LResult = erOK then
      begin
        LCanModify := LJob.FRawCanModify; LAddress := LJob.FRawAddress; LSize := LJob.FRawSize; LValue := LJob.FRawValue;
      end;
      LJob.FinishCall(LResult, LText, LTruncated, LCanModify, LAddress, LSize, LValue, False);
      if AModify and (LResult = erOK) then
      begin
        // Nothing between these calls pumps the IDE or asks the provider for UI state.
        if not LJob.MayModify or FStopped then
        begin
          if not LCanModify then LJob.Fail('not_modifiable', 'Das SDK erlaubt keine Änderung dieses Ausdrucks.')
          else LJob.Fail('context_changed', 'Reentranz oder eine Threadänderung verhindert die sichere Änderung.', True);
        end
        else
        begin
          FillChar(LBuffer[0], Length(LBuffer) * SizeOf(Char), 0);
          LJob.BeginCall(True, AValue);
          LResult := LThread.Modify(AValue, PChar(LBuffer), Length(LBuffer), LJob.FRawModifyValue);
          LText := ''; LTruncated := False;
          if LResult in [erOK, erError] then LText := BufferText(LBuffer, LRequest.MaximumCharacters, LTruncated);
          LModifyValue := 0;
          if LResult = erOK then LModifyValue := LJob.FRawModifyValue;
          LJob.FinishCall(LResult, LText, LTruncated, False, 0, 0, LModifyValue, True);
        end;
      end;
    except
      on E: Exception do
      begin
        LJob.SDKException(E.Message);
      end;
    end;
  finally
    FExecuting := nil;
    FInSDK := False;
    Sweep;
  end;
  Result := SnapshotJson(LJob.Snapshot);
end;

function TEvaluationBroker.Status(const AId: string): TJSONObject;
var
  LJob: IEvaluationJob;
  LState: TEvaluationSnapshot;
  LDebugger: IOTADebuggerServices;
begin
  if FInSDK then
  begin
    if FExecuting <> nil then FExecuting.MarkReentrant;
  end
  else Sweep;
  for LJob in FJobs do
  begin
    LState := LJob.Snapshot;
    if LState.Id <> AId then Continue;
    if LState.Outstanding and not LState.RegistrationUncertain and not FInSDK and not FStopped then
      if Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
      begin
        FInSDK := True;
        FExecuting := LJob;
        try
          // One SDK event pass, never a wait loop or a delayed Modify continuation.
          if not FStopped then LDebugger.ProcessDebugEvents;
        finally
          FExecuting := nil;
          FInSDK := False;
          Sweep;
        end;
        LState := LJob.Snapshot;
      end;
    Exit(SnapshotJson(LState));
  end;
  raise EArgumentException.Create('Die Auswertung ist unbekannt oder nicht mehr gespeichert.');
end;

procedure TEvaluationBroker.Stop;
var
  LJob: IEvaluationJob;
begin
  FStopped := True;
  for LJob in FJobs do LJob.Cancel;
  if not FInSDK then Sweep;
end;

class function TDAIEvaluationService.Prepare(const ARequest: TDAIEvaluationRequest): TDAIEvaluationRequest;
var
  LRequest: TDAIEvaluationRequest;
begin
  LRequest := ARequest;
  TDAIOTA.RunOnMainThread(procedure
    var
      LProcess: IOTAProcess;
      LThread: IOTAThread;
      LReason: string;
    begin
      if GStopped then raise EInvalidOperation.Create('Der Evaluator wurde beendet; ein IDE-Neustart ist erforderlich.');
      LReason := ResolveTarget(LRequest, LProcess, LThread);
      if LReason <> '' then raise EInvalidOperation.Create('Debug-Ziel nicht verfügbar: ' + LReason);
      LRequest.ProcessId := LProcess.OSProcessId;
      LRequest.ThreadId := LThread.OSThreadID;
      LRequest.FExpectedProcess := LProcess;
      LRequest.FExpectedThread := LThread;
      LRequest.FPrepared := True;
    end);
  Result := LRequest;
end;

class function TDAIEvaluationService.Evaluate(const ARequest: TDAIEvaluationRequest): TJSONObject;
var
  LBroker: IEvaluationBroker;
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(procedure
    begin
      if GStopped then raise EInvalidOperation.Create('Der Evaluator wurde beendet; ein IDE-Neustart ist erforderlich.');
      if GBroker = nil then GBroker := TEvaluationBroker.Create;
      LBroker := GBroker;
      LResult := LBroker.Execute(ARequest, '', False);
    end);
  Result := LResult;
end;

class function TDAIEvaluationService.Modify(const ARequest: TDAIEvaluationRequest; const AValue: string): TJSONObject;
var
  LBroker: IEvaluationBroker;
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(procedure
    begin
      if GStopped then raise EInvalidOperation.Create('Der Evaluator wurde beendet; ein IDE-Neustart ist erforderlich.');
      if GBroker = nil then GBroker := TEvaluationBroker.Create;
      LBroker := GBroker;
      LResult := LBroker.Execute(ARequest, AValue, True);
    end);
  Result := LResult;
end;

class function TDAIEvaluationService.Status(const ARequestId: string): TJSONObject;
var
  LBroker: IEvaluationBroker;
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(procedure
    begin
      LBroker := GBroker;
      if LBroker = nil then raise EArgumentException.Create('Es ist keine Auswertung gespeichert.');
      LResult := LBroker.Status(ARequestId);
    end);
  Result := LResult;
end;

class procedure TDAIEvaluationService.Shutdown;
begin
  TDAIOTA.RunOnMainThread(procedure
    begin
      GStopped := True;
      if GBroker <> nil then GBroker.Stop;
    end);
end;

initialization
  GBroker := nil;
  GStopped := False;
  GBroker := TEvaluationBroker.Create;

finalization
  TDAIEvaluationService.Shutdown;
  // Pending receivers keep their broker, state and locks independent of globals.
  GBroker := nil;

end.
