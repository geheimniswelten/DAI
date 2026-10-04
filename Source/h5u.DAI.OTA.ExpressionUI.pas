unit h5u.DAI.OTA.ExpressionUI;

interface

uses
  System.JSON,
  ToolsAPI;

type
  TDAIExpressionUIRequest = record
    Action, FileName, SourceSha256: string;
    Cursor: TOTAEditPos;
    BlockStart, BlockAfter: TOTACharPos;
    BlockType: TOTABlockType;
    BlockVisible: Boolean;
    ProcessId, DebuggerProcessId, ThreadId: LongWord;
  end;

  TDAIExpressionUIService = class sealed
  public
    class function CurrentFileName: string; static;
    class function Prepare(const AAction: string; const AExpectedFile: string = ''): TDAIExpressionUIRequest; static;
    class function Invoke(const ARequest: TDAIExpressionUIRequest): TJSONObject; static;
    class function Status(const ARequestId: string): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.Hash,
  System.Generics.Collections,
  Winapi.Windows,
  h5u.DAI.OTA.Helpers;

const
  CMaximumSourceBytes = 16 * 1024 * 1024;
  CMaximumViews = 64;
  CMaximumJobs = 16;

type
  TExpressionUIJob = class
    Id, State, Reason: string;
    Request: TDAIExpressionUIRequest;
    CallbackActive, ActionStarted, ActionInvoked: Boolean;
    function ToJson: TJSONObject;
  end;

  TExpressionUIPump = class
  private
    FJobs: TObjectList<TExpressionUIJob>;
    FActive: TExpressionUIJob;
    FRunning, FStopped: Boolean;
    procedure RunQueued;
  public
    constructor Create;
    destructor Destroy; override;
    function Enqueue(const ARequest: TDAIExpressionUIRequest): TJSONObject;
    function FindStatus(const AId: string): TJSONObject;
    procedure Stop;
  end;

var
  GPump: TExpressionUIPump;
  GServiceStopped: Boolean;

function ExpressionUIGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure PinExpressionUIModule;
var
  LModule: HMODULE;
begin
  // Native actions can pump a package-unload request inside a modal call.
  if not ExpressionUIGetModuleHandleExW($00000004 or $00000001,
    PChar(Pointer(@PinExpressionUIModule)), LModule) then RaiseLastOSError;
end;

function CheckedAction(const AAction: string): string;
begin
  if (Pos(#0, AAction) <> 0) or (Length(AAction) > 64) then
    raise EArgumentException.Create('Ungültige Debugger-Editoraktion.');
  Result := LowerCase(Trim(AAction));
  if (Result <> 'add_watch') and (Result <> 'watch_at_cursor') and
     (Result <> 'evaluate_modify') and (Result <> 'inspect_at_cursor') then
    raise EArgumentException.Create('action muss add_watch, watch_at_cursor, evaluate_modify oder inspect_at_cursor sein.');
end;

procedure CurrentSource(out ASource: IOTASourceEditor; out AView: IOTAEditView; out AFileName: string);
var
  LModules: IOTAModuleServices;
  LEditors: IOTAEditorServices;
  LModule: IOTAModule;
  LBuffer: IOTAEditBuffer;
  LMember: IOTAEditView;
  I, LCount: Integer;
  LFound: Boolean;
begin
  ASource := nil;
  AView := nil;
  AFileName := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModules) or
     not Supports(BorlandIDEServices, IOTAEditorServices, LEditors) then
    raise EInvalidOperation.Create('Die IDE-Editordienste sind nicht verfügbar.');
  LModule := LModules.CurrentModule;
  if LModule = nil then raise EInvalidOperation.Create('Der aktuelle IDE-Editor ist kein Quelleditor.');
  if not Supports(LModule.CurrentEditor, IOTASourceEditor, ASource) then
    raise EInvalidOperation.Create('Der aktuelle IDE-Editor ist kein Quelleditor.');
  AView := LEditors.TopView;
  if AView = nil then raise EInvalidOperation.Create('Es ist keine aktuelle Quelltextansicht verfügbar.');
  LBuffer := AView.Buffer;
  if LBuffer = nil then raise EInvalidOperation.Create('Der aktuelle Editorpuffer ist nicht verfügbar.');
  AFileName := ASource.FileName;
  if (Trim(AFileName) = '') or (Pos(#0, AFileName) <> 0) then
    raise EInvalidOperation.Create('Der aktuelle Quelleditor besitzt keinen eindeutigen Dateipfad.');
  if not TDAIOTA.SameFile(AFileName, LBuffer.FileName) then
    raise EInvalidOperation.Create('Die aktuelle Ansicht gehört nicht zum aktuellen Quelleditor.');
  LCount := ASource.EditViewCount;
  if (LCount < 1) or (LCount > CMaximumViews) then
    raise EInvalidOperation.Create('Die aktuelle Quelltextansicht lässt sich nicht eindeutig zuordnen.');
  LFound := False;
  for I := 0 to LCount - 1 do
  begin
    LMember := ASource.EditViews[I];
    if LMember <> nil then if AView.SameView(LMember) then LFound := True;
  end;
  if not LFound then raise EInvalidOperation.Create('Die aktuelle Ansicht gehört nicht zum aktuellen Quelleditor.');
  AFileName := TDAIOTA.NormalizeFileName(AFileName);
end;

function SourceHash(const ASource: IOTASourceEditor): string;
var
  LReader: IOTAEditReader;
  LBuffer: array[0..8191] of Byte;
  LHash: THashSHA2;
  LOffset, LRead, LCount: Integer;
begin
  LReader := ASource.CreateReader;
  if LReader = nil then raise EInvalidOperation.Create('Der Quelltext kann nicht aus dem Editor gelesen werden.');
  LHash := THashSHA2.Create;
  LOffset := 0;
  repeat
    LCount := Length(LBuffer);
    if LCount > CMaximumSourceBytes - LOffset + 1 then LCount := CMaximumSourceBytes - LOffset + 1;
    LRead := LReader.GetText(LOffset, PAnsiChar(@LBuffer[0]), LCount);
    if (LRead < 0) or (LRead > LCount) then raise EInvalidOperation.Create('Der Editor lieferte eine ungültige Quelltextlänge.');
    if LRead > CMaximumSourceBytes - LOffset then
      raise EInvalidOperation.Create('Der Quelltext überschreitet die Grenze von 16 MiB.');
    if LRead > 0 then
    begin
      LHash.Update(LBuffer[0], Cardinal(LRead));
      Inc(LOffset, LRead);
    end;
  until LRead = 0;
  // Hash the actual UTF-8 editor bytes; never retain or return source text.
  Result := LHash.HashAsString;
end;

procedure ReadDebugContext(var ARequest: TDAIExpressionUIRequest);
var
  LDebugger: IOTADebuggerServices;
  LProcess, LOwner: IOTAProcess;
  LThread: IOTAThread;
begin
  if (ARequest.Action <> 'evaluate_modify') and (ARequest.Action <> 'inspect_at_cursor') then Exit;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
    raise EInvalidOperation.Create('Der Debuggerdienst ist nicht verfügbar.');
  LProcess := LDebugger.CurrentProcess;
  if LProcess = nil then raise EInvalidOperation.Create('Es gibt keinen aktuellen Debug-Prozess.');
  LThread := LProcess.CurrentThread;
  if LThread = nil then raise EInvalidOperation.Create('Es gibt keinen aktuellen Debug-Thread.');
  if not (LProcess.ProcessState in [psStopped, psFault, psResFault, psException]) or (LThread.State <> tsStopped) then
    raise EInvalidOperation.Create('Der aktuelle Debug-Prozess und Thread müssen angehalten sein.');
  LOwner := LThread.OwningProcess;
  if LOwner = nil then raise EInvalidOperation.Create('Der Prozess des Debug-Threads ist nicht verfügbar.');
  if (LOwner.OSProcessId <> LProcess.OSProcessId) or (LOwner.ProcessId <> LProcess.ProcessId) then
    raise EInvalidOperation.Create('Der aktuelle Thread gehört nicht zum aktuellen Debug-Prozess.');
  ARequest.ProcessId := LProcess.OSProcessId;
  ARequest.DebuggerProcessId := LProcess.ProcessId;
  ARequest.ThreadId := LThread.OSThreadID;
end;

function Capture(const AAction, AExpectedFile: string; out AActions: IOTAEditActions): TDAIExpressionUIRequest;
var
  LSource: IOTASourceEditor;
  LView: IOTAEditView;
begin
  Result := Default(TDAIExpressionUIRequest);
  Result.Action := CheckedAction(AAction);
  if Pos(#0, AExpectedFile) <> 0 then raise EArgumentException.Create('file darf kein NUL enthalten.');
  CurrentSource(LSource, LView, Result.FileName);
  // Compare metadata before accessing any potentially unauthorized source bytes.
  if (AExpectedFile <> '') and not TDAIOTA.SameFile(Result.FileName, AExpectedFile) then
    raise EInvalidOperation.Create('Die aktive Quelldatei hat sich seit der Zugriffsprüfung geändert.');
  if not Supports(LView, IOTAEditActions, AActions) then
    raise EInvalidOperation.Create('Der Quelleditor bietet keine nativen Debuggeraktionen an.');
  Result.Cursor := LView.CursorPos;
  Result.BlockStart := LSource.BlockStart;
  Result.BlockAfter := LSource.BlockAfter;
  Result.BlockType := LSource.BlockType;
  Result.BlockVisible := LSource.BlockVisible;
  ReadDebugContext(Result);
  Result.SourceSha256 := SourceHash(LSource);
end;

procedure CheckSnapshot(const AExpected, AActual: TDAIExpressionUIRequest);
begin
  if not TDAIOTA.SameFile(AExpected.FileName, AActual.FileName) or (AExpected.SourceSha256 <> AActual.SourceSha256) or
     (AExpected.Cursor.Line <> AActual.Cursor.Line) or (AExpected.Cursor.Col <> AActual.Cursor.Col) or
     (AExpected.BlockStart.Line <> AActual.BlockStart.Line) or (AExpected.BlockStart.CharIndex <> AActual.BlockStart.CharIndex) or
     (AExpected.BlockAfter.Line <> AActual.BlockAfter.Line) or (AExpected.BlockAfter.CharIndex <> AActual.BlockAfter.CharIndex) or
     (AExpected.BlockType <> AActual.BlockType) or (AExpected.BlockVisible <> AActual.BlockVisible) then
    raise EInvalidOperation.Create('Quelldatei, Quelltext, Cursor oder Auswahl haben sich seit der Anforderung geändert.');
  if (AExpected.ProcessId <> AActual.ProcessId) or (AExpected.DebuggerProcessId <> AActual.DebuggerProcessId) or
     (AExpected.ThreadId <> AActual.ThreadId) then
    raise EInvalidOperation.Create('Der aktuelle Debug-Prozess oder Thread hat sich seit der Anforderung geändert.');
end;

function TExpressionUIJob.ToJson: TJSONObject;
var
  LCursor: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('request_id', Id);
  Result.AddPair('status', State);
  Result.AddPair('action', Request.Action);
  Result.AddPair('file', Request.FileName);
  Result.AddPair('source_sha256', Request.SourceSha256);
  Result.AddPair('callback_active', TJSONBool.Create(CallbackActive));
  Result.AddPair('action_started', TJSONBool.Create(ActionStarted));
  Result.AddPair('action_invoked', TJSONBool.Create(ActionInvoked));
  Result.AddPair('dialog_opened', TJSONNull.Create);
  if Reason = '' then Result.AddPair('message', TJSONNull.Create) else Result.AddPair('message', Reason);
  LCursor := TJSONObject.Create;
  LCursor.AddPair('line', TJSONNumber.Create(Request.Cursor.Line));
  LCursor.AddPair('column', TJSONNumber.Create(Request.Cursor.Col));
  Result.AddPair('cursor', LCursor);
  if Request.ProcessId <> 0 then
  begin
    Result.AddPair('process_id', TJSONNumber.Create(Int64(Request.ProcessId)));
    Result.AddPair('thread_id', TJSONNumber.Create(Int64(Request.ThreadId)));
  end;
end;

constructor TExpressionUIPump.Create;
begin
  inherited;
  FJobs := TObjectList<TExpressionUIJob>.Create(True);
end;

destructor TExpressionUIPump.Destroy;
begin
  Stop;
  FJobs.Free;
  inherited;
end;

function TExpressionUIPump.Enqueue(const ARequest: TDAIExpressionUIRequest): TJSONObject;
var
  LJob: TExpressionUIJob;
  LId: TGUID;
begin
  if FStopped then raise EInvalidOperation.Create('Die Debugger-Editoraktionen wurden beendet.');
  if FRunning or (FActive <> nil) then raise EInvalidOperation.Create('Eine Debugger-Editoraktion ist bereits aktiv.');
  PinExpressionUIModule;
  LJob := TExpressionUIJob.Create;
  try
    LJob.Request := ARequest;
    CreateGUID(LId);
    LJob.Id := GUIDToString(LId);
    LJob.State := 'queued';
    while FJobs.Count >= CMaximumJobs do FJobs.Delete(0);
    FJobs.Add(LJob);
    FActive := LJob;
    LJob := nil;
    try
      TThread.ForceQueue(nil, RunQueued);
    except
      FActive.State := 'error';
      FActive.Reason := 'Die native Debuggeraktion konnte nicht eingereiht werden.';
      FActive := nil;
      raise;
    end;
    Result := FJobs.Last.ToJson;
  finally
    LJob.Free;
  end;
end;

function TExpressionUIPump.FindStatus(const AId: string): TJSONObject;
var
  LJob: TExpressionUIJob;
begin
  for LJob in FJobs do if LJob.Id = AId then Exit(LJob.ToJson);
  raise EArgumentException.Create('Die Debugger-Editoraktion ist unbekannt oder nicht mehr gespeichert.');
end;

procedure TExpressionUIPump.Stop;
begin
  FStopped := True;
  TThread.RemoveQueuedEvents(nil, RunQueued);
  if FActive <> nil then
  begin
    FActive.State := 'cancelled';
    FActive.Reason := 'Die Debugger-Editoraktion wurde beim Serverstopp abgebrochen; bereits gestartete IDE-Aufrufe werden nicht beendet.';
    if not FRunning then FActive := nil;
  end;
end;

procedure TExpressionUIPump.RunQueued;
var
  LJob: TExpressionUIJob;
  LActual: TDAIExpressionUIRequest;
  LActions: IOTAEditActions;
begin
  LJob := FActive;
  if (LJob = nil) or FStopped then Exit;
  FRunning := True;
  LJob.CallbackActive := True;
  try
    try
      LActual := Capture(LJob.Request.Action, LJob.Request.FileName, LActions);
      CheckSnapshot(LJob.Request, LActual);
      if FStopped or GServiceStopped then Exit;
      LJob.State := 'invoking';
      LJob.ActionStarted := True;
      if LJob.Request.Action = 'add_watch' then LActions.AddWatch
      else if LJob.Request.Action = 'watch_at_cursor' then LActions.AddWatchAtCursor
      else if LJob.Request.Action = 'evaluate_modify' then LActions.EvaluateModify
      else LActions.InspectAtCursor;
      LJob.ActionInvoked := True;
      if LJob.State <> 'cancelled' then LJob.State := 'invoked';
    except
      on E: Exception do if LJob.State <> 'cancelled' then
      begin
        LJob.State := 'error';
        LJob.Reason := E.Message;
      end;
    end;
  finally
    LJob.CallbackActive := False;
    FActive := nil;
    FRunning := False;
  end;
end;

class function TDAIExpressionUIService.CurrentFileName: string;
var
  LResult: string;
begin
  TDAIOTA.RunOnMainThread(procedure
    var LSource: IOTASourceEditor; LView: IOTAEditView;
    begin
      if GServiceStopped then raise EInvalidOperation.Create('Die Debugger-Editoraktionen wurden beendet.');
      CurrentSource(LSource, LView, LResult);
    end);
  Result := LResult;
end;

class function TDAIExpressionUIService.Prepare(const AAction, AExpectedFile: string): TDAIExpressionUIRequest;
var
  LResult: TDAIExpressionUIRequest;
begin
  TDAIOTA.RunOnMainThread(procedure
    var LActions: IOTAEditActions;
    begin
      if GServiceStopped then raise EInvalidOperation.Create('Die Debugger-Editoraktionen wurden beendet.');
      LResult := Capture(AAction, AExpectedFile, LActions);
      if GServiceStopped then raise EInvalidOperation.Create('Die Debugger-Editoraktionen wurden beendet.');
    end);
  Result := LResult;
end;

class function TDAIExpressionUIService.Invoke(const ARequest: TDAIExpressionUIRequest): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(procedure
    var LActual: TDAIExpressionUIRequest; LActions: IOTAEditActions;
    begin
      if GServiceStopped then raise EInvalidOperation.Create('Die Debugger-Editoraktionen wurden beendet.');
      LActual := Capture(ARequest.Action, ARequest.FileName, LActions);
      CheckSnapshot(ARequest, LActual);
      if GServiceStopped then raise EInvalidOperation.Create('Die Debugger-Editoraktionen wurden beendet.');
      if GPump = nil then GPump := TExpressionUIPump.Create;
      LResult := GPump.Enqueue(LActual);
    end);
  Result := LResult;
end;

class function TDAIExpressionUIService.Status(const ARequestId: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  if (Trim(ARequestId) = '') or (Pos(#0, ARequestId) <> 0) or (Length(ARequestId) > 128) then
    raise EArgumentException.Create('request_id muss eine nichtleere Kennung ohne NUL sein.');
  TDAIOTA.RunOnMainThread(procedure
    begin
      if GPump = nil then raise EArgumentException.Create('Es ist keine Debugger-Editoraktion gespeichert.');
      LResult := GPump.FindStatus(ARequestId);
    end);
  Result := LResult;
end;

class procedure TDAIExpressionUIService.Shutdown;
begin
  TDAIOTA.RunOnMainThread(procedure
    begin
      GServiceStopped := True;
      if GPump <> nil then GPump.Stop;
    end);
end;

initialization
  GPump := nil;
  GServiceStopped := False;

finalization
  GServiceStopped := True;
  if GPump <> nil then
  begin
    GPump.Stop;
    // A reentrant native/modal stack still owns its controller and job data.
    if not GPump.FRunning then FreeAndNil(GPump) else GPump := nil;
  end;

end.
