unit h5u.DAI.MCP.Sessions;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils;

const
  CDAIMCPSessionIdleTimeoutMs = 30 * 60 * 1000;
  CDAIMCPMaximumSessions = 1024;

type
  TDAIMCPSession = record
    ClientName: string;
    ProtocolVersion: string;
  end;

  TDAIMCPSessions = class sealed
  private type
    TEntry = record
      Session: TDAIMCPSession;
      LastActivityTick: UInt64;
      ActiveRequests: Integer;
    end;
  private
    FLock: TObject;
    FEntries: TDictionary<string, TEntry>;
    FRetired: TDictionary<string, Integer>;
    FIdleTimeoutMs: UInt64;
    FMaximumSessions: Integer;
    FClock: TFunc<UInt64>;
    function ReadTick: UInt64;
    procedure RemoveExpired(const ANow: UInt64);
  public
    // Acquire pins a session until the matching Release; AClock returns monotonic milliseconds.
    constructor Create(AIdleTimeoutMs: UInt64 = CDAIMCPSessionIdleTimeoutMs; AMaximumSessions: Integer = CDAIMCPMaximumSessions; const AClock: TFunc<UInt64> = nil);
    destructor Destroy; override;
    function TryCreate(const ASessionId: string; const ASession: TDAIMCPSession): Boolean;
    function TryAcquire(const ASessionId: string; out ASession: TDAIMCPSession): Boolean;
    procedure Release(const ASessionId: string);
    function Remove(const ASessionId: string): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

implementation

constructor TDAIMCPSessions.Create(AIdleTimeoutMs: UInt64; AMaximumSessions: Integer; const AClock: TFunc<UInt64>);
begin
  inherited Create;
  if AIdleTimeoutMs = 0 then
    raise EArgumentOutOfRangeException.Create('Der Sitzungstimeout muss positiv sein.');
  if AMaximumSessions < 1 then
    raise EArgumentOutOfRangeException.Create('Die Sitzungskapazitaet muss positiv sein.');
  FIdleTimeoutMs := AIdleTimeoutMs;
  FMaximumSessions := AMaximumSessions;
  FClock := AClock;
  FLock := TObject.Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FRetired := TDictionary<string, Integer>.Create;
end;

destructor TDAIMCPSessions.Destroy;
begin
  // The owner must finish all requests before destroying the store.
  FRetired.Free;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

function TDAIMCPSessions.ReadTick: UInt64;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := TThread.GetTickCount64;
end;

procedure TDAIMCPSessions.RemoveExpired(const ANow: UInt64);
var
  LPair: TPair<string, TEntry>;
begin
  for LPair in FEntries.ToArray do
  begin
    if (LPair.Value.ActiveRequests <> 0) or (ANow < LPair.Value.LastActivityTick) then
      Continue;
    if ANow - LPair.Value.LastActivityTick >= FIdleTimeoutMs then
      FEntries.Remove(LPair.Key);
  end;
end;

function TDAIMCPSessions.TryCreate(const ASessionId: string; const ASession: TDAIMCPSession): Boolean;
var
  LNow: UInt64;
  LEntry: TEntry;
begin
  Result := False;
  if ASessionId.Trim = '' then
    Exit;
  System.TMonitor.Enter(FLock);
  try
    LNow := ReadTick;
    RemoveExpired(LNow);
    if FEntries.ContainsKey(ASessionId) or FRetired.ContainsKey(ASessionId) or
      (FEntries.Count + FRetired.Count >= FMaximumSessions) then
      Exit;
    LEntry.Session := ASession;
    LEntry.LastActivityTick := LNow;
    LEntry.ActiveRequests := 0;
    FEntries.Add(ASessionId, LEntry);
    Result := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TDAIMCPSessions.TryAcquire(const ASessionId: string; out ASession: TDAIMCPSession): Boolean;
var
  LNow: UInt64;
  LEntry: TEntry;
begin
  ASession := Default(TDAIMCPSession);
  System.TMonitor.Enter(FLock);
  try
    LNow := ReadTick;
    RemoveExpired(LNow);
    Result := FEntries.TryGetValue(ASessionId, LEntry);
    if not Result then
      Exit;
    Inc(LEntry.ActiveRequests);
    if LNow > LEntry.LastActivityTick then
      LEntry.LastActivityTick := LNow;
    FEntries[ASessionId] := LEntry;
    ASession := LEntry.Session;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TDAIMCPSessions.Release(const ASessionId: string);
var
  LEntry: TEntry;
  LRetiredRequests: Integer;
  LNow: UInt64;
begin
  System.TMonitor.Enter(FLock);
  try
    if FRetired.TryGetValue(ASessionId, LRetiredRequests) then
    begin
      if LRetiredRequests = 1 then
        FRetired.Remove(ASessionId)
      else
        FRetired[ASessionId] := LRetiredRequests - 1;
    end
    else if FEntries.TryGetValue(ASessionId, LEntry) then
    begin
      if LEntry.ActiveRequests = 0 then
        Exit;
      LNow := ReadTick;
      Dec(LEntry.ActiveRequests);
      if LNow > LEntry.LastActivityTick then
        LEntry.LastActivityTick := LNow;
      FEntries[ASessionId] := LEntry;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TDAIMCPSessions.Remove(const ASessionId: string): Boolean;
var
  LEntry: TEntry;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FEntries.TryGetValue(ASessionId, LEntry);
    if Result then
    begin
      // Reserve removed IDs until old requests finish, preventing ID reuse races.
      if LEntry.ActiveRequests > 0 then
        FRetired.Add(ASessionId, LEntry.ActiveRequests);
      FEntries.Remove(ASessionId);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TDAIMCPSessions.Clear;
var
  LPair: TPair<string, TEntry>;
begin
  System.TMonitor.Enter(FLock);
  try
    for LPair in FEntries do
      if LPair.Value.ActiveRequests > 0 then
        FRetired.Add(LPair.Key, LPair.Value.ActiveRequests);
    FEntries.Clear;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TDAIMCPSessions.Count: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    // Removed in-flight requests reserve capacity but are no longer visible sessions.
    Result := FEntries.Count;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
