unit h5u.DAI.OTA.ProjectOpen;

interface

uses
  System.JSON,
  h5u.DAI.Types;

type
  TDAIProjectOpenService = class sealed
  public
    class function Open(const AFileName: string; const ACloseOthers: Boolean; const AContext: TDAIRequestContext): TJSONObject; static;
    class function Status(const ARequestId: string; const AContext: TDAIRequestContext): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.OTA.Projects;

const
  CMaximumJobs = 64;

type
  TOpenJob = class
    Id, FileName, Owner, State, Phase, ErrorText: string;
    CloseOthers, Started: Boolean;
    Value: TJSONObject;
    destructor Destroy; override;
    function Finished: Boolean;
    function ToJson: TJSONObject;
  end;

  IOpenQueue = interface
    ['{ECBF5961-27E1-4E34-8A02-82E039692F36}']
    function Open(const AFileName: string; const ACloseOthers: Boolean; const AOwner: string): TJSONObject;
    function Status(const AId, AOwner: string): TJSONObject;
    procedure Run(const AJob: TOpenJob);
    procedure Stop;
  end;

  TOpenQueue = class(TInterfacedObject, IOpenQueue)
  private
    FLock: TObject;
    FJobs: TObjectList<TOpenJob>;
    FActive: TOpenJob;
    FWorks: TList<Pointer>;
    FStopped, FInIDECall: Boolean;
    procedure SetPhase(const AJob: TOpenJob; const APhase: string);
  public
    constructor Create;
    destructor Destroy; override;
    function Open(const AFileName: string; const ACloseOthers: Boolean; const AOwner: string): TJSONObject;
    function Status(const AId, AOwner: string): TJSONObject;
    procedure Run(const AJob: TOpenJob);
    procedure Stop;
  end;

  TOpenWork = class
    Queue: IOpenQueue;
    Job: TOpenJob;
    Module: HMODULE;
  end;

var
  GQueue: IOpenQueue;

function OpenGetModuleHandleExW(AFlags: DWORD; AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';
function OpenCreateWork(ACallback, AContext, AEnvironment: Pointer): Pointer; stdcall;
  external kernel32 name 'CreateThreadpoolWork';
procedure OpenSubmitWork(AWork: Pointer); stdcall; external kernel32 name 'SubmitThreadpoolWork';
procedure OpenWaitWork(AWork: Pointer; ACancelPending: BOOL); stdcall; external kernel32 name 'WaitForThreadpoolWorkCallbacks';
procedure OpenCloseWork(AWork: Pointer); stdcall; external kernel32 name 'CloseThreadpoolWork';
function OpenCallbackMayRunLong(AInstance: Pointer): BOOL; stdcall; external kernel32 name 'CallbackMayRunLong';
procedure OpenFreeLibraryWhenCallbackReturns(AInstance: Pointer; AModule: HMODULE); stdcall;
  external kernel32 name 'FreeLibraryWhenCallbackReturns';

procedure RunOpenWork(AInstance, AContext, AWork: Pointer); stdcall;
var
  LWork: TOpenWork;
begin
  LWork := TOpenWork(AContext);
  OpenCallbackMayRunLong(AInstance);
  // A modal IDE call can pump package-unload actions. Keep this image mapped
  // only for the active callback; Windows releases it after our code returns.
  if LWork.Module <> 0 then
    OpenFreeLibraryWhenCallbackReturns(AInstance, LWork.Module);
  try
    LWork.Queue.Run(LWork.Job);
  finally
    LWork.Free;
  end;
end;

function RetainCallbackModule: HMODULE;
begin
  // Static test executables need no extra reference. FROM_ADDRESS without PIN
  // lets an installed package unload again after its last outstanding job.
  if not OpenGetModuleHandleExW($00000004 or $00000002, PWideChar(Pointer(@RunOpenWork)), Result) then RaiseLastOSError;
  if Result = GetModuleHandle(nil) then
    Exit(0);
  if not OpenGetModuleHandleExW($00000004, PWideChar(Pointer(@RunOpenWork)), Result) then RaiseLastOSError;
end;

destructor TOpenJob.Destroy;
begin
  Value.Free;
  inherited;
end;

function TOpenJob.Finished: Boolean;
begin
  Result := (State = 'completed') or (State = 'cancelled') or (State = 'error');
end;

function TOpenJob.ToJson: TJSONObject;
begin
  if Value <> nil then Result := Value.Clone as TJSONObject
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('file', FileName);
    Result.AddPair('close_others', TJSONBool.Create(CloseOthers));
    if State = 'cancelled' then Result.AddPair('opened', TJSONBool.Create(False))
    else Result.AddPair('opened', TJSONNull.Create);
  end;
  Result.AddPair('request_id', Id);
  Result.AddPair('status', State);
  Result.AddPair('phase', Phase);
  Result.AddPair('finished', TJSONBool.Create(Finished));
  Result.AddPair('sdk_pending', TJSONBool.Create(Started and not Finished));
  Result.AddPair('save_prompts_possible', TJSONBool.Create(not Finished));
  Result.AddPair('timeout_cancels', TJSONBool.Create(False));
  if ErrorText <> '' then Result.AddPair('error', ErrorText);
end;

constructor TOpenQueue.Create;
begin
  inherited;
  FLock := TObject.Create;
  FJobs := TObjectList<TOpenJob>.Create(True);
  FWorks := TList<Pointer>.Create;
end;

destructor TOpenQueue.Destroy;
var LWork: Pointer;
begin
  // Close is nonblocking. Reentrant finalization may release this controller
  // on its last callback; the OS still owns the callback until it returns.
  for LWork in FWorks do OpenCloseWork(LWork);
  FWorks.Free;
  FJobs.Free;
  FLock.Free;
  inherited;
end;

function TOpenQueue.Open(const AFileName: string; const ACloseOthers: Boolean; const AOwner: string): TJSONObject;
var
  LJob: TOpenJob;
  LWork: TOpenWork;
  LId: TGUID;
  LIndex: Integer;
  LNativeWork: Pointer;
begin
  Result := nil;
  LWork := nil;
  System.TMonitor.Enter(FLock);
  try
    if FStopped then raise EInvalidOperation.Create('Die Projektwechsel wurden beendet.');
    if FActive <> nil then
    begin
      if (FActive.Owner = AOwner) and SameText(FActive.FileName, AFileName) and (FActive.CloseOthers = ACloseOthers) then
      begin
        Result := FActive.ToJson;
        Result.AddPair('deduplicated', TJSONBool.Create(True));
        Exit;
      end;
      raise EInvalidOperation.Create('Ein Projektwechsel läuft bereits. Zuerst dessen Status mit request_id abfragen.');
    end;
    // A previous job has finished its IDE call. Join its short callback tail
    // before accepting another, without retaining a growing list of OS work items.
    for LNativeWork in FWorks do
    begin
      OpenWaitWork(LNativeWork, False);
      OpenCloseWork(LNativeWork);
    end;
    FWorks.Clear;
    while FJobs.Count >= CMaximumJobs do
    begin
      LIndex := 0;
      while (LIndex < FJobs.Count) and not FJobs[LIndex].Finished do Inc(LIndex);
      if LIndex = FJobs.Count then raise EInvalidOperation.Create('Zu viele offene Projektwechsel.');
      FJobs.Delete(LIndex);
    end;
    if CreateGUID(LId) <> 0 then raise EInvalidOperation.Create('Die Auftragskennung konnte nicht erzeugt werden.');
    LJob := TOpenJob.Create;
    LJob.Id := GUIDToString(LId);
    LJob.FileName := AFileName;
    LJob.CloseOthers := ACloseOthers;
    LJob.Owner := AOwner;
    LJob.State := 'queued';
    LJob.Phase := 'queued';
    FJobs.Add(LJob);
    FActive := LJob;
    try
      Result := LJob.ToJson;
      LWork := TOpenWork.Create;
      LWork.Queue := Self;
      LWork.Job := LJob;
      LWork.Module := RetainCallbackModule;
      LNativeWork := OpenCreateWork(@RunOpenWork, LWork, nil);
      if LNativeWork = nil then RaiseLastOSError;
      try
        FWorks.Add(LNativeWork);
      except
        OpenCloseWork(LNativeWork);
        raise;
      end;
      OpenSubmitWork(LNativeWork);
      LWork := nil; // The Windows callback owns the work item now.
    except
      if LWork <> nil then
      begin
        if LWork.Module <> 0 then FreeLibrary(LWork.Module);
        LWork.Free;
      end;
      FreeAndNil(Result);
      FActive := nil;
      FJobs.Remove(LJob);
      raise;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TOpenQueue.Status(const AId, AOwner: string): TJSONObject;
var
  LJob: TOpenJob;
begin
  System.TMonitor.Enter(FLock);
  try
    for LJob in FJobs do
      if (LJob.Id = AId) and (LJob.Owner = AOwner) then
        Exit(LJob.ToJson);
    raise EArgumentException.Create('Der Projektwechsel ist unbekannt, abgelaufen oder gehört zu einer anderen Sitzung.');
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TOpenQueue.SetPhase(const AJob: TOpenJob; const APhase: string);
begin
  System.TMonitor.Enter(FLock);
  try
    if FStopped then raise EAbort.Create('Der Projektwechsel wurde beim Beenden von DAI abgebrochen.');
    AJob.Phase := APhase;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TOpenQueue.Run(const AJob: TOpenJob);
var
  LValue: TJSONObject;
  LState, LError: string;
begin
  System.TMonitor.Enter(FLock);
  try
    if FStopped or AJob.Finished then Exit;
    AJob.Started := True;
    AJob.State := 'running';
    AJob.Phase := 'starting';
  finally
    System.TMonitor.Exit(FLock);
  end;
  LValue := nil;
  LError := '';
  LState := 'completed';
  try
    try
      TThread.Synchronize(nil,
        procedure
        begin
          System.TMonitor.Enter(FLock);
          try
            if FStopped then raise EAbort.Create('Der Projektwechsel wurde vor dem IDE-Aufruf beendet.');
            FInIDECall := True;
          finally
            System.TMonitor.Exit(FLock);
          end;
          try
            LValue := TDAIProjectService.OpenProject(AJob.FileName, AJob.CloseOthers,
              procedure(const APhase: string)
              begin
                SetPhase(AJob, APhase);
              end);
          finally
            System.TMonitor.Enter(FLock);
            try FInIDECall := False; finally System.TMonitor.Exit(FLock); end;
          end;
        end);
    except
      on E: EAbort do
      begin
        LState := 'cancelled';
        LError := E.Message;
      end;
      on E: Exception do
      begin
        LState := 'error';
        LError := E.ClassName + ': ' + E.Message;
      end;
    end;
  finally
    System.TMonitor.Enter(FLock);
    try
      AJob.Value := LValue;
      AJob.ErrorText := LError;
      AJob.State := LState;
      AJob.Phase := LState;
      if FActive = AJob then FActive := nil;
    finally
      System.TMonitor.Exit(FLock);
    end;
  end;
end;

procedure TOpenQueue.Stop;
var
  LWork: Pointer;
  LWorks: TArray<Pointer>;
  LPending, LReentrant: Boolean;
  LStarted: UInt64;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopped := True;
    LReentrant := FInIDECall;
    if FActive <> nil then
      if not FActive.Started then
      begin
        FActive.State := 'cancelled';
        FActive.Phase := 'cancelled';
        FActive.ErrorText := 'Der Projektwechsel wurde vor dem Start beendet.';
        FActive := nil;
      end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  // Never join the native call from inside its own modal message loop.
  // The callback retains the controller and package image until it returns.
  if LReentrant then Exit;
  LStarted := GetTickCount64;
  repeat
    System.TMonitor.Enter(FLock);
    try LPending := FActive <> nil; finally System.TMonitor.Exit(FLock); end;
    if not LPending then Break;
    if GetTickCount64 - LStarted > 5000 then Exit;
    if GetCurrentThreadId = MainThreadID then CheckSynchronize(10) else Sleep(1);
  until False;
  System.TMonitor.Enter(FLock);
  try
    LWorks := FWorks.ToArray;
    FWorks.Clear;
  finally
    System.TMonitor.Exit(FLock);
  end;
  // A cancelled callback may not have entered Run yet. It needs FLock once
  // to observe FStopped, so join outside the controller lock.
  for LWork in LWorks do
  begin
    OpenWaitWork(LWork, False);
    OpenCloseWork(LWork);
  end;
end;

class function TDAIProjectOpenService.Open(const AFileName: string; const ACloseOthers: Boolean; const AContext: TDAIRequestContext): TJSONObject;
var
  LFileName: string;
begin
  LFileName := TDAIProjectService.ResolveOpenProjectFile(AFileName);
  Result := GQueue.Open(LFileName, ACloseOthers, AContext.SessionIdentity);
end;

class function TDAIProjectOpenService.Status(const ARequestId: string; const AContext: TDAIRequestContext): TJSONObject;
begin
  if (Trim(ARequestId) = '') or (Length(ARequestId) > 128) or (Pos(#0, ARequestId) <> 0) then
    raise EArgumentException.Create('request_id muss eine gültige Auftragskennung sein.');
  Result := GQueue.Status(ARequestId, AContext.SessionIdentity);
end;

class procedure TDAIProjectOpenService.Shutdown;
begin
  if GQueue <> nil then GQueue.Stop;
end;

initialization
  GQueue := TOpenQueue.Create;

finalization
  if GQueue <> nil then GQueue.Stop;
  GQueue := nil;

end.
