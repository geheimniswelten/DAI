unit h5u.DAI.Permissions.Manager;

interface

uses
  System.Generics.Collections,
  h5u.DAI.Types;

type
  TDAIPermissionManager = class sealed
  strict private
    class var FInstance: TDAIPermissionManager;
  private
    FLock: TObject;
    FOneShotAllows: TDictionary<string, Integer>;
    FOneShotDenials: TDictionary<string, Integer>;
    FSessionAllows: TDictionary<string, Boolean>;
    function AccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
    function WildcardAccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
    function GlobalWildcardAccessKey(const ACategory: TDAIPermissionCategory): string;
    procedure ClearRuntimeCategoryUnlocked(const ACategory: TDAIPermissionCategory; const AProjectKey: string);
    function ConsumeCounter(const ADictionary: TDictionary<string, Integer>; const AKey: string): Boolean;
    function EffectiveLevelUnlocked(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    procedure ApplyDecisionUnlocked(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext;
      const AForCurrentRequest: Boolean);
    procedure ApplyToLowerLevelsUnlocked(const ASourceCategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
  public
    constructor Create;
    destructor Destroy; override;
    class destructor Finalize;
    class function Instance: TDAIPermissionManager; static;
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext): Boolean;
    function GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    procedure SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
    procedure ClearProjectSession(const AProjectFileName: string);
    procedure ClearAllSessions;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Log,
  h5u.DAI.Permissions.Dialog,
  h5u.DAI.Permissions.Store;

function NormalizeKeyPart(const AValue: string): string;
begin
  Result := LowerCase(Trim(AValue));
  if Result = '' then
    Result := '<none>';
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
begin
  Result := NormalizeKeyPart(AContext.ProjectKey) + '|' + NormalizeKeyPart(AContext.SessionIdentity) + '|' + DAIPermissionCategoryKey(ACategory);
end;

function TDAIPermissionManager.WildcardAccessKey(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
begin
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
begin
  LKey := AccessKey(ACategory, AContext);

  case ALevel of
    plNever,
    plAlways:
      TDAIPermissionStore.SetLevel(ACategory, AContext.ProjectKey, ALevel);

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
      TDAIPermissionStore.SetLevel(ACategory, AContext.ProjectKey, plAsk);
  end;
end;

procedure TDAIPermissionManager.ApplyToLowerLevelsUnlocked(const ASourceCategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
var
  LCategory: TDAIPermissionCategory;
  LCurrentLevel: TDAIPermissionLevel;
begin
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
  begin
    if LCategory = ASourceCategory then
      Continue;

    LCurrentLevel := EffectiveLevelUnlocked(LCategory, AContext);
    if DAIPermissionLevelRank(LCurrentLevel) < DAIPermissionLevelRank(ALevel) then
      ApplyDecisionUnlocked(LCategory, ALevel, AContext, False);
  end;
end;

function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext): Boolean;
var
  LDecision: TDAIPermissionPromptResult;
  LGlobalWildcardKey: string;
  LKey: string;
  LLevel: TDAIPermissionLevel;
  LWildcardKey: string;
begin
  LKey := AccessKey(ACategory, AContext);
  LWildcardKey := WildcardAccessKey(ACategory, AContext);
  LGlobalWildcardKey := GlobalWildcardAccessKey(ACategory);

  System.TMonitor.Enter(FLock);
  try
    if ConsumeCounter(FOneShotDenials, LKey) or ConsumeCounter(FOneShotDenials, LWildcardKey) or
       ConsumeCounter(FOneShotDenials, LGlobalWildcardKey) then
    begin
      TDAILog.Access(DAIPermissionCategoryName(ACategory) + ' verweigert: ' + AOperation);
      Exit(False);
    end;

    if ConsumeCounter(FOneShotAllows, LKey) or ConsumeCounter(FOneShotAllows, LWildcardKey) or
       ConsumeCounter(FOneShotAllows, LGlobalWildcardKey) then
    begin
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
    ApplyDecisionUnlocked(ACategory, LDecision.Level, AContext, True);
    if LDecision.ApplyToLowerLevels then
      ApplyToLowerLevelsUnlocked(ACategory, LDecision.Level, AContext);
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

function TDAIPermissionManager.EffectiveLevelUnlocked(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
var
  LGlobalWildcardKey: string;
  LKey: string;
  LWildcardKey: string;
begin
  LKey := AccessKey(ACategory, AContext);
  LWildcardKey := WildcardAccessKey(ACategory, AContext);
  LGlobalWildcardKey := GlobalWildcardAccessKey(ACategory);

  if FSessionAllows.ContainsKey(LKey) or FSessionAllows.ContainsKey(LWildcardKey) or FSessionAllows.ContainsKey(LGlobalWildcardKey) then
    Exit(plSession);
  if FOneShotAllows.ContainsKey(LKey) or FOneShotAllows.ContainsKey(LWildcardKey) or FOneShotAllows.ContainsKey(LGlobalWildcardKey) then
    Exit(plOnce);
  if FOneShotDenials.ContainsKey(LKey) or FOneShotDenials.ContainsKey(LWildcardKey) or FOneShotDenials.ContainsKey(LGlobalWildcardKey) then
    Exit(plDeny);
  Result := TDAIPermissionStore.GetLevel(ACategory, AContext.ProjectKey);
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

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if FInstance = nil then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
begin
  System.TMonitor.Enter(FLock);
  try
    case ALevel of
      plNever,
      plAsk,
      plAlways:
        begin
          ClearRuntimeCategoryUnlocked(ACategory, AContext.ProjectKey);
          TDAIPermissionStore.SetLevel(ACategory, AContext.ProjectKey, ALevel);
        end;
      plDeny,
      plOnce,
      plSession:
        ApplyDecisionUnlocked(ACategory, ALevel, AContext, False);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
