unit h5u.DAI.Types;

interface

uses
  System.SysUtils;

type
  EDAIError = class(Exception);
  EDAIAccessDenied = class(EDAIError);
  EDAIFileNotFound = class(EDAIError);
  EDAIFileAlreadyExists = class(EDAIError);
  EDAIExecutableNotFound = class(EDAIFileNotFound);

  TDAIPermissionCategory = (
    pcReadAccess,
    pcEditInsideIDE,
    pcEditOutsideIDE,
    pcCompile,
    pcExecute
  );

  TDAIPermissionLevel = (
    plNever,
    plDeny,
    plAsk,
    plOnce,
    plSession,
    plAlways
  );

  TDAIPermissionScope = (
    psGlobal,
    psProject
  );

  TDAIRequestContext = record
  public
    ThreadId: string;
    TransportSessionId: string;
    ProjectKey: string;
    ClientName: string;
    function HasStableSessionIdentity: Boolean;
    function SessionIdentity: string;
  end;

  TDAIProcessResult = record
  public
    Started: Boolean;
    TimedOut: Boolean;
    ExitCode: Cardinal;
    Output: string;
    ErrorText: string;
    DurationMs: Int64;
  end;

function DAIPermissionCategoryName(const ACategory: TDAIPermissionCategory): string;
function DAIPermissionCategoryKey(const ACategory: TDAIPermissionCategory): string;
function DAIPermissionLevelName(const ALevel: TDAIPermissionLevel): string;
function DAIPermissionLevelKey(const ALevel: TDAIPermissionLevel): string;
function DAIPermissionLevelFromKey(const AValue: string): TDAIPermissionLevel;
function DAIPermissionLevelRank(const ALevel: TDAIPermissionLevel): Integer;

implementation

function DAIPermissionCategoryKey(const ACategory: TDAIPermissionCategory): string;
begin
  case ACategory of
    pcReadAccess:
      Result := 'read';
    pcEditInsideIDE:
      Result := 'edit_inside_ide';
    pcEditOutsideIDE:
      Result := 'edit_outside_ide';
    pcCompile:
      Result := 'compile';
    pcExecute:
      Result := 'execute';
  else
    Result := 'unknown';
  end;
end;

function DAIPermissionCategoryName(const ACategory: TDAIPermissionCategory): string;
begin
  case ACategory of
    pcReadAccess:
      Result := 'Lesezugriffe';
    pcEditInsideIDE:
      Result := 'Bearbeiten innerhalb der IDE';
    pcEditOutsideIDE:
      Result := 'Dateien außerhalb der IDE bearbeiten';
    pcCompile:
      Result := 'Kompilieren';
    pcExecute:
      Result := 'Ausführen';
  else
    Result := 'Unbekannte Funktionalität';
  end;
end;

function DAIPermissionLevelFromKey(const AValue: string): TDAIPermissionLevel;
begin
  if SameText(AValue, 'never') then
    Exit(plNever);
  if SameText(AValue, 'deny') then
    Exit(plDeny);
  if SameText(AValue, 'once') then
    Exit(plOnce);
  if SameText(AValue, 'session') then
    Exit(plSession);
  if SameText(AValue, 'always') then
    Exit(plAlways);
  Result := plAsk;
end;

function DAIPermissionLevelKey(const ALevel: TDAIPermissionLevel): string;
begin
  case ALevel of
    plNever:
      Result := 'never';
    plDeny:
      Result := 'deny';
    plAsk:
      Result := 'ask';
    plOnce:
      Result := 'once';
    plSession:
      Result := 'session';
    plAlways:
      Result := 'always';
  else
    Result := 'ask';
  end;
end;

function DAIPermissionLevelName(const ALevel: TDAIPermissionLevel): string;
begin
  case ALevel of
    plNever:
      Result := 'Nie erlauben';
    plDeny:
      Result := 'Verweigern';
    plAsk:
      Result := 'Nachfragen';
    plOnce:
      Result := 'Nur diesmal';
    plSession:
      Result := 'Für diese Session';
    plAlways:
      Result := 'Immer erlauben';
  else
    Result := 'Nachfragen';
  end;
end;

function DAIPermissionLevelRank(const ALevel: TDAIPermissionLevel): Integer;
begin
  case ALevel of
    plNever:
      Result := 0;
    plDeny,
    plAsk:
      Result := 1;
    plOnce:
      Result := 2;
    plSession:
      Result := 3;
    plAlways:
      Result := 4;
  else
    Result := 1;
  end;
end;

function TDAIRequestContext.HasStableSessionIdentity: Boolean;
begin
  Result := (Trim(ThreadId) <> '') or (Trim(TransportSessionId) <> '');
end;

function TDAIRequestContext.SessionIdentity: string;
begin
  if Trim(ThreadId) = '*' then
    Exit('*');
  if Trim(ThreadId) <> '' then
    Exit('chat:' + LowerCase(Trim(ThreadId)));
  if Trim(TransportSessionId) <> '' then
    Exit('transport:' + LowerCase(Trim(TransportSessionId)));
  Result := '';
end;

end.
