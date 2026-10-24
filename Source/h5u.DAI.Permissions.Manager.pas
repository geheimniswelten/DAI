unit h5u.DAI.Permissions.Manager;

interface

uses
  System.Generics.Collections,
  h5u.DAI.Types;

type
  TDAIPermissionManager = class sealed
  strict private
    class var FInstance: TDAIPermissionManager;
    class var FChangeVersion: Integer;
  private
    FLock: TObject;
    FOneShotAllows: TDictionary<string, Integer>;
    FOneShotDenials: TDictionary<string, Integer>;
    FSessionAllows: TDictionary<string, Boolean>;
    function AccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
    function GlobalAccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
    function WildcardAccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
    function GlobalWildcardAccessKey(const ACategory: TDAIPermissionCategory): string;
    procedure ClearRuntimeCategoryUnlocked(const ACategory: TDAIPermissionCategory; const AProjectKey: string);
    function ConsumeCounter(const ADictionary: TDictionary<string, Integer>; const AKey: string): Boolean;
    function UseGlobalRuntime(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): Boolean;
    function ConsumeAccessCounter(const ADictionary: TDictionary<string, Integer>; const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): Boolean;
    function EffectiveLevelUnlocked(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    procedure ApplyDecisionUnlocked(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext;
      const AForCurrentRequest: Boolean);
  public
    class constructor Initialize;
    constructor Create;
    destructor Destroy; override;
    class destructor Finalize;
    class function ChangeVersion: Integer; static;
    class function Instance: TDAIPermissionManager; static;
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext): Boolean;
    function GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    function GetLevelForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext; out AInheritsGlobal: Boolean): TDAIPermissionLevel;
    procedure UseGlobalLevelFromOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext);
    procedure SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext;
      const ACurrentProjectKey: string = '');
    function GetAccessSummary(const AProjectKey: string; const AForIDE: Boolean): string;
    procedure ClearProjectSession(const AProjectFileName: string);
    procedure ClearAllSessions;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  Winapi.Windows,
  h5u.DAI.Log,
  h5u.DAI.Permissions.Dialog,
  h5u.DAI.Permissions.Store;

function NormalizeKeyPart(const AValue: string): string;
begin
  Result := LowerCase(Trim(AValue));
  if Result = '' then
    Result := '<none>';
  Result := StringReplace(Result, '%', '%25', [rfReplaceAll]);
  Result := StringReplace(Result, '|', '%7c', [rfReplaceAll]);
end;

constructor TDAIPermissionManager.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FOneShotAllows := TDictionary<string, Integer>.Create;
  FOneShotDenials := TDictionary<string, Integer>.Create;
  FSessionAllows := TDictionary<string, Boolean>.Create;
end;

destructor TDAIPermissionManager.Destroy;
begin
  FSessionAllows.Free;
  FOneShotDenials.Free;
  FOneShotAllows.Free;
  FLock.Free;
  inherited Destroy;
end;

class destructor TDAIPermissionManager.Finalize;
begin
  FInstance.Free;
  FInstance := nil;
end;

function TDAIPermissionManager.AccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
var
  LSession: string;
begin
  LSession := AContext.SessionIdentity;
  if (LSession <> '*') and (AContext.TransportSessionId <> '') and (AContext.ThreadId <> '') then
    LSession := LSession + ':transport:' + AContext.TransportSessionId;
  if LSession <> '*' then
    LSession := AContext.ClientName + ':' + LSession;
  if DAIPermissionCategoryIsGlobal(ACategory) then
    Result := '<none>'
  else
    Result := NormalizeKeyPart(AContext.ProjectKey);
  Result := Result + '|' + NormalizeKeyPart(LSession) + '|' + DAIPermissionCategoryKey(ACategory);
end;

function TDAIPermissionManager.GlobalAccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
var
  LContext: TDAIRequestContext;
begin
  LContext := AContext;
  LContext.ProjectKey := '';
  Result := AccessKey(ACategory, LContext);
end;

function TDAIPermissionManager.WildcardAccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
begin
  if DAIPermissionCategoryIsGlobal(ACategory) then
    Result := GlobalWildcardAccessKey(ACategory)
  else
    Result := NormalizeKeyPart(AContext.ProjectKey) + '|*|' + DAIPermissionCategoryKey(ACategory);
end;

function TDAIPermissionManager.GlobalWildcardAccessKey(const ACategory: TDAIPermissionCategory): string;
begin
  Result := '<none>|*|' + DAIPermissionCategoryKey(ACategory);
end;

procedure TDAIPermissionManager.ClearRuntimeCategoryUnlocked(const ACategory: TDAIPermissionCategory; const AProjectKey: string);
var
  LKey: string;
  LPrefix: string;
  LRemoveKeys: TList<string>;
  LSuffix: string;
begin
  LPrefix := NormalizeKeyPart(AProjectKey) + '|';
  LSuffix := '|' + DAIPermissionCategoryKey(ACategory);
  LRemoveKeys := TList<string>.Create;
  try
    for LKey in FOneShotAllows.Keys do
      if LKey.StartsWith(LPrefix, True) and LKey.EndsWith(LSuffix, True) then
        LRemoveKeys.Add(LKey);
    for LKey in LRemoveKeys do
      FOneShotAllows.Remove(LKey);

    LRemoveKeys.Clear;
    for LKey in FOneShotDenials.Keys do
      if LKey.StartsWith(LPrefix, True) and LKey.EndsWith(LSuffix, True) then
        LRemoveKeys.Add(LKey);
    for LKey in LRemoveKeys do
      FOneShotDenials.Remove(LKey);

    LRemoveKeys.Clear;
    for LKey in FSessionAllows.Keys do
      if LKey.StartsWith(LPrefix, True) and LKey.EndsWith(LSuffix, True) then
        LRemoveKeys.Add(LKey);
    for LKey in LRemoveKeys do
      FSessionAllows.Remove(LKey);
  finally
    LRemoveKeys.Free;
  end;
end;

procedure TDAIPermissionManager.ApplyDecisionUnlocked(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext;
  const AForCurrentRequest: Boolean);
var
  LCount: Integer;
  LKey: string;
  LProjectKey: string;
begin
  if ACategory = pcReferenceRead then
    Exit;
  LProjectKey := AContext.ProjectKey;
  if DAIPermissionCategoryIsGlobal(ACategory) then
    LProjectKey := '';
  LKey := AccessKey(ACategory, AContext);

  case ALevel of
    plNever,
    plAlways:
      begin
        TDAIPermissionStore.SetLevel(ACategory, LProjectKey, ALevel);
        ClearRuntimeCategoryUnlocked(ACategory, LProjectKey);
      end;

    plDeny:
      if not AForCurrentRequest then
      begin
        FOneShotDenials.TryGetValue(LKey, LCount);
        FOneShotDenials.AddOrSetValue(LKey, LCount + 1);
      end;

    plOnce:
      if not AForCurrentRequest then
      begin
        FOneShotAllows.TryGetValue(LKey, LCount);
        FOneShotAllows.AddOrSetValue(LKey, LCount + 1);
      end;

    plSession:
      if AContext.HasStableSessionIdentity then
        FSessionAllows.AddOrSetValue(LKey, True)
      else if not AForCurrentRequest then
      begin
        FOneShotAllows.TryGetValue(LKey, LCount);
        FOneShotAllows.AddOrSetValue(LKey, LCount + 1);
      end;

    plAsk:
      begin
        TDAIPermissionStore.SetLevel(ACategory, LProjectKey, plAsk);
        ClearRuntimeCategoryUnlocked(ACategory, LProjectKey);
      end;
  end;
end;

function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext): Boolean;
var
  LDecision: TDAIPermissionPromptResult;
  LDecisionContext: TDAIRequestContext;
  LLevel: TDAIPermissionLevel;
begin
  if ACategory = pcReferenceRead then
    Exit(True);
  System.TMonitor.Enter(FLock);
  try
    LLevel := EffectiveLevelUnlocked(ACategory, AContext);
    if LLevel = plNever then
      Exit(False);
    if ConsumeAccessCounter(FOneShotDenials, ACategory, AContext) then
    begin
      TInterlocked.Increment(FChangeVersion);
      TDAILog.Access(DAIPermissionCategoryName(ACategory) + ' verweigert: ' + AOperation);
      Exit(False);
    end;

    if ConsumeAccessCounter(FOneShotAllows, ACategory, AContext) then
    begin
      TInterlocked.Increment(FChangeVersion);
      TDAILog.Access(DAIPermissionCategoryName(ACategory) + ' einmalig erlaubt: ' + AOperation);
      Exit(True);
    end;

    LLevel := EffectiveLevelUnlocked(ACategory, AContext);
    case LLevel of
      plNever:
        Exit(False);
      plAlways,
      plSession:
        Exit(True);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;

  if GetCurrentThreadId = MainThreadID then
    LDecision := TDAIPermissionDialog.Ask(ACategory, AOperation, AResource, AContext)
  else
    TThread.Synchronize(nil,
      procedure
      begin
        LDecision := TDAIPermissionDialog.Ask(ACategory, AOperation, AResource, AContext);
      end);

  System.TMonitor.Enter(FLock);
  try
    LDecisionContext := AContext;
    if LDecision.ApplyGlobally or DAIPermissionCategoryIsGlobal(ACategory) then
      LDecisionContext.ProjectKey := '';
    ApplyDecisionUnlocked(ACategory, LDecision.Level, LDecisionContext, True);
    if (LDecisionContext.ProjectKey = '') and (Trim(AContext.ProjectKey) <> '') and not DAIPermissionCategoryIsGlobal(ACategory) then
    begin
      TDAIPermissionStore.RemoveProjectLevel(ACategory, AContext.ProjectKey);
      ClearRuntimeCategoryUnlocked(ACategory, AContext.ProjectKey);
    end;
    TInterlocked.Increment(FChangeVersion);
  finally
    System.TMonitor.Exit(FLock);
  end;

  Result := LDecision.Level in [plOnce, plSession, plAlways];
  TDAILog.Access(DAIPermissionCategoryName(ACategory) + ': ' + DAIPermissionLevelName(LDecision.Level) + ' – ' + AOperation);
end;

procedure TDAIPermissionManager.ClearAllSessions;
begin
  System.TMonitor.Enter(FLock);
  try
    FSessionAllows.Clear;
    FOneShotAllows.Clear;
    FOneShotDenials.Clear;
    TInterlocked.Increment(FChangeVersion);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TDAIPermissionManager.ClearProjectSession(const AProjectFileName: string);
var
  LKey: string;
  LNormalizedProject: string;
  LRemoveKeys: TList<string>;
begin
  LNormalizedProject := NormalizeKeyPart(AProjectFileName);
  LRemoveKeys := TList<string>.Create;
  try
    System.TMonitor.Enter(FLock);
    try
      for LKey in FOneShotAllows.Keys do
        if LKey.StartsWith(LNormalizedProject + '|', True) then
          LRemoveKeys.Add(LKey);
      for LKey in LRemoveKeys do
        FOneShotAllows.Remove(LKey);

      LRemoveKeys.Clear;
      for LKey in FOneShotDenials.Keys do
        if LKey.StartsWith(LNormalizedProject + '|', True) then
          LRemoveKeys.Add(LKey);
      for LKey in LRemoveKeys do
        FOneShotDenials.Remove(LKey);

      LRemoveKeys.Clear;
      for LKey in FSessionAllows.Keys do
        if LKey.StartsWith(LNormalizedProject + '|', True) then
          LRemoveKeys.Add(LKey);
      for LKey in LRemoveKeys do
        FSessionAllows.Remove(LKey);
      TInterlocked.Increment(FChangeVersion);
    finally
      System.TMonitor.Exit(FLock);
    end;
  finally
    LRemoveKeys.Free;
  end;
end;

function TDAIPermissionManager.ConsumeCounter(const ADictionary: TDictionary<string, Integer>; const AKey: string): Boolean;
var
  LCount: Integer;
begin
  Result := ADictionary.TryGetValue(AKey, LCount) and (LCount > 0);
  if not Result then
    Exit;

  if LCount = 1 then
    ADictionary.Remove(AKey)
  else
    ADictionary.AddOrSetValue(AKey, LCount - 1);
end;

function TDAIPermissionManager.UseGlobalRuntime(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): Boolean;
var
  LProjectLevel: TDAIPermissionLevel;
begin
  if DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '') then
    Exit(True);
  Result := not TDAIPermissionStore.TryGetProjectLevel(ACategory, AContext.ProjectKey, LProjectLevel);
end;

function TDAIPermissionManager.ConsumeAccessCounter(const ADictionary: TDictionary<string, Integer>; const ACategory: TDAIPermissionCategory;
  const AContext: TDAIRequestContext): Boolean;
begin
  if ConsumeCounter(ADictionary, AccessKey(ACategory, AContext)) then
    Exit(True);
  if ConsumeCounter(ADictionary, WildcardAccessKey(ACategory, AContext)) then
    Exit(True);
  if not UseGlobalRuntime(ACategory, AContext) then
    Exit(False);
  if ConsumeCounter(ADictionary, GlobalAccessKey(ACategory, AContext)) then
    Exit(True);
  Result := ConsumeCounter(ADictionary, GlobalWildcardAccessKey(ACategory));
end;

function TDAIPermissionManager.EffectiveLevelUnlocked(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
var
  LGlobalKey: string;
  LGlobalWildcardKey: string;
  LKey: string;
  LWildcardKey: string;
  LUseGlobal: Boolean;
begin
  if ACategory = pcReferenceRead then
    Exit(plAlways);
  LKey := AccessKey(ACategory, AContext);
  LGlobalKey := GlobalAccessKey(ACategory, AContext);
  LWildcardKey := WildcardAccessKey(ACategory, AContext);
  LGlobalWildcardKey := GlobalWildcardAccessKey(ACategory);
  LUseGlobal := UseGlobalRuntime(ACategory, AContext);

  Result := TDAIPermissionStore.GetLevel(ACategory, AContext.ProjectKey);
  if Result = plNever then
    Exit;
  if FOneShotDenials.ContainsKey(LKey) or FOneShotDenials.ContainsKey(LWildcardKey) or
    (LUseGlobal and (FOneShotDenials.ContainsKey(LGlobalKey) or FOneShotDenials.ContainsKey(LGlobalWildcardKey))) then
    Exit(plDeny);
  if FOneShotAllows.ContainsKey(LKey) or FOneShotAllows.ContainsKey(LWildcardKey) or
    (LUseGlobal and (FOneShotAllows.ContainsKey(LGlobalKey) or FOneShotAllows.ContainsKey(LGlobalWildcardKey))) then
    Exit(plOnce);
  if FSessionAllows.ContainsKey(LKey) or FSessionAllows.ContainsKey(LWildcardKey) or
    (LUseGlobal and (FSessionAllows.ContainsKey(LGlobalKey) or FSessionAllows.ContainsKey(LGlobalWildcardKey))) then
    Exit(plSession);
end;

class constructor TDAIPermissionManager.Initialize;
begin
  FInstance := TDAIPermissionManager.Create;
  FChangeVersion := 1;
end;

function TDAIPermissionManager.GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := EffectiveLevelUnlocked(ACategory, AContext);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TDAIPermissionManager.GetLevelForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext; out AInheritsGlobal: Boolean): TDAIPermissionLevel;
var
  LHasProjectLevel: Boolean;
  LHasRuntimeLevel: Boolean;
  LKey: string;
  LWildcardKey: string;
begin
  System.TMonitor.Enter(FLock);
  try
    AInheritsGlobal := False;
    if DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '') then
      Exit(EffectiveLevelUnlocked(ACategory, AContext));

    LKey := AccessKey(ACategory, AContext);
    LWildcardKey := WildcardAccessKey(ACategory, AContext);
    LHasProjectLevel := TDAIPermissionStore.TryGetProjectLevel(ACategory, AContext.ProjectKey, Result);
    LHasRuntimeLevel := FSessionAllows.ContainsKey(LKey) or FSessionAllows.ContainsKey(LWildcardKey) or
      FOneShotAllows.ContainsKey(LKey) or FOneShotAllows.ContainsKey(LWildcardKey) or
      FOneShotDenials.ContainsKey(LKey) or FOneShotDenials.ContainsKey(LWildcardKey);
    AInheritsGlobal := not LHasProjectLevel and not LHasRuntimeLevel;
    if AInheritsGlobal then
      Exit(EffectiveLevelUnlocked(ACategory, AContext));
    if not LHasProjectLevel then
      Result := TDAIPermissionStore.GetLevel(ACategory, '');
    if Result = plNever then
      Exit;

    if FOneShotDenials.ContainsKey(LKey) or FOneShotDenials.ContainsKey(LWildcardKey) then
      Exit(plDeny);
    if FOneShotAllows.ContainsKey(LKey) or FOneShotAllows.ContainsKey(LWildcardKey) then
      Exit(plOnce);
    if FSessionAllows.ContainsKey(LKey) or FSessionAllows.ContainsKey(LWildcardKey) then
      Exit(plSession);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TDAIPermissionManager.UseGlobalLevelFromOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext);
begin
  System.TMonitor.Enter(FLock);
  try
    TDAIPermissionStore.RemoveProjectLevel(ACategory, AContext.ProjectKey);
    ClearRuntimeCategoryUnlocked(ACategory, AContext.ProjectKey);
    TInterlocked.Increment(FChangeVersion);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  Result := FInstance;
end;

procedure TDAIPermissionManager.SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext;
  const ACurrentProjectKey: string);
var
  LContext: TDAIRequestContext;
begin
  if ACategory = pcReferenceRead then
    Exit;
  LContext := AContext;
  if DAIPermissionCategoryIsGlobal(ACategory) then
    LContext.ProjectKey := '';
  System.TMonitor.Enter(FLock);
  try
    ApplyDecisionUnlocked(ACategory, ALevel, LContext, False);
    if (LContext.ProjectKey = '') and (Trim(ACurrentProjectKey) <> '') and not DAIPermissionCategoryIsGlobal(ACategory) then
    begin
      TDAIPermissionStore.RemoveProjectLevel(ACategory, ACurrentProjectKey);
      ClearRuntimeCategoryUnlocked(ACategory, ACurrentProjectKey);
    end;
    TInterlocked.Increment(FChangeVersion);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class function TDAIPermissionManager.ChangeVersion: Integer;
begin
  Result := TInterlocked.CompareExchange(FChangeVersion, 0, 0);
end;

function TDAIPermissionManager.GetAccessSummary(const AProjectKey: string; const AForIDE: Boolean): string;
var
  LContext: TDAIRequestContext;
  LRead: TDAIPermissionLevel;
  LWrite: TDAIPermissionLevel;
  LCompile: TDAIPermissionLevel;
  LExecute: TDAIPermissionLevel;
begin
  if not AForIDE and (Trim(AProjectKey) = '') then
    Exit('kein Projekt');
  LContext := Default(TDAIRequestContext);
  LContext.ThreadId := '*';
  if not AForIDE then
    LContext.ProjectKey := AProjectKey;
  System.TMonitor.Enter(FLock);
  try
    if AForIDE then
    begin
      LRead := plAlways;
      LWrite := EffectiveLevelUnlocked(pcIDEOptions, LContext);
    end
    else
    begin
      LRead := EffectiveLevelUnlocked(pcProjectRead, LContext);
      LWrite := EffectiveLevelUnlocked(pcProjectWrite, LContext);
    end;
    LCompile := EffectiveLevelUnlocked(pcCompile, LContext);
    LExecute := EffectiveLevelUnlocked(pcExecute, LContext);
  finally
    System.TMonitor.Exit(FLock);
  end;
  if not (LRead in [plOnce, plSession, plAlways]) then
  begin
    if LRead in [plNever, plDeny] then
      Exit('gesperrt');
    Exit('nachfragen');
  end;
  Result := 'lesen';
  if not (LWrite in [plOnce, plSession, plAlways]) then
    Exit;
  Result := 'schreiben';
  if (LCompile in [plOnce, plSession, plAlways]) and (LExecute in [plOnce, plSession, plAlways]) then
    Result := 'Vollzugriff';
end;

end.
