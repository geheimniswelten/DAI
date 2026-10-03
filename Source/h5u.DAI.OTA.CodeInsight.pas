unit h5u.DAI.OTA.CodeInsight;

interface

uses
  System.JSON;

type
  TDAICodeInsightService = class sealed
  public
    class procedure Shutdown; static;
    class function Status(const AFileName: string): TJSONObject; static;
    class function Definition(const AFileName: string; const ALine: Integer; const ACharacter: Integer; const ATimeoutMs: Integer): TJSONObject; static;
    class function Hover(const AFileName: string; const ALine: Integer; const AColumn: Integer; const ATimeoutMs: Integer): TJSONObject; static;
    class function Diagnostics(const AFileName: string): TJSONObject; static;
    class function ProjectContext(const AProjectNameOrPath: string; const AIncludeFiles: Boolean; const AMaximumFiles: Integer;
      const AIncludeCompilerOptions: Boolean): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.SyncObjs,
  System.SysUtils,
  Vcl.Forms,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Types;

type
  TDAICodeInsightOperation = (
    cioNone,
    cioDefinition,
    cioHover
  );

  TDAICodeInsightState = record
    Operation: TDAICodeInsightOperation;
    RequestId: Integer;
    Completed: Boolean;
    Error: Boolean;
    TimedOut: Boolean;
    MessageText: string;
    ResultText: string;
    ResultFileName: string;
    ResultLine: Integer;
    ResultCharacter: Integer;
  end;

  IDAICodeInsightCallbackBroker = interface
    ['{58AD24B3-A2DF-4F65-AD1B-82C5F9C78620}']
    procedure RetainCallback(const ACallback: IInterface);
    procedure ReleaseCallback(const ACallback: IInterface);
    procedure Shutdown;
  end;

  TDAICodeInsightCallbackBroker = class(TInterfacedObject, IDAICodeInsightCallbackBroker)
  private
    FLock: TCriticalSection;
    FModulePinned: Boolean;
    FPendingCallbacks: TList<IInterface>;
    FShutdown: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RetainCallback(const ACallback: IInterface);
    procedure ReleaseCallback(const ACallback: IInterface);
    procedure Shutdown;
  end;

  TDAICodeInsightCallbacks = class(TInterfacedObject)
  private
    FBroker: IDAICodeInsightCallbackBroker;
    FResultEvent: TEvent;
    FState: TDAICodeInsightState;
    FStateLock: TCriticalSection;
  public
    constructor Create(const AOperation: TDAICodeInsightOperation; const ABroker: IDAICodeInsightCallbackBroker);
    destructor Destroy; override;
    function MarkCancelled: Boolean;
    procedure RegisterRequestId(const ARequestId: Integer);
    function SnapshotState: TDAICodeInsightState;
    procedure DefinitionCallback(Sender: TObject; AId: Integer; const AFileName: string; ALine: Integer; AError: Boolean; const AMessage: string);
    procedure DefinitionCallbackEx(Sender: TObject; AId: Integer; const AFileName: string; ALine, ACharIndex: Integer; AError: Boolean; const AMessage: string);
    procedure HintCallback(Sender: TObject; AId: Integer; const AHint: string; AError: Boolean; const AMessage: string);
  end;

const
  CDefaultTimeoutMs = 10000;
  CMaximumTimeoutMs = 60000;
  CMaximumPendingCallbacks = 256;
  CGetModuleHandleExFromAddress = $00000004;
  CGetModuleHandleExPin = $00000001;

var
  GCallbackRegistryLock: TCriticalSection;
  GOperationLock: TObject;
  GCallbackBroker: IDAICodeInsightCallbackBroker;
  // This unmanaged flag also survives FinalizePackage/InitializePackage of a pinned image.
  GServiceShutdown: Boolean;

function ClampTimeout(const ATimeoutMs: Integer): Integer;
begin
  if ATimeoutMs <= 0 then
    Exit(CDefaultTimeoutMs);
  Result := EnsureRange(ATimeoutMs, 100, CMaximumTimeoutMs);
end;

function ExpandReadableFileName(const AFileName: string): string;
begin
  if Trim(AFileName) = '' then
    raise EArgumentException.Create('Der Parameter "file" darf nicht leer sein.');

  Result := TDAISettings.Instance.ExpandPath(AFileName);
  if not TFile.Exists(Result) and not TDAIOTA.IsFileOpenInEditor(Result) then
    raise EDAIFileNotFound.CreateFmt('Die Datei wurde nicht gefunden: %s', [Result]);

  if not TDAIOTA.IsWorkspaceFile(Result) and not TDAIOTA.IsReadOnlyReferenceFile(Result) then
    raise EDAIAccessDenied.CreateFmt('Die Datei liegt weder im Workspace noch in einem freigegebenen Referenzpfad: %s', [Result]);
end;

function JsonStringArray(const AValues: TArray<string>): TJSONArray;
var
  LValue: string;
begin
  Result := TJSONArray.Create;
  for LValue in AValues do
    Result.Add(LValue);
end;

function ManagerId(const AManager: IOTACodeInsightManager): string;
begin
  Result := '';
  if not Assigned(AManager) then
    Exit;
  try
    Result := AManager.GetIDString;
  except
    Result := '';
  end;
end;

function ManagerName(const AManager: IOTACodeInsightManager): string;
begin
  Result := '';
  if not Assigned(AManager) then
    Exit;
  try
    Result := AManager.Name;
  except
    Result := '';
  end;
end;

function ManagerEnabled(const AManager: IOTACodeInsightManager): Boolean;
begin
  Result := False;
  if not Assigned(AManager) then
    Exit;
  try
    Result := AManager.Enabled;
  except
    Result := False;
  end;
end;

function ManagerHandlesFile(const AServices: IOTACodeInsightServices; const AManager: IOTACodeInsightManager; const AFileName: string): Boolean;
var
  LId: string;
begin
  Result := Trim(AFileName) = '';
  if Result or not Assigned(AManager) then
    Exit;

  LId := ManagerId(AManager);
  if Assigned(AServices) and (LId <> '') then
    try
      Result := AServices.HandlesFile(AFileName, LId);
    except
      Result := False;
    end;

  if not Result then
    try
      Result := AManager.HandlesFile(AFileName);
    except
      Result := False;
    end;
end;

function AsyncCanInvoke(const AManager: IOTAAsyncCodeInsightManager; const AInsightType: TOTACodeInsightType): Boolean;
begin
  Result := False;
  if not Assigned(AManager) then
    Exit;
  try
    Result := AManager.AsyncCanInvoke(AInsightType);
  except
    Result := False;
  end;
end;

function AsyncEnabled(const AManager: IOTAAsyncCodeInsightManager): Boolean;
begin
  Result := False;
  if not Assigned(AManager) then
    Exit;
  try
    Result := AManager.AsyncEnabled;
  except
    Result := False;
  end;
end;

function TrySelectManager(const AFileName: string; const AInsightType: TOTACodeInsightType; out AServices: IOTACodeInsightServices;
  out AManager: IOTACodeInsightManager; out AAsyncManager: IOTAAsyncCodeInsightManager; out AErrorMessage: string): Boolean;
var
  LCandidate: IOTACodeInsightManager;
  LCandidateAsync: IOTAAsyncCodeInsightManager;
  LIndex: Integer;

  function CandidateUsable(const ACandidate: IOTACodeInsightManager): Boolean;
  begin
    Result := Assigned(ACandidate) and ManagerEnabled(ACandidate) and ManagerHandlesFile(AServices, ACandidate, AFileName) and
      Supports(ACandidate, IOTAAsyncCodeInsightManager, LCandidateAsync) and AsyncEnabled(LCandidateAsync) and
      AsyncCanInvoke(LCandidateAsync, AInsightType);
    if Result then
    begin
      AManager := ACandidate;
      AAsyncManager := LCandidateAsync;
    end;
  end;

begin
  Result := False;
  AServices := nil;
  AManager := nil;
  AAsyncManager := nil;
  AErrorMessage := '';

  if not Supports(BorlandIDEServices, IOTACodeInsightServices, AServices) then
  begin
    AErrorMessage := 'IOTACodeInsightServices ist in dieser IDE nicht verfügbar.';
    Exit;
  end;

  AServices.GetCurrentCodeInsightManager(LCandidate);
  if CandidateUsable(LCandidate) then
    Exit(True);

  for LIndex := 0 to AServices.CodeInsightManagerCount - 1 do
  begin
    LCandidate := AServices.CodeInsightManager[LIndex];
    if CandidateUsable(LCandidate) then
      Exit(True);
  end;

  AErrorMessage := 'Kein aktivierter und bereiter Code-Insight-Provider unterstützt die angeforderte Datei und Operation.';
end;

// These Windows SDK declarations are missing from Delphi's Winapi.Windows unit.
function DAIGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure PinCallbackModule;
var
  LModule: HMODULE;
begin
  LModule := 0;
  // OTA receives a raw method pointer and cancellation does not revoke it. Pin code
  // before publishing the first receiver; Delphi finalization is handled separately.
  if not DAIGetModuleHandleExW(CGetModuleHandleExFromAddress or CGetModuleHandleExPin,
    PChar(Pointer(@PinCallbackModule)), LModule) then
    RaiseLastOSError;
end;

function RequireActiveBroker: IDAICodeInsightCallbackBroker;
begin
  if not Assigned(GCallbackRegistryLock) then
    raise EInvalidOperation.Create('Code Insight wurde beendet; ein IDE-Neustart ist erforderlich.');
  GCallbackRegistryLock.Acquire;
  try
    if GServiceShutdown or not Assigned(GCallbackBroker) then
      raise EInvalidOperation.Create('Code Insight wurde beendet; ein IDE-Neustart ist erforderlich.');
    Result := GCallbackBroker;
  finally
    GCallbackRegistryLock.Release;
  end;
end;

constructor TDAICodeInsightCallbackBroker.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPendingCallbacks := TList<IInterface>.Create;
end;

destructor TDAICodeInsightCallbackBroker.Destroy;
begin
  FPendingCallbacks.Free;
  FLock.Free;
  inherited;
end;

procedure TDAICodeInsightCallbackBroker.RetainCallback(const ACallback: IInterface);
begin
  FLock.Acquire;
  try
    if FShutdown then
      raise EInvalidOperation.Create('Code Insight wurde beendet; ein IDE-Neustart ist erforderlich.');
    if FPendingCallbacks.Count >= CMaximumPendingCallbacks then
      raise EInvalidOperation.CreateFmt(
        'Es sind bereits %d Code-Insight-Anfragen ohne abschließenden Provider-Callback offen; weitere Anfragen sind bis zu deren Abschluss gesperrt.',
        [CMaximumPendingCallbacks]);
    if not FModulePinned then
    begin
      PinCallbackModule;
      FModulePinned := True;
    end;
    FPendingCallbacks.Add(ACallback);
  finally
    FLock.Release;
  end;
end;

procedure TDAICodeInsightCallbackBroker.ReleaseCallback(const ACallback: IInterface);
begin
  FLock.Acquire;
  try
    FPendingCallbacks.Remove(ACallback);
  finally
    FLock.Release;
  end;
end;

procedure TDAICodeInsightCallbackBroker.Shutdown;
begin
  FLock.Acquire;
  try
    FShutdown := True;
    // Do not free pending receivers: a provider can still hold their method pointers.
    // Each receiver owns this broker, so late completion needs no unit globals.
  finally
    FLock.Release;
  end;
end;

constructor TDAICodeInsightCallbacks.Create(const AOperation: TDAICodeInsightOperation; const ABroker: IDAICodeInsightCallbackBroker);
begin
  inherited Create;
  FBroker := ABroker;
  FStateLock := TCriticalSection.Create;
  FResultEvent := TEvent.Create(nil, True, False, '');
  FState.Operation := AOperation;
  FState.RequestId := -1;
end;

destructor TDAICodeInsightCallbacks.Destroy;
begin
  FResultEvent.Free;
  FStateLock.Free;
  inherited;
end;

procedure TDAICodeInsightCallbacks.RegisterRequestId(const ARequestId: Integer);
begin
  FStateLock.Acquire;
  try
    if FState.RequestId < 0 then
      FState.RequestId := ARequestId;
  finally
    FStateLock.Release;
  end;
end;

function TDAICodeInsightCallbacks.MarkCancelled: Boolean;
begin
  FStateLock.Acquire;
  try
    if FState.Completed then
      Exit(False);
    FState.TimedOut := True;
    FState.Completed := True;
    FState.MessageText := 'Zeitüberschreitung beim Warten auf den IDE-Code-Insight-Provider.';
    Result := True;
  finally
    FStateLock.Release;
  end;
end;

function WaitForOperation(const ACallbacks: TDAICodeInsightCallbacks; const ATimeoutMs: Integer): Boolean;
var
  LStartedAt: Cardinal;
begin
  if GetCurrentThreadId <> MainThreadID then
    Exit(ACallbacks.FResultEvent.WaitFor(ATimeoutMs) = wrSignaled);

  LStartedAt := GetTickCount;
  repeat
    if ACallbacks.FResultEvent.WaitFor(0) = wrSignaled then
      Exit(True);
    Application.ProcessMessages;
    CheckSynchronize(0);
    Sleep(5);
  until GetTickCount - LStartedAt >= Cardinal(ATimeoutMs);
  Result := False;
end;

function TDAICodeInsightCallbacks.SnapshotState: TDAICodeInsightState;
begin
  FStateLock.Acquire;
  try
    Result := FState;
  finally
    FStateLock.Release;
  end;
end;

procedure CancelRequest(const ACallbacks: TDAICodeInsightCallbacks; const AAsyncManager: IOTAAsyncCodeInsightManager; const ARequestId: Integer);
begin
  if not ACallbacks.MarkCancelled then
    Exit;
  if not Assigned(AAsyncManager) or (ARequestId < 0) then
    Exit;

  TDAIOTA.RunOnMainThread(
    procedure
    begin
      try
        AAsyncManager.AsyncOperationCanceled(ARequestId);
      except
        // A timeout remains a timeout even if the provider rejects cancellation.
      end;
    end
  );
end;

function CodeInsightResultBase(const AFileName: string; const AProviderName: string; const AProviderId: string; const AState: TDAICodeInsightState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AFileName);
  Result.AddPair('provider_name', AProviderName);
  Result.AddPair('provider_id', AProviderId);
  Result.AddPair('request_id', TJSONNumber.Create(AState.RequestId));
  Result.AddPair('success', TJSONBool.Create(AState.Completed and not AState.Error and not AState.TimedOut));
  Result.AddPair('timed_out', TJSONBool.Create(AState.TimedOut));
  Result.AddPair('message', AState.MessageText);
end;

function SeverityName(const ASeverity: Integer): string;
begin
  case ASeverity of
    1:
      Result := 'error';
    2:
      Result := 'warning';
    3:
      Result := 'hint';
  else
    Result := 'unknown';
  end;
end;

procedure AddCompilerOption(const AObject: TJSONObject; const AConfiguration: IOTABuildConfiguration; const AJsonName: string; const APropertyName: string);
var
  LValue: string;
begin
  LValue := '';
  if Assigned(AConfiguration) then
    try
      LValue := AConfiguration.Value[APropertyName];
    except
      LValue := '';
    end;
  AObject.AddPair(AJsonName, LValue);
end;

procedure TDAICodeInsightCallbacks.DefinitionCallback(Sender: TObject; AId: Integer; const AFileName: string; ALine: Integer; AError: Boolean; const AMessage: string);
var
  LKeepAlive: IInterface;
begin
  LKeepAlive := Self;
  DefinitionCallbackEx(Sender, AId, AFileName, ALine, 0, AError, AMessage);
end;

procedure TDAICodeInsightCallbacks.DefinitionCallbackEx(Sender: TObject; AId: Integer; const AFileName: string; ALine, ACharIndex: Integer;
  AError: Boolean; const AMessage: string);
var
  LKeepAlive: IInterface;
  LReleasePending: Boolean;
begin
  // OTA stores a method pointer, not an owning interface. Keep this receiver alive
  // until its callback returns, including a late result after the caller timed out.
  LKeepAlive := Self;
  FStateLock.Acquire;
  try
    if (FState.Operation <> cioDefinition) or ((FState.RequestId >= 0) and (FState.RequestId <> AId)) then
      Exit;
    if FState.Completed then
      LReleasePending := FState.TimedOut
    else
    begin
      FState.RequestId := AId;
      FState.ResultFileName := AFileName;
      FState.ResultLine := ALine;
      FState.ResultCharacter := ACharIndex;
      FState.Error := AError;
      FState.MessageText := AMessage;
      FState.Completed := True;
      FResultEvent.SetEvent;
      LReleasePending := True;
    end;
  finally
    FStateLock.Release;
  end;
  if LReleasePending then
    FBroker.ReleaseCallback(Self);
end;

procedure TDAICodeInsightCallbacks.HintCallback(Sender: TObject; AId: Integer; const AHint: string; AError: Boolean; const AMessage: string);
var
  LKeepAlive: IInterface;
  LReleasePending: Boolean;
begin
  LKeepAlive := Self;
  FStateLock.Acquire;
  try
    if (FState.Operation <> cioHover) or ((FState.RequestId >= 0) and (FState.RequestId <> AId)) then
      Exit;
    if FState.Completed then
      LReleasePending := FState.TimedOut
    else
    begin
      FState.RequestId := AId;
      FState.ResultText := AHint;
      FState.Error := AError;
      FState.MessageText := AMessage;
      FState.Completed := True;
      FResultEvent.SetEvent;
      LReleasePending := True;
    end;
  finally
    FStateLock.Release;
  end;
  if LReleasePending then
    FBroker.ReleaseCallback(Self);
end;

class procedure TDAICodeInsightService.Shutdown;
var
  LBroker: IDAICodeInsightCallbackBroker;
begin
  if not Assigned(GCallbackRegistryLock) then
    Exit;
  GCallbackRegistryLock.Acquire;
  try
    GServiceShutdown := True;
    LBroker := GCallbackBroker;
    if Assigned(LBroker) then
      LBroker.Shutdown;
    GCallbackBroker := nil;
  finally
    GCallbackRegistryLock.Release;
  end;
end;

class function TDAICodeInsightService.Status(const AFileName: string): TJSONObject;
var
  LExpandedFileName: string;
  LResult: TJSONObject;
begin
  LExpandedFileName := '';
  if Trim(AFileName) <> '' then
    LExpandedFileName := ExpandReadableFileName(AFileName);

  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LAsync: IOTAAsyncCodeInsightManager;
      {$IF Declared(IOTAAsyncCodeInsightManager290)}
      LAsyncEx: IOTAAsyncCodeInsightManager290;
      {$IFEND}
      LCurrent: IOTACodeInsightManager;
      LCurrentId: string;
      LIndex: Integer;
      LManager: IOTACodeInsightManager;
      LManagerObject: TJSONObject;
      LManagers: TJSONArray;
      LServices: IOTACodeInsightServices;
    begin
      LResult := TJSONObject.Create;
      LResult.AddPair('file', LExpandedFileName);
      LResult.AddPair('transport', 'IDE Code Insight über OpenToolsAPI');
      LResult.AddPair('raw_lsp_connection', TJSONBool.Create(False));

      if not Supports(BorlandIDEServices, IOTACodeInsightServices, LServices) then
      begin
        LResult.AddPair('available', TJSONBool.Create(False));
        LResult.AddPair('message', 'IOTACodeInsightServices ist in dieser IDE nicht verfügbar.');
        LResult.AddPair('managers', TJSONArray.Create);
        Exit;
      end;

      LServices.GetCurrentCodeInsightManager(LCurrent);
      LCurrentId := ManagerId(LCurrent);
      LManagers := TJSONArray.Create;
      for LIndex := 0 to LServices.CodeInsightManagerCount - 1 do
      begin
        LManager := LServices.CodeInsightManager[LIndex];
        LManagerObject := TJSONObject.Create;
        LManagerObject.AddPair('name', ManagerName(LManager));
        LManagerObject.AddPair('id', ManagerId(LManager));
        LManagerObject.AddPair('current', TJSONBool.Create((LCurrentId <> '') and SameText(ManagerId(LManager), LCurrentId)));
        LManagerObject.AddPair('enabled', TJSONBool.Create(ManagerEnabled(LManager)));
        LManagerObject.AddPair('handles_file', TJSONBool.Create(ManagerHandlesFile(LServices, LManager, LExpandedFileName)));
        if Supports(LManager, IOTAAsyncCodeInsightManager, LAsync) then
        begin
          LManagerObject.AddPair('async_supported', TJSONBool.Create(True));
          LManagerObject.AddPair('ready', TJSONBool.Create(AsyncEnabled(LAsync)));
          LManagerObject.AddPair('definition', TJSONBool.Create(AsyncCanInvoke(LAsync, citBrowseCodeInsight)));
          LManagerObject.AddPair('hover', TJSONBool.Create(AsyncCanInvoke(LAsync, citHintCodeInsight)));
          LManagerObject.AddPair('completion', TJSONBool.Create(AsyncCanInvoke(LAsync, citCodeInsight)));
          LManagerObject.AddPair('signature_help', TJSONBool.Create(AsyncCanInvoke(LAsync, citParameterCodeInsight)));
        end
        else
        begin
          LManagerObject.AddPair('async_supported', TJSONBool.Create(False));
          LManagerObject.AddPair('ready', TJSONBool.Create(False));
          LManagerObject.AddPair('definition', TJSONBool.Create(False));
          LManagerObject.AddPair('hover', TJSONBool.Create(False));
          LManagerObject.AddPair('completion', TJSONBool.Create(False));
          LManagerObject.AddPair('signature_help', TJSONBool.Create(False));
        end;
        {$IF Declared(IOTAAsyncCodeInsightManager290)}
        LManagerObject.AddPair('definition_character_supported', TJSONBool.Create(Supports(LManager, IOTAAsyncCodeInsightManager290, LAsyncEx)));
        LAsyncEx := nil;
        {$ELSE}
        LManagerObject.AddPair('definition_character_supported', TJSONBool.Create(False));
        {$IFEND}
        LManagers.AddElement(LManagerObject);
      end;

      LResult.AddPair('available', TJSONBool.Create(True));
      LResult.AddPair('current_provider_id', LCurrentId);
      LResult.AddPair('manager_count', TJSONNumber.Create(LServices.CodeInsightManagerCount));
      LResult.AddPair('managers', LManagers);
    end
  );
  Result := LResult;
end;

class function TDAICodeInsightService.Definition(const AFileName: string; const ALine: Integer; const ACharacter: Integer; const ATimeoutMs: Integer): TJSONObject;
var
  LAsync: IOTAAsyncCodeInsightManager;
  {$IF Declared(IOTAAsyncCodeInsightManager290)}
  LAsyncEx: IOTAAsyncCodeInsightManager290;
  {$IFEND}
  LBroker: IDAICodeInsightCallbackBroker;
  LCallbackLifetime: IInterface;
  LCallbacks: TDAICodeInsightCallbacks;
  LErrorMessage: string;
  LExpandedFileName: string;
  LManager: IOTACodeInsightManager;
  LProviderId: string;
  LProviderName: string;
  LRequestId: Integer;
  LServices: IOTACodeInsightServices;
  LStarted: Boolean;
  LState: TDAICodeInsightState;
  LTimeout: Integer;
begin
  if ALine < 1 then
    raise EArgumentOutOfRangeException.Create('Der Parameter "line" muss mindestens 1 sein.');
  if ACharacter < 0 then
    raise EArgumentOutOfRangeException.Create('Der Parameter "character" darf nicht negativ sein.');

  LBroker := RequireActiveBroker;
  LExpandedFileName := ExpandReadableFileName(AFileName);
  LTimeout := ClampTimeout(ATimeoutMs);
  LStarted := False;
  LRequestId := -1;
  LErrorMessage := '';
  LProviderId := '';
  LProviderName := '';

  System.TMonitor.Enter(GOperationLock);
  try
    LCallbacks := TDAICodeInsightCallbacks.Create(cioDefinition, LBroker);
    LCallbackLifetime := LCallbacks;
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LPublished: Boolean;
        LRetained: Boolean;
      begin
        LPublished := False;
        LRetained := False;
        try
          try
            if not TrySelectManager(LExpandedFileName, citBrowseCodeInsight, LServices, LManager, LAsync, LErrorMessage) then
              Exit;
            LProviderId := ManagerId(LManager);
            LProviderName := ManagerName(LManager);
            {$IF Declared(IOTAAsyncCodeInsightManager290)}
            Supports(LManager, IOTAAsyncCodeInsightManager290, LAsyncEx);
            {$IFEND}
            LBroker.RetainCallback(LCallbacks);
            LRetained := True;
            LPublished := True;
            {$IF Declared(IOTAAsyncCodeInsightManager290)}
            if Assigned(LAsyncEx) then
              LRequestId := LAsyncEx.AsyncGotoDefinitionEx(LExpandedFileName, ALine, ACharacter, LCallbacks.DefinitionCallbackEx)
            else
            {$IFEND}
              LRequestId := LAsync.AsyncGotoDefinition(LExpandedFileName, ALine, ACharacter, LCallbacks.DefinitionCallback);
            if LRequestId < 0 then
            begin
              LErrorMessage := 'Der Code-Insight-Provider hat keine gültige Request-ID zurückgegeben.';
              Exit;
            end;
            LCallbacks.RegisterRequestId(LRequestId);
            LStarted := True;
          except
            on E: Exception do
              LErrorMessage := E.Message;
          end;
        finally
          if LRetained and not LPublished then
            LBroker.ReleaseCallback(LCallbacks);
          {$IF Declared(IOTAAsyncCodeInsightManager290)}
          LAsyncEx := nil;
          {$IFEND}
          LManager := nil;
          LServices := nil;
        end;
      end
    );

    if LStarted and not WaitForOperation(LCallbacks, LTimeout) then
      CancelRequest(LCallbacks, LAsync, LRequestId);
    LState := LCallbacks.SnapshotState;

    if not LStarted then
    begin
      LState.Error := True;
      LState.MessageText := LErrorMessage;
    end;

    Result := CodeInsightResultBase(LExpandedFileName, LProviderName, LProviderId, LState);
    Result.AddPair('found', TJSONBool.Create(not LState.Error and not LState.TimedOut and (Trim(LState.ResultFileName) <> '')));
    if Trim(LState.ResultFileName) <> '' then
      try
        Result.AddPair('definition_file', TDAIOTA.NormalizeFileName(LState.ResultFileName));
      except
        Result.AddPair('definition_file', LState.ResultFileName);
      end
    else
      Result.AddPair('definition_file', '');
    Result.AddPair('definition_line', TJSONNumber.Create(LState.ResultLine));
    Result.AddPair('definition_character', TJSONNumber.Create(LState.ResultCharacter));
    Result.AddPair('input_line', TJSONNumber.Create(ALine));
    Result.AddPair('input_character', TJSONNumber.Create(ACharacter));
  finally
    try
      TDAIOTA.RunOnMainThread(
        procedure
        begin
          LAsync := nil;
        end
      );
    finally
      System.TMonitor.Exit(GOperationLock);
    end;
  end;
end;

class function TDAICodeInsightService.Hover(const AFileName: string; const ALine: Integer; const AColumn: Integer; const ATimeoutMs: Integer): TJSONObject;
var
  LAsync: IOTAAsyncCodeInsightManager;
  LBroker: IDAICodeInsightCallbackBroker;
  LCallbackLifetime: IInterface;
  LCallbacks: TDAICodeInsightCallbacks;
  LContextSet: Boolean;
  LEditView: IOTAEditView;
  LErrorMessage: string;
  LExpandedFileName: string;
  LManager: IOTACodeInsightManager;
  LProviderId: string;
  LProviderName: string;
  LRequestId: Integer;
  LServices: IOTACodeInsightServices;
  LSourceEditor: IOTASourceEditor;
  LStarted: Boolean;
  LState: TDAICodeInsightState;
  LTimeout: Integer;
begin
  if ALine < 1 then
    raise EArgumentOutOfRangeException.Create('Der Parameter "line" muss mindestens 1 sein.');
  if AColumn < 1 then
    raise EArgumentOutOfRangeException.Create('Der Parameter "column" muss mindestens 1 sein.');

  LBroker := RequireActiveBroker;
  LExpandedFileName := ExpandReadableFileName(AFileName);
  LTimeout := ClampTimeout(ATimeoutMs);
  LStarted := False;
  LContextSet := False;
  LRequestId := -1;
  LErrorMessage := '';
  LProviderId := '';
  LProviderName := '';

  System.TMonitor.Enter(GOperationLock);
  try
    LCallbacks := TDAICodeInsightCallbacks.Create(cioHover, LBroker);
    LCallbackLifetime := LCallbacks;
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LPublished: Boolean;
        LRetained: Boolean;
      begin
        LPublished := False;
        LRetained := False;
        try
          try
            LSourceEditor := TDAIOTA.FindSourceEditor(LExpandedFileName);
            if not Assigned(LSourceEditor) or (LSourceEditor.EditViewCount = 0) then
            begin
              LErrorMessage := 'Help Insight benötigt eine in einem Code-Editor geöffnete Datei.';
              Exit;
            end;
            LEditView := LSourceEditor.EditViews[0];
            if not Assigned(LEditView) then
            begin
              LErrorMessage := 'Für die geöffnete Datei ist keine Editoransicht verfügbar.';
              Exit;
            end;
            if not TrySelectManager(LExpandedFileName, citHintCodeInsight, LServices, LManager, LAsync, LErrorMessage) then
              Exit;
            LProviderId := ManagerId(LManager);
            LProviderName := ManagerName(LManager);
            LBroker.RetainCallback(LCallbacks);
            LRetained := True;
            LContextSet := True;
            LServices.SetQueryContext(LEditView, LManager);
            LPublished := True;
            LRequestId := LAsync.AsyncGetHintText(ALine, AColumn, LCallbacks.HintCallback);
            if LRequestId < 0 then
            begin
              LErrorMessage := 'Der Code-Insight-Provider hat keine gültige Request-ID zurückgegeben.';
              Exit;
            end;
            LCallbacks.RegisterRequestId(LRequestId);
            LStarted := True;
          except
            on E: Exception do
              LErrorMessage := E.Message;
          end;
        finally
          if LRetained and not LPublished then
            LBroker.ReleaseCallback(LCallbacks);
          if LContextSet then
          begin
            try
              LServices.SetQueryContext(nil, nil);
            except
              // The provider may reject restoration during IDE shutdown.
            end;
            LContextSet := False;
          end;
          // Query invocation has consumed these interfaces. Release them on the
          // IDE thread before waiting, so an open module/view is not kept alive.
          LEditView := nil;
          LSourceEditor := nil;
          LManager := nil;
          LServices := nil;
        end;
      end
    );

    if LStarted and not WaitForOperation(LCallbacks, LTimeout) then
      CancelRequest(LCallbacks, LAsync, LRequestId);

    LState := LCallbacks.SnapshotState;
    if not LStarted then
    begin
      LState.Error := True;
      LState.MessageText := LErrorMessage;
    end;

    // Delphi providers can return this protocol marker instead of position-specific
    // help text. Viewer/caret documentation is not a reliable substitute here.
    if not LState.Error and not LState.TimedOut and SameText(Trim(LState.ResultText), 'HTML') then
    begin
      LState.Error := True;
      LState.ResultText := '';
      LState.MessageText := 'Der IDE-Provider liefert nur den HTML-Marker; positionsbezogener Help-Insight-Inhalt ist nicht verfügbar.';
    end;

    Result := CodeInsightResultBase(LExpandedFileName, LProviderName, LProviderId, LState);
    Result.AddPair('found', TJSONBool.Create(not LState.Error and not LState.TimedOut and (Trim(LState.ResultText) <> '')));
    Result.AddPair('content_kind', 'ide_hint');
    Result.AddPair('may_contain_html', TJSONBool.Create(True));
    Result.AddPair('content', LState.ResultText);
    Result.AddPair('input_line', TJSONNumber.Create(ALine));
    Result.AddPair('input_column', TJSONNumber.Create(AColumn));
    Result.AddPair('requires_open_editor', TJSONBool.Create(True));
  finally
    try
      TDAIOTA.RunOnMainThread(
        procedure
        begin
          LAsync := nil;
        end
      );
    finally
      System.TMonitor.Exit(GOperationLock);
    end;
  end;
end;

class function TDAICodeInsightService.Diagnostics(const AFileName: string): TJSONObject;
var
  LError: TOTAError;
  LErrorIndex: Integer;
  LErrors: TOTAErrors;
  LExpandedFileName: string;
  LFileOpen: Boolean;
  LItem: TJSONObject;
  LItems: TJSONArray;
  LProviderAvailable: Boolean;
  LReason: string;
  LStart: TJSONObject;
  LStop: TJSONObject;
begin
  LExpandedFileName := ExpandReadableFileName(AFileName);
  LErrors := [];
  LFileOpen := False;
  LProviderAvailable := False;
  LReason := '';

  TDAIOTA.RunOnMainThread(
    procedure
    var
      LModule: IOTAModule;
      LModuleErrors: IOTAModuleErrors;
    begin
      try
        LModule := TDAIOTA.FindModuleByFileName(LExpandedFileName);
        LFileOpen := Assigned(LModule);
        if not Assigned(LModule) then
        begin
          LReason := 'Error Insight ist nur für eine von der IDE geladene Datei verfügbar.';
          Exit;
        end;
        if not Supports(LModule, IOTAModuleErrors, LModuleErrors) then
        begin
          LReason := 'Das IDE-Modul stellt IOTAModuleErrors nicht bereit.';
          Exit;
        end;
        LErrors := LModuleErrors.GetErrors(LExpandedFileName);
        LProviderAvailable := True;
      except
        on E: Exception do
          LReason := E.Message;
      end;
    end
  );

  Result := TJSONObject.Create;
  Result.AddPair('file', LExpandedFileName);
  Result.AddPair('file_loaded_in_ide', TJSONBool.Create(LFileOpen));
  Result.AddPair('provider_available', TJSONBool.Create(LProviderAvailable));
  Result.AddPair('source', 'IDE Error Insight');
  Result.AddPair('diagnostics_api', 'IOTAModuleErrors.GetErrors');
  if LProviderAvailable then
    Result.AddPair('diagnostics_freshness', 'unknown')
  else
    Result.AddPair('diagnostics_freshness', 'unavailable');
  Result.AddPair('message', LReason);
  Result.AddPair('count', TJSONNumber.Create(Length(LErrors)));
  LItems := TJSONArray.Create;
  for LErrorIndex := 0 to High(LErrors) do
  begin
    LError := LErrors[LErrorIndex];
    LItem := TJSONObject.Create;
    LItem.AddPair('severity', SeverityName(LError.Severity));
    LItem.AddPair('severity_code', TJSONNumber.Create(LError.Severity));
    LItem.AddPair('message', LError.Text);
    LStart := TJSONObject.Create;
    LStart.AddPair('line', TJSONNumber.Create(LError.Start.Line));
    LStart.AddPair('character', TJSONNumber.Create(LError.Start.CharIndex));
    LItem.AddPair('start', LStart);
    LStop := TJSONObject.Create;
    LStop.AddPair('line', TJSONNumber.Create(LError.Stop.Line));
    LStop.AddPair('character', TJSONNumber.Create(LError.Stop.CharIndex));
    LItem.AddPair('end', LStop);
    LItems.AddElement(LItem);
  end;
  Result.AddPair('diagnostics', LItems);
end;

class function TDAICodeInsightService.ProjectContext(const AProjectNameOrPath: string; const AIncludeFiles: Boolean; const AMaximumFiles: Integer;
  const AIncludeCompilerOptions: Boolean): TJSONObject;
var
  LProject: IOTAProject;
  LResult: TJSONObject;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LActiveConfiguration: IOTABuildConfiguration;
      LCompilerOptions: TJSONObject;
      LConfigurationObject: TJSONObject;
      LConfigurations: IOTAProjectOptionsConfigurations;
      LFileIndex: Integer;
      LFiles: TStringList;
      LFilesArray: TJSONArray;
      LGuid: TGUID;
      LMaximumFiles: Integer;
      LPlatformConfiguration: IOTABuildConfiguration;
      LProjectFileName: string;
      LSupportedPlatforms: TArray<string>;
    begin
      LProjectFileName := TDAIOTA.NormalizeFileName(LProject.FileName);
      LResult := TJSONObject.Create;
      LResult.AddPair('project', LProjectFileName);
      LResult.AddPair('name', TPath.GetFileNameWithoutExtension(LProjectFileName));
      LResult.AddPair('directory', TPath.GetDirectoryName(LProjectFileName));
      LResult.AddPair('personality', LProject.Personality);
      LResult.AddPair('project_type', LProject.ProjectType);
      LResult.AddPair('application_type', LProject.ApplicationType);
      LResult.AddPair('framework_type', LProject.FrameworkType);
      LResult.AddPair('configuration', LProject.CurrentConfiguration);
      LResult.AddPair('platform', LProject.CurrentPlatform);
      if Assigned(LProject.ProjectOptions) then
        LResult.AddPair('target_name', LProject.ProjectOptions.TargetName)
      else
        LResult.AddPair('target_name', '');
      LGuid := LProject.ProjectGUID;
      LResult.AddPair('project_guid', GUIDToString(LGuid));
      LSupportedPlatforms := LProject.SupportedPlatforms;
      LResult.AddPair('supported_platforms', JsonStringArray(LSupportedPlatforms));
      LResult.AddPair('module_count', TJSONNumber.Create(LProject.GetModuleCount));

      LActiveConfiguration := nil;
      LConfigurationObject := TJSONObject.Create;
      if Supports(LProject.ProjectOptions, IOTAProjectOptionsConfigurations, LConfigurations) then
      begin
        LActiveConfiguration := LConfigurations.ActiveConfiguration;
        if Assigned(LActiveConfiguration) and (Trim(LProject.CurrentPlatform) <> '') then
          try
            LPlatformConfiguration := LActiveConfiguration.PlatformConfiguration[LProject.CurrentPlatform];
            if Assigned(LPlatformConfiguration) then
              LActiveConfiguration := LPlatformConfiguration;
          except
            LPlatformConfiguration := nil;
          end;
      end;
      LConfigurationObject.AddPair('available', TJSONBool.Create(Assigned(LActiveConfiguration)));
      if Assigned(LActiveConfiguration) then
      begin
        LConfigurationObject.AddPair('name', LActiveConfiguration.Name);
        LConfigurationObject.AddPair('key', LActiveConfiguration.Key);
        LConfigurationObject.AddPair('platform', LActiveConfiguration.Platform);
      end;
      LResult.AddPair('active_build_configuration', LConfigurationObject);

      if AIncludeCompilerOptions then
      begin
        LCompilerOptions := TJSONObject.Create;
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'defines', 'DCC_Define');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'unit_search_path', 'DCC_UnitSearchPath');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'namespaces', 'DCC_Namespace');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'include_path', 'DCC_IncludePath');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'library_path', 'DCC_LibraryPath');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'unit_aliases', 'DCC_UnitAlias');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'runtime_packages', 'DCC_UsePackage');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'exe_output', 'DCC_ExeOutput');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'dcu_output', 'DCC_DcuOutput');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'bpl_output', 'DCC_BplOutput');
        AddCompilerOption(LCompilerOptions, LActiveConfiguration, 'dcp_output', 'DCC_DcpOutput');
        LResult.AddPair('compiler_options', LCompilerOptions);
      end;

      if AIncludeFiles then
      begin
        LMaximumFiles := EnsureRange(AMaximumFiles, 1, 50000);
        LFiles := TStringList.Create;
        try
          LProject.GetCompleteFileList(LFiles);
          LFilesArray := TJSONArray.Create;
          for LFileIndex := 0 to Min(LFiles.Count, LMaximumFiles) - 1 do
            LFilesArray.Add(TDAIOTA.NormalizeFileName(LFiles[LFileIndex]));
          LResult.AddPair('files', LFilesArray);
          LResult.AddPair('file_count', TJSONNumber.Create(LFiles.Count));
          LResult.AddPair('files_truncated', TJSONBool.Create(LFiles.Count > LMaximumFiles));
        finally
          LFiles.Free;
        end;
      end;
    end
  );
  Result := LResult;
end;

initialization
  GCallbackRegistryLock := TCriticalSection.Create;
  GOperationLock := TObject.Create;
  if not GServiceShutdown then
    GCallbackBroker := TDAICodeInsightCallbackBroker.Create;

finalization
  // Pinning prevents unmapped code, not Delphi FinalizePackage. Detach the broker;
  // pending receivers keep its independent state alive until completion/process exit.
  TDAICodeInsightService.Shutdown;
  FreeAndNil(GOperationLock);
  FreeAndNil(GCallbackRegistryLock);

end.
