program Test.ExpressionUI;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.JSON, System.Hash, Winapi.Windows,
  ToolsAPI, h5u.DAI.OTA.Helpers, h5u.DAI.OTA.ExpressionUI;
type
  TReader = class(TInterfacedObject, IOTAEditReader)
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  TEditor = class(TInterfacedObject, IOTAEditor, IOTASourceEditor, IOTAEditBuffer)
    function GetFileName: string;
    function CreateReader: IOTAEditReader;
    function GetEditViewCount: Integer;
    function GetEditView(Index: Integer): IOTAEditView;
    function GetBlockStart: TOTACharPos;
    function GetBlockAfter: TOTACharPos;
    function GetBlockType: TOTABlockType;
    function GetBlockVisible: Boolean;
  end;
  TPlainEditor = class(TInterfacedObject, IOTAEditor)
    function GetFileName: string;
  end;
  TView = class(TInterfacedObject, IOTAEditView, IOTAEditActions)
    Identity: Integer;
    function GetBuffer: IOTAEditBuffer;
    function GetCursorPos: TOTAEditPos;
    function SameView(const EditView: IOTAEditView): Boolean;
    procedure DoAction(const AAction: string);
    procedure AddWatch;
    procedure AddWatchAtCursor;
    procedure EvaluateModify;
    procedure InspectAtCursor;
  end;
  TThread = class(TInterfacedObject, IOTAThread)
    function GetState: TOTAThreadState;
    function GetOSThreadID: LongWord;
    function GetOwningProcess: IOTAProcess;
  end;
  TProcess = class(TInterfacedObject, IOTAProcess)
    function GetCurrentThread: IOTAThread;
    function GetOSProcessId: LongWord;
    function GetProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
  end;
  TServices = class(TInterfacedObject, IOTAModule, IOTAModuleServices, IOTAEditorServices, IOTADebuggerServices)
    function GetCurrentEditor: IOTAEditor;
    function CurrentModule: IOTAModule;
    function GetTopView: IOTAEditView;
    function GetCurrentProcess: IOTAProcess;
  end;
var
  Checks, Readers, Reads, Calls, SourceBytes, ShortRead, BadRead, Views: Integer;
  FileText, SourceText, ActionText, RequestId, DuringState: string;
  SourceEditor: IOTASourceEditor;
  Editor: IOTAEditor;
  Buffer: IOTAEditBuffer;
  TopView, MemberView: IOTAEditView;
  CurrentProcess: IOTAProcess;
  CurrentThread: IOTAThread;
  Cursor: TOTAEditPos;
  BlockStart, BlockAfter: TOTACharPos;
  BlockType: TOTABlockType;
  BlockVisible, NilModule, NilBuffer, NilReader, WrongOwner, RaiseAction, StopAction, ReenterAction: Boolean;
  DuringActive, DuringStarted, DuringInvoked, ReentryRejected: Boolean;
  ProcessState: TOTAProcessState;
  ThreadState: TOTAThreadState;
  ProcessId, DebuggerId, ThreadId: LongWord;
  Request: TDAIExpressionUIRequest;
procedure Check(const ACondition: Boolean; const AMessage: string);
begin Inc(Checks); if not ACondition then raise EInvalidOperation.Create(AMessage); end;
procedure SDK;
begin if GetCurrentThreadId <> MainThreadID then raise EInvalidOperation.Create('SDK used outside IDE thread.'); end;
function Value(const AJson: TJSONObject; const AName: string): string;
var LValue: TJSONValue;
begin LValue := AJson.GetValue(AName); Check(LValue <> nil, 'Missing ' + AName); Result := LValue.Value; end;
function TReader.GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
var LBytes: TBytes; I: Integer;
begin
  SDK; Inc(Reads);
  if BadRead <> 0 then Exit(BadRead);
  if SourceBytes >= 0 then
  begin
    Result := SourceBytes - Position;
    if Result < 0 then Result := 0;
    if Result > Count then Result := Count;
    if (ShortRead > 0) and (Result > ShortRead) then Result := ShortRead;
    for I := 0 to Result - 1 do Buffer[I] := 'x';
    Exit;
  end;
  LBytes := TEncoding.UTF8.GetBytes(SourceText);
  Result := Length(LBytes) - Position;
  if Result < 0 then Result := 0;
  if Result > Count then Result := Count;
  if (ShortRead > 0) and (Result > ShortRead) then Result := ShortRead;
  if Result > 0 then Move(LBytes[Position], Buffer^, Result);
end;
function TEditor.GetFileName: string; begin SDK; Result := FileText; end;
function TPlainEditor.GetFileName: string; begin SDK; Result := FileText; end;
function TEditor.CreateReader: IOTAEditReader;
begin SDK; Inc(Readers); Result := nil; if not NilReader then Result := TReader.Create; end;
function TEditor.GetEditViewCount: Integer; begin SDK; Result := Views; end;
function TEditor.GetEditView(Index: Integer): IOTAEditView; begin SDK; Result := MemberView; end;
function TEditor.GetBlockStart: TOTACharPos; begin SDK; Result := BlockStart; end;
function TEditor.GetBlockAfter: TOTACharPos; begin SDK; Result := BlockAfter; end;
function TEditor.GetBlockType: TOTABlockType; begin SDK; Result := BlockType; end;
function TEditor.GetBlockVisible: Boolean; begin SDK; Result := BlockVisible; end;
function TView.GetBuffer: IOTAEditBuffer; begin SDK; if NilBuffer then Result := nil else Result := Buffer; end;
function TView.GetCursorPos: TOTAEditPos; begin SDK; Result := Cursor; end;
function TView.SameView(const EditView: IOTAEditView): Boolean;
var LOther: TView;
begin SDK; LOther := EditView as TView; Result := Identity = LOther.Identity; end;
procedure TView.DoAction(const AAction: string);
var LJson: TJSONObject;
begin
  SDK; Inc(Calls); ActionText := AAction;
  LJson := TDAIExpressionUIService.Status(RequestId);
  try
    DuringState := Value(LJson, 'status');
    DuringActive := Value(LJson, 'callback_active') = 'true';
    DuringStarted := Value(LJson, 'action_started') = 'true';
    DuringInvoked := Value(LJson, 'action_invoked') = 'true';
  finally LJson.Free; end;
  if ReenterAction then
    try
      LJson := TDAIExpressionUIService.Invoke(Request); LJson.Free;
    except on E: EInvalidOperation do ReentryRejected := True; end;
  if StopAction then TDAIExpressionUIService.Shutdown;
  if RaiseAction then raise EInvalidOperation.Create('Native action raised.');
end;
procedure TView.AddWatch; begin DoAction('add_watch'); end;
procedure TView.AddWatchAtCursor; begin DoAction('watch_at_cursor'); end;
procedure TView.EvaluateModify; begin DoAction('evaluate_modify'); end;
procedure TView.InspectAtCursor; begin DoAction('inspect_at_cursor'); end;
function TThread.GetState: TOTAThreadState; begin SDK; Result := ThreadState; end;
function TThread.GetOSThreadID: LongWord; begin SDK; Result := ThreadId; end;
function TThread.GetOwningProcess: IOTAProcess;
begin SDK; if WrongOwner then Result := nil else Result := CurrentProcess; end;
function TProcess.GetCurrentThread: IOTAThread; begin SDK; Result := CurrentThread; end;
function TProcess.GetOSProcessId: LongWord; begin SDK; Result := ProcessId; end;
function TProcess.GetProcessId: LongWord; begin SDK; Result := DebuggerId; end;
function TProcess.GetProcessState: TOTAProcessState; begin SDK; Result := ProcessState; end;
function TServices.GetCurrentEditor: IOTAEditor; begin SDK; Result := Editor; end;
function TServices.CurrentModule: IOTAModule;
begin SDK; if NilModule then Result := nil else Result := Self; end;
function TServices.GetTopView: IOTAEditView; begin SDK; Result := TopView; end;
function TServices.GetCurrentProcess: IOTAProcess; begin SDK; Result := CurrentProcess; end;
procedure Fixture;
var LEditor: TEditor; LView: TView;
begin
  FileText := 'C:\Fixture\Source.pas'; SourceText := 'unit Source; // ä'#13#10'interface'#13#10'implementation'#13#10'end.';
  SourceBytes := -1; ShortRead := 0; BadRead := 0; Views := 1;
  NilModule := False; NilBuffer := False; NilReader := False; WrongOwner := False;
  RaiseAction := False; StopAction := False; ReenterAction := False;
  Cursor.Line := 2; Cursor.Col := 5;
  BlockStart.Line := 2; BlockStart.CharIndex := 2; BlockAfter.Line := 2; BlockAfter.CharIndex := 5;
  BlockType := btNonInclusive; BlockVisible := True;
  ProcessId := 4242; DebuggerId := 7; ThreadId := 123; ProcessState := psStopped; ThreadState := tsStopped;
  LEditor := TEditor.Create; SourceEditor := LEditor; Editor := LEditor; Buffer := LEditor;
  LView := TView.Create; LView.Identity := 10; TopView := LView;
  LView := TView.Create; LView.Identity := 10; MemberView := LView;
  CurrentThread := TThread.Create; CurrentProcess := TProcess.Create; BorlandIDEServices := TServices.Create;
end;
procedure ExpectPrepareFailure(const AAction: string; const AFile: string = '');
var LRejected: Boolean;
begin
  LRejected := False;
  try TDAIExpressionUIService.Prepare(AAction, AFile);
  except on E: Exception do LRejected := True; end;
  Check(LRejected, 'Expected prepare failure.');
end;
procedure ExpectInvokeFailure;
var LRejected: Boolean; LJson: TJSONObject;
begin
  LRejected := False;
  try LJson := TDAIExpressionUIService.Invoke(Request); LJson.Free;
  except on E: Exception do LRejected := True; end;
  Check(LRejected, 'Expected snapshot failure.');
end;
procedure Queue;
var LJson: TJSONObject; LCalls: Integer;
begin
  LCalls := Calls; LJson := TDAIExpressionUIService.Invoke(Request);
  try
    RequestId := Value(LJson, 'request_id');
    Check(Value(LJson, 'status') = 'queued', 'Must queue asynchronously.');
    Check(Value(LJson, 'action_invoked') = 'false', 'Queued action not invoked.');
    Check(LJson.GetValue('dialog_opened') is TJSONNull, 'Dialog visibility must remain unknown.');
  finally LJson.Free; end;
  Check(Calls = LCalls, 'Invoke executed native action synchronously.');
end;
procedure Finished(const AState: string; const AInvoked: Boolean);
var LJson: TJSONObject;
begin
  CheckSynchronize;
  LJson := TDAIExpressionUIService.Status(RequestId);
  try
    Check(Value(LJson, 'status') = AState, 'Unexpected final state: ' + LJson.ToJSON);
    Check((Value(LJson, 'action_invoked') = 'true') = AInvoked, 'Incorrect action completion flag.');
    Check(Value(LJson, 'callback_active') = 'false', 'Callback retained active status after return.');
  finally LJson.Free; end;
end;
procedure NormalTests;
var LReads, LCalls, I: Integer; LJson: TJSONObject; LFirstId, LAction: string; LView: TView;
begin
  LReads := Reads;
  Check(TDAIExpressionUIService.CurrentFileName = FileText, 'Metadata filename.');
  Check(Reads = LReads, 'Metadata accessor read source.');
  ExpectPrepareFailure('unknown'); ExpectPrepareFailure('add_watch'#0);
  ExpectPrepareFailure('add_watch', 'C:\Unauthorized\Other.pas');
  Check(Reads = LReads, 'Expected-file mismatch accessed source.');
  NilModule := True; ExpectPrepareFailure('add_watch'); NilModule := False;
  Editor := TPlainEditor.Create; ExpectPrepareFailure('add_watch'); Editor := SourceEditor;
  NilBuffer := True; ExpectPrepareFailure('add_watch'); NilBuffer := False;
  Views := 65; ExpectPrepareFailure('add_watch'); Views := 1;
  LView := TView.Create; LView.Identity := 11; MemberView := LView;
  ExpectPrepareFailure('add_watch'); LView.Identity := 10;
  NilReader := True; ExpectPrepareFailure('add_watch'); NilReader := False;
  BadRead := -1; ExpectPrepareFailure('add_watch'); BadRead := 9000; ExpectPrepareFailure('add_watch'); BadRead := 0;
  SourceBytes := 16 * 1024 * 1024 + 1; ExpectPrepareFailure('add_watch');
  SourceBytes := 16 * 1024 * 1024; Request := TDAIExpressionUIService.Prepare('add_watch');
  Check(Length(Request.SourceSha256) = 64, 'Exactly 16MiB is accepted.'); SourceBytes := -1;
  ShortRead := 3; Request := TDAIExpressionUIService.Prepare('  ADD_WATCH  ');
  Check(Request.SourceSha256 = THashSHA2.GetHashString(SourceText), 'UTF8 streaming and short reads must hash all bytes.');
  ShortRead := 0;
  Inc(Cursor.Col); ExpectInvokeFailure; Dec(Cursor.Col);
  Inc(BlockStart.CharIndex); ExpectInvokeFailure; Dec(BlockStart.CharIndex);
  Inc(BlockAfter.Line); ExpectInvokeFailure; Dec(BlockAfter.Line);
  BlockType := btColumn; ExpectInvokeFailure; BlockType := btNonInclusive;
  BlockVisible := False; ExpectInvokeFailure; BlockVisible := True;
  SourceText := SourceText + ' '; ExpectInvokeFailure; SetLength(SourceText, Length(SourceText) - 1);
  for LAction in TArray<string>.Create('add_watch', 'watch_at_cursor', 'evaluate_modify', 'inspect_at_cursor') do
  begin
    Request := TDAIExpressionUIService.Prepare(LAction); Queue;
    ExpectInvokeFailure;
    Finished('invoked', True);
    Check(ActionText = LAction, 'Wrong SDK action.');
    Check((DuringState = 'invoking') and DuringActive and DuringStarted and not DuringInvoked, 'In-flight status inaccurate.');
  end;
  Request := TDAIExpressionUIService.Prepare('add_watch'); Queue;
  LCalls := Calls; Inc(Cursor.Line); Finished('error', False); Dec(Cursor.Line);
  Check(Calls = LCalls, 'Queued changed cursor acted.');
  Request := TDAIExpressionUIService.Prepare('add_watch'); Queue;
  LReads := Reads; FileText := 'C:\Unauthorized\Other.pas'; Finished('error', False);
  Check(Reads = LReads, 'Queued unauthorized file accessed source.'); FileText := 'C:\Fixture\Source.pas';
  Request := TDAIExpressionUIService.Prepare('add_watch'); Queue;
  SourceText := SourceText + ' '; Finished('error', False); SetLength(SourceText, Length(SourceText) - 1);
  CurrentProcess := nil; ExpectPrepareFailure('evaluate_modify'); ExpectPrepareFailure('inspect_at_cursor');
  Request := TDAIExpressionUIService.Prepare('watch_at_cursor'); Queue; Finished('invoked', True);
  CurrentProcess := TProcess.Create;
  ProcessState := psRunning; ExpectPrepareFailure('evaluate_modify'); ProcessState := psStopped;
  ThreadState := tsRunnable; ExpectPrepareFailure('inspect_at_cursor'); ThreadState := tsStopped;
  WrongOwner := True; ExpectPrepareFailure('evaluate_modify'); WrongOwner := False;
  Request := TDAIExpressionUIService.Prepare('evaluate_modify'); Inc(ThreadId); ExpectInvokeFailure; Dec(ThreadId);
  Queue; Inc(ProcessId); Finished('error', False); Dec(ProcessId);
  Request := TDAIExpressionUIService.Prepare('inspect_at_cursor'); Queue;
  ProcessState := psRunning; Finished('error', False); ProcessState := psStopped;
  Request := TDAIExpressionUIService.Prepare('add_watch'); RaiseAction := True; Queue; Finished('error', False); RaiseAction := False;
  ReenterAction := True; Request := TDAIExpressionUIService.Prepare('add_watch'); Queue; Finished('invoked', True);
  Check(ReentryRejected, 'Reentrant Invoke was not rejected.'); ReenterAction := False;
  LFirstId := RequestId;
  for I := 1 to 16 do begin Request := TDAIExpressionUIService.Prepare('add_watch'); Queue; Finished('invoked', True); end;
  try LJson := TDAIExpressionUIService.Status(LFirstId); LJson.Free; Check(False, 'History exceeded 16 entries.');
  except on E: EArgumentException do Check(True, 'Bounded history.'); end;
  LJson := TDAIExpressionUIService.Status(RequestId); LJson.Free;
  try LJson := TDAIExpressionUIService.Status(''); LJson.Free; Check(False, 'Empty status id accepted.');
  except on E: EArgumentException do Check(True, 'Empty status rejected.'); end;
end;
procedure ShutdownTests;
var LCalls: Integer;
begin
  if ParamStr(1) = '--empty-shutdown' then TDAIExpressionUIService.Shutdown
  else
  begin
    Request := TDAIExpressionUIService.Prepare('add_watch'); Queue; LCalls := Calls;
    if ParamStr(1) = '--running-shutdown' then
    begin StopAction := True; Finished('cancelled', True); Check(Calls = LCalls + 1, 'Running action did not return.'); end
    else
    begin TDAIExpressionUIService.Shutdown; Finished('cancelled', False); Check(Calls = LCalls, 'Stopped queued callback ran.'); end;
  end;
  ExpectPrepareFailure('add_watch');
  TDAIExpressionUIService.Shutdown;
end;
begin
  try
    Fixture;
    if ParamCount = 0 then NormalTests else ShutdownTests;
    Writeln('PASS ExpressionUI: ', Checks, ' checks ', ParamStr(1));
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
