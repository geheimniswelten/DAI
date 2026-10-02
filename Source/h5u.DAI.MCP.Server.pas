unit h5u.DAI.MCP.Server;

interface

uses
  System.Classes,
  System.SysUtils,
  h5u.DAI.MCP.Instance,
  h5u.DAI.MCP.Sessions,
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer,
  IdSocketHandle;

type
  TDAIHTTPServer = class(TIdHTTPServer)
  private
    FDeactivating: Boolean;
    FShutdownPending: Boolean;
    FLastStopDiagnostics: string;
    function GetShutdownPending: Boolean;
  protected
    procedure DoBeforeBind(AHandle: TIdSocketHandle); override;
    procedure DoConnect(AContext: TIdContext); override;
    procedure Startup; override;
    procedure Shutdown; override;
  public
    procedure Deactivate;
    property ShutdownPending: Boolean read GetShutdownPending;
    property Deactivating: Boolean read FDeactivating;
    property LastStopDiagnostics: string read FLastStopDiagnostics;
  end;

  TDAIMCPServer = class sealed
  private
    FHTTPServer: TDAIHTTPServer;
    FInstanceLease: TDAIMCPInstanceLease;
    FStateLock: TObject;
    FLastError: string;
    // Immutable while Indy workers run; replace only after complete shutdown.
    FPort: Integer;
    FToken: string;
    FSessions: TDAIMCPSessions;
    procedure HandleCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: string; var VUsername, VPassword: string; var VHandled: Boolean);
    procedure HandleDeleteSession(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure ResetAfterFailedStart;
    function GetPort: Integer;
    function StartUnlocked(const APort: Integer; const AToken: string): Boolean;
    function StopUnlocked(const AReleaseOwnership: Boolean = True): Boolean;
  public
    constructor Create(AIdleTimeoutMs: UInt64 = CDAIMCPSessionIdleTimeoutMs; AMaximumSessions: Integer = CDAIMCPMaximumSessions;
      const AClock: TFunc<UInt64> = nil; const AInstanceName: string = '');
    destructor Destroy; override;
    class function ValidateConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean; static;
    function Start: Boolean; overload;
    function Start(const APort: Integer; const AToken: string): Boolean; overload;
    function Stop: Boolean;
    function ApplySettings: Boolean;
    function Active: Boolean;
    property LastError: string read FLastError;
    property Port: Integer read GetPort;
  end;

implementation

uses
  System.JSON,
  System.RegularExpressions,
  IdException,
  IdStack,
  Winapi.Windows,
  Winapi.WinSock2,
  h5u.DAI.Consts,
  h5u.DAI.IDE.Control,
  h5u.DAI.Log,
  h5u.DAI.MCP.Protocol,
  h5u.DAI.Settings,
  h5u.DAI.WinAPI.TCP;

type
  TDAIListenerSnapshot = record
    Handle: TSocket;
    Address: TSockAddrIn;
    Listening: Boolean;
    ReadSucceeded: Boolean;
    SocketError: Integer;
    InheritanceKnown: Boolean;
    Inheritable: Boolean;
  end;

function ReadListenerSnapshot(const AHandle: TSocket): TDAIListenerSnapshot;
var
  LAcceptConnections: Integer;
  LSize: Integer;
  LHandleFlags: DWORD;
begin
  Result := Default(TDAIListenerSnapshot);
  Result.Handle := AHandle;
  Result.InheritanceKnown := GetHandleInformation(THandle(AHandle), LHandleFlags);
  if Result.InheritanceKnown then
    Result.Inheritable := (LHandleFlags and HANDLE_FLAG_INHERIT) <> 0;
  LAcceptConnections := 0;
  LSize := SizeOf(LAcceptConnections);
  if getsockopt(AHandle, SOL_SOCKET, SO_ACCEPTCONN, MarshaledAString(@LAcceptConnections), LSize) = SOCKET_ERROR then
  begin
    Result.SocketError := WSAGetLastError;
    Exit;
  end;
  LSize := SizeOf(Result.Address);
  if getsockname(AHandle, TSockAddr(Result.Address), LSize) = SOCKET_ERROR then
  begin
    Result.SocketError := WSAGetLastError;
    Exit;
  end;
  Result.ReadSucceeded := True;
  Result.Listening := (LAcceptConnections <> 0) and (Result.Address.sin_family = AF_INET);
end;

function ListenerSnapshotText(const ASnapshot: TDAIListenerSnapshot): string;
var
  LInheritance: string;
begin
  if not ASnapshot.ReadSucceeded then
    Exit(Format('Socket=%s, nicht lesbar, Winsock=%d', [IntToHex(NativeUInt(ASnapshot.Handle), SizeOf(TSocket) * 2), ASnapshot.SocketError]));
  if ASnapshot.InheritanceKnown then
    LInheritance := BoolToStr(ASnapshot.Inheritable, True)
  else
    LInheritance := 'unbekannt';
  Result := Format('Socket=%s, LISTEN=%s, Port=%d, vererbbar=%s', [IntToHex(NativeUInt(ASnapshot.Handle), SizeOf(TSocket) * 2),
    BoolToStr(ASnapshot.Listening, True), ntohs(ASnapshot.Address.sin_port), LInheritance]);
end;

function IndyExceptionText(const AException: Exception): string;
var
  LCurrent: Exception;
  LDepth: Integer;
begin
  Result := '';
  LCurrent := AException;
  LDepth := 0;
  while Assigned(LCurrent) and (LDepth < 8) do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + LCurrent.ClassName + ': ' + LCurrent.Message;
    if LCurrent is EIdSocketError then
      Result := Result + Format(' (Winsock=%d)', [EIdSocketError(LCurrent).LastError]);
    LCurrent := LCurrent.InnerException;
    Inc(LDepth);
  end;
end;

procedure MakeSocketNonInheritable(const ABinding: TIdSocketHandle);
var
  LFlags: DWORD;
begin
  if not Assigned(ABinding) then
    raise EInvalidOperation.Create('Der DAI-Socket ist vor dem Vererbungsschutz nicht verfügbar.');
  if not ABinding.HandleAllocated then
    raise EInvalidOperation.Create('Der DAI-Socket ist vor dem Vererbungsschutz nicht verfügbar.');
  // IDE child processes (LSP/debuggee/helpers) must not retain our socket object.
  if not SetHandleInformation(THandle(ABinding.Handle), HANDLE_FLAG_INHERIT, 0) then
    RaiseLastOSError(GetLastError, 'Der DAI-Socket konnte nicht gegen Handlevererbung geschützt werden.');
  if not GetHandleInformation(THandle(ABinding.Handle), LFlags) then
    RaiseLastOSError(GetLastError, 'Der Vererbungsschutz des DAI-Sockets konnte nicht geprüft werden.');
  if (LFlags and HANDLE_FLAG_INHERIT) <> 0 then
    raise EInvalidOperation.Create('Der DAI-Socket bleibt trotz Vererbungsschutz vererbbar.');
end;

procedure TDAIHTTPServer.DoBeforeBind(AHandle: TIdSocketHandle);
begin
  MakeSocketNonInheritable(AHandle);
  inherited;
end;

procedure TDAIHTTPServer.DoConnect(AContext: TIdContext);
begin
  MakeSocketNonInheritable(AContext.Binding);
  inherited;
end;

procedure TDAIHTTPServer.Startup;
begin
  FShutdownPending := True;
  inherited;
end;

procedure TDAIHTTPServer.Shutdown;
begin
  inherited;
  // Indy clears Active before Shutdown; only successful cleanup releases ownership.
  FShutdownPending := False;
end;

function TDAIHTTPServer.GetShutdownPending: Boolean;
begin
  // A Synchronize callback may run after Indy shutdown but before WaitFor returns.
  Result := FShutdownPending or FDeactivating;
end;

procedure TDAIHTTPServer.Deactivate;
var
  LThread: TThread;
  LFailureClass: string;
  LFailureMessage: string;
  LBefore: TArray<TDAIListenerSnapshot>;
  LAfter: TDAIListenerSnapshot;
  LIndex: Integer;
  LStackClass: string;
begin
  if FDeactivating then
    raise EInvalidOperation.Create('Die MCP-Serverbereinigung läuft bereits.');
  if not Active then
    Exit;

  SetLength(LBefore, Bindings.Count);
  if Assigned(GStack) then
    LStackClass := GStack.ClassName
  else
    LStackClass := 'nil';
  FLastStopDiagnostics := Format('Server=%s, Thread=%d, Stack=%s', [IntToHex(NativeUInt(Self), SizeOf(Pointer) * 2),
    GetCurrentThreadId, LStackClass]);
  for LIndex := 0 to Bindings.Count - 1 do
  begin
    LBefore[LIndex] := ReadListenerSnapshot(TSocket(Bindings[LIndex].Handle));
    FLastStopDiagnostics := FLastStopDiagnostics + '; vorher: ' + ListenerSnapshotText(LBefore[LIndex]);
  end;

  FDeactivating := True;
  try
    if GetCurrentThreadId <> MainThreadID then
    begin
      Active := False;
    end
    else
    begin
      // Close the listener on the IDE thread before draining workers in the helper.
      // Indy Shutdown calls StopListening again; its listener list is already empty.
      StopListening;

      // Main-thread WaitFor processes Synchronize requests from retiring HTTP workers.
      LThread := TThread.CreateAnonymousThread(
        procedure
        begin
          Self.Active := False;
        end
      );
      LThread.FreeOnTerminate := False;
      try
        LThread.Start;
        LThread.WaitFor;
        if Assigned(LThread.FatalException) then
        begin
          LFailureClass := LThread.FatalException.ClassName;
          if LThread.FatalException is Exception then
            LFailureMessage := Exception(LThread.FatalException).Message
          else
            LFailureMessage := 'Unbekannter Fehler bei der Serverbereinigung.';
          // The thread owns FatalException; propagate copied data in a new exception.
          raise EInvalidOperation.CreateFmt('MCP-Serverbereinigung im Hintergrund fehlgeschlagen: %s: %s', [LFailureClass, LFailureMessage]);
        end;
      finally
        LThread.Free;
      end;
    end;

    // Inspect only our saved handles. Never close a raw handle which may have been reused.
    for LIndex := 0 to High(LBefore) do
    begin
      LAfter := ReadListenerSnapshot(LBefore[LIndex].Handle);
      FLastStopDiagnostics := FLastStopDiagnostics + '; danach: ' + ListenerSnapshotText(LAfter);
      if LBefore[LIndex].Listening and LAfter.Listening and
        (LBefore[LIndex].Address.sin_addr.S_addr = LAfter.Address.sin_addr.S_addr) and
        (LBefore[LIndex].Address.sin_port = LAfter.Address.sin_port) then
      begin
        FShutdownPending := True;
        raise EInvalidOperation.Create('Ein bisheriger MCP-Socket ist nach Stop noch aktiv oder wurde für denselben Endpunkt wiederverwendet. ' + FLastStopDiagnostics);
      end;
    end;
    for LIndex := 0 to Bindings.Count - 1 do
      if Bindings[LIndex].HandleAllocated then
      begin
        FShutdownPending := True;
        raise EInvalidOperation.Create('Indy hält nach dem Stoppen noch eine Socketbindung. ' + FLastStopDiagnostics);
      end;
    TDAILog.Access('MCP-Stop abgeschlossen. ' + FLastStopDiagnostics);
  finally
    FDeactivating := False;
  end;
end;

function NewSessionId: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := LowerCase(StringReplace(StringReplace(GUIDToString(LGuid), '{', '', []), '}', '', []));
end;

function IsLoopbackAddress(const AAddress: string): Boolean;
begin
  Result := SameText(AAddress, '127.0.0.1') or SameText(AAddress, '::1') or SameText(AAddress, 'localhost');
end;

function IsAllowedOrigin(const AOrigin: string): Boolean;
begin
  Result := (AOrigin = '') or TRegEx.IsMatch(AOrigin,
    '^https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::[0-9]{1,5})?$', [roIgnoreCase]);
end;

function HasValidBearerToken(const ARequestInfo: TIdHTTPRequestInfo; const AExpectedToken: string): Boolean;
begin
  Result := ARequestInfo.AuthExists and SameText(ARequestInfo.AuthType, 'Bearer') and SameStr(ARequestInfo.AuthPassword, AExpectedToken);
end;

function ReadRequestBody(const ARequestInfo: TIdHTTPRequestInfo): string;
var
  LReader: TStreamReader;
begin
  Result := '';
  if not Assigned(ARequestInfo.PostStream) then
    Exit;
  if ARequestInfo.PostStream.Size > CDAIMaxRequestBytes then
    raise EInvalidOperation.CreateFmt('Die MCP-Anfrage überschreitet das Limit von %d MiB.', [CDAIMaxRequestBytes div 1024 div 1024]);

  ARequestInfo.PostStream.Position := 0;
  LReader := TStreamReader.Create(ARequestInfo.PostStream, TEncoding.UTF8, True, 4096);
  try
    Result := LReader.ReadToEnd;
  finally
    LReader.Free;
  end;
end;

function ErrorJson(const AMessage: string; const ACode: Integer = -32603; const AId: TJSONValue = nil): string;
var
  LError: TJSONObject;
  LRoot: TJSONObject;
begin
  LError := TJSONObject.Create;
  LRoot := TJSONObject.Create;
  try
    LError.AddPair('code', TJSONNumber.Create(ACode));
    LError.AddPair('message', AMessage);
    LRoot.AddPair('jsonrpc', '2.0');
    if Assigned(AId) and ((AId is TJSONString) or (AId is TJSONNumber)) then
      LRoot.AddPair('id', TJSONObject.ParseJSONValue(AId.ToJSON))
    else
      LRoot.AddPair('id', TJSONNull.Create);
    LRoot.AddPair('error', LError);
    LError := nil;
    Result := LRoot.ToJSON;
  finally
    LError.Free;
    LRoot.Free;
  end;
end;

function JsonObject(const AObject: TJSONObject; const AName: string): TJSONObject;
var
  LValue: TJSONValue;
begin
  Result := nil;
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.GetValue(AName);
  if LValue is TJSONObject then
    Result := TJSONObject(LValue);
end;

function UnsupportedVersionJson(const AId: TJSONValue; const ARequested: string): string;
var
  LRoot: TJSONObject;
  LData: TJSONObject;
begin
  LRoot := TJSONObject.ParseJSONValue(ErrorJson('Nicht unterstützte MCP-Protokollversion.', -32022, AId)) as TJSONObject;
  try
    LData := TJSONObject.Create;
    LData.AddPair('supported', TJSONArray.Create.Add('2026-07-28').Add('2025-11-25').Add('2025-06-18'));
    LData.AddPair('requested', ARequested);
    (LRoot.GetValue('error') as TJSONObject).AddPair('data', LData);
    Result := LRoot.ToJSON;
  finally
    LRoot.Free;
  end;
end;

function JsonString(const AObject: TJSONObject; const AName: string): string;
var
  LValue: TJSONValue;
begin
  Result := '';
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.GetValue(AName);
  if LValue is TJSONString then
    Result := LValue.Value;
end;

constructor TDAIMCPServer.Create(AIdleTimeoutMs: UInt64; AMaximumSessions: Integer; const AClock: TFunc<UInt64>; const AInstanceName: string);
begin
  inherited Create;
  FLastError := '';
  FStateLock := TObject.Create;
  FInstanceLease := TDAIMCPInstanceLease.Create(AInstanceName);
  FSessions := TDAIMCPSessions.Create(AIdleTimeoutMs, AMaximumSessions, AClock);
  FHTTPServer := TDAIHTTPServer.Create(nil);
  FHTTPServer.ServerSoftware := CDAIDisplayName + '/' + CDAIVersion;
  FHTTPServer.OnCommandGet := HandleCommand;
  FHTTPServer.OnCommandOther := HandleCommand;
  FHTTPServer.OnParseAuthentication := HandleParseAuthentication;
end;

destructor TDAIMCPServer.Destroy;
begin
  Stop;
  FHTTPServer.Free;
  FInstanceLease.Free;
  FStateLock.Free;
  FSessions.Free;
  inherited Destroy;
end;

procedure TDAIMCPServer.HandleParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: string; var VUsername, VPassword: string; var VHandled: Boolean);
begin
  if not SameText(AAuthType, 'Bearer') then
    Exit;

  VUsername := '';
  VPassword := Trim(AAuthData);
  VHandled := True;
end;

procedure TDAIMCPServer.HandleDeleteSession(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LProtocolHeader: string;
  LSession: TDAIMCPSession;
  LSessionId: string;
begin
  LProtocolHeader := ARequestInfo.RawHeaders.Values['MCP-Protocol-Version'];
  if LProtocolHeader = '2026-07-28' then
  begin
    AResponseInfo.ResponseNo := 405;
    AResponseInfo.CustomHeaders.Values['Allow'] := 'POST';
    AResponseInfo.ContentText := ErrorJson('Moderne MCP-Anfragen verwenden keine Transport-Sitzung.');
    Exit;
  end;
  if (LProtocolHeader <> '') and (LProtocolHeader <> '2025-11-25') and (LProtocolHeader <> '2025-06-18') then
  begin
    AResponseInfo.ResponseNo := 400;
    AResponseInfo.ContentText := UnsupportedVersionJson(nil, LProtocolHeader);
    Exit;
  end;
  LSessionId := Trim(ARequestInfo.RawHeaders.Values['Mcp-Session-Id']);
  if not FSessions.TryAcquire(LSessionId, LSession) then
  begin
    if LSessionId = '' then
      AResponseInfo.ResponseNo := 400
    else
      AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := ErrorJson('MCP-Sitzung fehlt oder ist abgelaufen.', -32600);
    Exit;
  end;
  try
    if (LProtocolHeader <> '') and (LProtocolHeader <> LSession.ProtocolVersion) then
    begin
      AResponseInfo.ResponseNo := 400;
      AResponseInfo.ContentText := ErrorJson('MCP-Protocol-Version stimmt nicht mit der Sitzung überein.', -32600);
      Exit;
    end;
    FSessions.Remove(LSessionId);
    AResponseInfo.ResponseNo := 204;
    AResponseInfo.ContentText := '';
    AResponseInfo.ContentLength := 0;
  finally
    FSessions.Release(LSessionId);
  end;
end;

function TDAIMCPServer.Active: Boolean;
begin
  Result := Assigned(FHTTPServer) and FHTTPServer.Active;
end;

function TDAIMCPServer.GetPort: Integer;
begin
  // HTTP status calls must not wait for the lock held during Indy shutdown.
  if Active then
    Result := FPort
  else
    Result := 0;
end;

class function TDAIMCPServer.ValidateConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean;
var
  LCharacter: Char;
begin
  AError := '';
  if (APort < 1024) or (APort > 65535) then
    AError := 'Der Port muss zwischen 1024 und 65535 liegen.'
  else if Trim(AToken) = '' then
    AError := 'Der Bearer-Token darf nicht leer sein.'
  else
    for LCharacter in AToken do
      if (Ord(LCharacter) < 32) or (Ord(LCharacter) = 127) then
      begin
        AError := 'Der Bearer-Token darf keine Steuerzeichen enthalten.';
        Break;
      end;
  Result := AError = '';
end;

function TDAIMCPServer.ApplySettings: Boolean;
var
  LPort: Integer;
  LToken: string;
begin
  System.TMonitor.Enter(FStateLock);
  try
    if FHTTPServer.Deactivating then
    begin
      FLastError := 'Der MCP-Server wird gerade gestoppt. Erst den vollständigen Abschluss abwarten.';
      Exit(False);
    end;
    // Autostart is evaluated once by Runtime.Start. Preserve manual Start/Stop here.
    if not Active then
      Exit(not FHTTPServer.ShutdownPending);
    LPort := TDAISettings.Instance.Port;
    LToken := TDAISettings.Instance.Token;
    if not ValidateConfiguration(LPort, LToken, FLastError) then
      Exit(False);
    if (FPort = LPort) and SameStr(FToken, Trim(LToken)) then
      Exit(True);
    // Rebinding the owner's endpoint retains the lease throughout the restart.
    if not StopUnlocked(False) then
      Exit(False);
    Result := StartUnlocked(LPort, LToken);
  finally
    System.TMonitor.Exit(FStateLock);
  end;
end;

function SuccessfulToolResponse(const AResponse: TJSONObject; const AHTTPStatus: Integer): Boolean;
var
  LResult: TJSONObject;
begin
  Result := False;
  if (AHTTPStatus <> 200) or not Assigned(AResponse) then
    Exit;
  if Assigned(AResponse.GetValue('error')) then
    Exit;
  LResult := JsonObject(AResponse, 'result');
  if not Assigned(LResult) then
    Exit;
  Result := not LResult.GetValue<Boolean>('isError', False);
end;

procedure TDAIMCPServer.HandleCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LHTTPStatus: Integer;
  LHealth: TJSONObject;
  LMessage: TJSONObject;
  LMeta: TJSONObject;
  LMethod: string;
  LModern: Boolean;
  LParams: TJSONObject;
  LProtocolHeader: string;
  LProtocolVersion: string;
  LOrigin: string;
  LResponseJson: TJSONObject;
  LSessionId: string;
  LSession: TDAIMCPSession;
  LSessionFound: Boolean;
  LText: string;
  LValue: TJSONValue;
begin
  TDAIIDEControl.ResetDeferredClose;
  AResponseInfo.ContentType := 'application/json';
  AResponseInfo.CharSet := 'utf-8';
  AResponseInfo.CustomHeaders.Values['Cache-Control'] := 'no-store';

  if not IsLoopbackAddress(AContext.Binding.PeerIP) then
  begin
    AResponseInfo.ResponseNo := 403;
    AResponseInfo.ContentText := ErrorJson('DAI akzeptiert ausschließlich lokale Verbindungen.');
    Exit;
  end;

  LOrigin := ARequestInfo.RawHeaders.Values['Origin'];
  if not IsAllowedOrigin(LOrigin) then
  begin
    AResponseInfo.ResponseNo := 403;
    AResponseInfo.ContentText := ErrorJson('Der HTTP-Origin ist nicht zugelassen.');
    Exit;
  end;

  if SameText(ARequestInfo.Document, '/health') and SameText(ARequestInfo.Command, 'GET') then
  begin
    LHealth := TJSONObject.Create;
    try
      LHealth.AddPair('name', CDAIName);
      LHealth.AddPair('version', CDAIVersion);
      LHealth.AddPair('active', TJSONBool.Create(Active));
      AResponseInfo.ResponseNo := 200;
      AResponseInfo.ContentText := LHealth.ToJSON;
    finally
      LHealth.Free;
    end;
    Exit;
  end;

  if not SameText(ARequestInfo.Document, CDAIMcpPath) then
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := ErrorJson('Unbekannter Endpunkt.');
    Exit;
  end;

  if not HasValidBearerToken(ARequestInfo, FToken) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.CustomHeaders.Values['WWW-Authenticate'] := 'Bearer realm="DAI"';
    AResponseInfo.ContentText := ErrorJson('Ungültige oder fehlende Autorisierung.');
    Exit;
  end;

  if SameText(ARequestInfo.Command, 'DELETE') then
  begin
    HandleDeleteSession(ARequestInfo, AResponseInfo);
    Exit;
  end;

  if not SameText(ARequestInfo.Command, 'POST') then
  begin
    AResponseInfo.ResponseNo := 405;
    AResponseInfo.CustomHeaders.Values['Allow'] := 'POST, DELETE';
    AResponseInfo.ContentText := ErrorJson('Für den MCP-Endpunkt sind POST und klassisches Session-DELETE erlaubt.');
    Exit;
  end;

  LSessionFound := False;
  try
    LText := ReadRequestBody(ARequestInfo);
    LValue := TJSONObject.ParseJSONValue(LText);
    try
      if not (LValue is TJSONObject) then
      begin
        AResponseInfo.ResponseNo := 400;
        AResponseInfo.ContentText := ErrorJson('Der Request-Body muss ein JSON-Objekt sein.', -32700);
        Exit;
      end;

      LMessage := TJSONObject(LValue);
      LMethod := JsonString(LMessage, 'method');
      LParams := JsonObject(LMessage, 'params');
      LMeta := JsonObject(LParams, '_meta');
      LProtocolVersion := JsonString(LMeta, 'io.modelcontextprotocol/protocolVersion');
      LProtocolHeader := ARequestInfo.RawHeaders.Values['MCP-Protocol-Version'];
      if ((LProtocolVersion <> '') and (LProtocolVersion <> '2026-07-28') and (LProtocolVersion <> '2025-11-25') and
          (LProtocolVersion <> '2025-06-18')) or
         ((LProtocolHeader <> '') and (LProtocolHeader <> '2026-07-28') and (LProtocolHeader <> '2025-11-25') and
          (LProtocolHeader <> '2025-06-18')) then
      begin
        AResponseInfo.ResponseNo := 400;
        if LProtocolVersion = '' then
          LProtocolVersion := LProtocolHeader;
        AResponseInfo.ContentText := UnsupportedVersionJson(LMessage.GetValue('id'), LProtocolVersion);
        Exit;
      end;
      LModern := (LProtocolVersion = '2026-07-28') or (LProtocolHeader = '2026-07-28') or (LMethod = 'server/discover');
      LSessionId := '';
      LSession := Default(TDAIMCPSession);
      if LModern then
      begin
        if (LProtocolHeader <> '2026-07-28') or (LProtocolVersion <> LProtocolHeader) or
           (ARequestInfo.RawHeaders.Values['Mcp-Method'] <> LMethod) or
           ((LMethod = 'tools/call') and (ARequestInfo.RawHeaders.Values['Mcp-Name'] <> JsonString(LParams, 'name'))) then
        begin
          AResponseInfo.ResponseNo := 400;
          AResponseInfo.ContentText := ErrorJson('Fehlende oder abweichende moderne MCP-HTTP-Header.', -32020, LMessage.GetValue('id'));
          Exit;
        end;
        // Modern requests are stateless: do not accept or emit transport session IDs.
      end
      else
      begin
        LSessionId := Trim(ARequestInfo.RawHeaders.Values['Mcp-Session-Id']);
        if LMethod = 'initialize' then
        begin
          if LSessionId <> '' then
          begin
            AResponseInfo.ResponseNo := 400;
            AResponseInfo.ContentText := ErrorJson('initialize muss ohne Mcp-Session-Id gesendet werden.', -32600, LMessage.GetValue('id'));
            Exit;
          end;
          LSessionId := NewSessionId;
          LSession.ClientName := JsonString(JsonObject(LParams, 'clientInfo'), 'name');
        end
        else
        begin
          LSessionFound := FSessions.TryAcquire(LSessionId, LSession);
          if not LSessionFound then
          begin
            if LSessionId = '' then
              AResponseInfo.ResponseNo := 400
            else
              AResponseInfo.ResponseNo := 404;
            AResponseInfo.ContentText := ErrorJson('MCP-Sitzung fehlt oder ist abgelaufen. initialize erneut senden.', -32600, LMessage.GetValue('id'));
            Exit;
          end;
          if (LProtocolHeader <> '') and (LProtocolHeader <> LSession.ProtocolVersion) then
          begin
            AResponseInfo.ResponseNo := 400;
            AResponseInfo.ContentText := ErrorJson('MCP-Protocol-Version stimmt nicht mit der initialisierten Sitzung überein.', -32600,
              LMessage.GetValue('id'));
            Exit;
          end;
        end;
      end;
      LResponseJson := TDAIMCPProtocol.HandleMessage(LMessage, LSessionId, LHTTPStatus, LSession.ClientName);
      try
        if not LModern then
        begin
          if (LMethod = 'initialize') and Assigned(LResponseJson) and Assigned(LResponseJson.GetValue('result')) then
          begin
            LSession.ProtocolVersion := JsonString(JsonObject(LResponseJson, 'result'), 'protocolVersion');
            if not FSessions.TryCreate(LSessionId, LSession) then
            begin
              AResponseInfo.ResponseNo := 503;
              AResponseInfo.CustomHeaders.Values['Retry-After'] := '60';
              AResponseInfo.ContentText := ErrorJson('Das Limit aktiver MCP-Sitzungen ist erreicht. Später erneut initialisieren.', -32000,
                LMessage.GetValue('id'));
              Exit;
            end;
          end;
          if (LMethod <> 'initialize') or (LSession.ProtocolVersion <> '') then
            AResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := LSessionId;
        end;
        AResponseInfo.ResponseNo := LHTTPStatus;
        if Assigned(LResponseJson) then
          AResponseInfo.ContentText := LResponseJson.ToJSON
        else
        begin
          AResponseInfo.ContentText := '';
          // Indy otherwise replaces an empty 202 response with an HTML status page.
          AResponseInfo.ContentLength := 0;
        end;
        if TDAIIDEControl.HasDeferredClose then
        begin
          if SuccessfulToolResponse(LResponseJson, LHTTPStatus) then
          begin
            // Send the acknowledgement before WM_CLOSE can start IDE/server teardown.
            // Indy clears ContentText after WriteContent and will not send it twice.
            AResponseInfo.WriteContent;
            TDAIIDEControl.CompleteDeferredClose;
          end;
        end;
      finally
        TDAIIDEControl.ResetDeferredClose;
        LResponseJson.Free;
      end;
    finally
      if LSessionFound then
        FSessions.Release(LSessionId);
      LValue.Free;
    end;
  except
    on E: Exception do
    begin
      TDAIIDEControl.ResetDeferredClose;
      TDAILog.Error('HTTP-MCP: ' + E.ClassName + ': ' + E.Message);
      AResponseInfo.ResponseNo := 500;
      AResponseInfo.ContentText := ErrorJson(E.ClassName + ': ' + E.Message);
    end;
  end;
end;

procedure TDAIMCPServer.ResetAfterFailedStart;
begin
  try
    if Assigned(FHTTPServer) then
      FHTTPServer.Deactivate;
  except
  end;
  if Assigned(FHTTPServer) and FHTTPServer.ShutdownPending then
    Exit;
  try
    if Assigned(FHTTPServer) then
      FHTTPServer.Bindings.Clear;
  except
  end;
  FPort := 0;
  FToken := '';
  FInstanceLease.Release;
end;

function TDAIMCPServer.Start: Boolean;
begin
  System.TMonitor.Enter(FStateLock);
  try
    if FHTTPServer.Deactivating then
    begin
      FLastError := 'Der MCP-Server wird gerade gestoppt. Erst den vollständigen Abschluss abwarten.';
      Exit(False);
    end;
    if Active then
    begin
      FLastError := '';
      Exit(True);
    end;
    Result := StartUnlocked(TDAISettings.Instance.Port, TDAISettings.Instance.Token);
  finally
    System.TMonitor.Exit(FStateLock);
  end;
end;

function TDAIMCPServer.Start(const APort: Integer; const AToken: string): Boolean;
begin
  System.TMonitor.Enter(FStateLock);
  try
    Result := StartUnlocked(APort, AToken);
  finally
    System.TMonitor.Exit(FStateLock);
  end;
end;

function TDAIMCPServer.StartUnlocked(const APort: Integer; const AToken: string): Boolean;
var
  LBinding: TIdSocketHandle;
  LOwnerDescription: string;
  LOwner: TDAITCPListenerOwner;
  LExceptionDescription: string;
begin
  if FHTTPServer.Deactivating then
  begin
    FLastError := 'Der MCP-Server wird gerade gestoppt. Erst den vollständigen Abschluss abwarten.';
    Exit(False);
  end;
  if not ValidateConfiguration(APort, AToken, FLastError) then
    Exit(False);
  if Active then
  begin
    if (FPort = APort) and SameStr(FToken, Trim(AToken)) then
    begin
      FLastError := '';
      Exit(True);
    end;
    FLastError := 'Der MCP-Server ist bereits aktiv. Zum Ändern von Port oder Token zuerst den Server stoppen.';
    Exit(False);
  end;

  FLastError := '';
  if FHTTPServer.ShutdownPending then
  begin
    FLastError := 'Der vorherige Server konnte nicht vollständig beendet werden. Diese IDE neu starten.';
    Exit(False);
  end;
  if not FInstanceLease.TryAcquire then
  begin
    FLastError := FInstanceLease.LastError;
    TDAILog.Access(FLastError);
    Exit(False);
  end;
  try
    FHTTPServer.Bindings.Clear;
    LBinding := FHTTPServer.Bindings.Add;
    LBinding.IP := CDAIDefaultBindAddress;
    LBinding.Port := APort;
    FPort := APort;
    FToken := Trim(AToken);
    FHTTPServer.Active := True;
    TDAILog.Access(Format('MCP-Server gestartet: http://%s:%d%s', [CDAIDefaultBindAddress, APort, CDAIMcpPath]));
    Result := True;
  except
    on E: EIdCouldNotBindSocket do
    begin
      LExceptionDescription := IndyExceptionText(E);
      ResetAfterFailedStart;
      if TDAITCPListener.TryFindIPv4Owner(APort, LOwner) then
        LOwnerDescription := 'Der Port ist bereits belegt. ' + TDAITCPListener.DescribeIPv4Owner(APort)
      else
        LOwnerDescription := 'In der Windows-TCP-Tabelle wurde kein lokaler Listener gefunden.';
      FLastError := Format(
        'Der MCP-Server konnte nicht an %s:%d gebunden werden. %s ' +
        'Das DAI-Package bleibt geladen; wählen Sie in den DAI-Einstellungen einen freien Port. Indy: %s',
        [CDAIDefaultBindAddress, APort, LOwnerDescription, LExceptionDescription]
      );
      if FHTTPServer.LastStopDiagnostics <> '' then
        FLastError := FLastError + ' Letzter Stop: ' + FHTTPServer.LastStopDiagnostics;
      TDAILog.Error(FLastError);
      Result := False;
    end;
    on E: Exception do
    begin
      ResetAfterFailedStart;
      FLastError := Format('Der MCP-Server konnte auf %s:%d nicht gestartet werden: %s: %s', [CDAIDefaultBindAddress, APort, E.ClassName, E.Message]);
      TDAILog.Error(FLastError);
      Result := False;
    end;
  end;
end;

function TDAIMCPServer.Stop: Boolean;
begin
  System.TMonitor.Enter(FStateLock);
  try
    Result := StopUnlocked;
  finally
    System.TMonitor.Exit(FStateLock);
  end;
end;

function TDAIMCPServer.StopUnlocked(const AReleaseOwnership: Boolean): Boolean;
begin
  if not Assigned(FHTTPServer) then
  begin
    if AReleaseOwnership and Assigned(FInstanceLease) then
      FInstanceLease.Release;
    Exit(True);
  end;
  try
    FHTTPServer.Deactivate;
    if FHTTPServer.ShutdownPending then
      raise EInvalidOperation.Create('Die vorherige Serverbereinigung ist nicht abgeschlossen. Diese IDE neu starten.');
    FHTTPServer.Bindings.Clear;
    FSessions.Clear;
    FPort := 0;
    FToken := '';
    if AReleaseOwnership then
      FInstanceLease.Release;
    FLastError := '';
    TDAILog.Access('MCP-Server gestoppt.');
    Result := True;
  except
    on E: Exception do
    begin
      FLastError := Format('Der MCP-Server konnte nicht sauber gestoppt werden: %s: %s', [E.ClassName, E.Message]);
      TDAILog.Error(FLastError);
      Result := False;
    end;
  end;
end;

end.
