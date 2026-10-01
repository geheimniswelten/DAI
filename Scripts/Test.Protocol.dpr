program TestProtocol;

{$APPTYPE CONSOLE}

// Compile with the isolated test stubs first on the unit search path.
// The real MCP.Server/MCP.Protocol units are exercised against loopback HTTP.

uses
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SyncObjs,
  System.SysUtils,
  Winapi.Windows,
  IdHTTPServer,
  h5u.DAI.MCP.Server,
  h5u.DAI.MCP.Sessions,
  h5u.DAI.MCP.Tools,
  h5u.DAI.Settings;

const
  CModernMeta = '"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' +
    '"io.modelcontextprotocol/clientCapabilities":{}}';

var
  Client: THTTPClient;
  Server: TDAIMCPServer;
  CheckCount: Integer;
  ClockTick: UInt64;
  SessionId: string;
  InstanceName: string;
  InstanceGuid: TGUID;
  Response: IHTTPResponse;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function Post(const ABody: string; const ASession: string = ''; const AVersion: string = ''; const AMethod: string = '';
  const AName: string = ''; const AOrigin: string = ''; const AAuthenticate: Boolean = True;
  AOverridePort: Integer = 0; const AOverrideToken: string = ''): IHTTPResponse;
var
  Body: TStringStream;
  Headers: TNetHeaders;
  Count: Integer;
  LPort: Integer;
  LToken: string;

  procedure AddHeader(const AKey, AValue: string);
  begin
    SetLength(Headers, Count + 1);
    Headers[Count] := TNameValuePair.Create(AKey, AValue);
    Inc(Count);
  end;

begin
  Count := 0;
  LPort := AOverridePort;
  if LPort = 0 then
    LPort := TDAISettings.Instance.Port;
  LToken := AOverrideToken;
  if LToken = '' then
    LToken := 'isolated-test-token';
  if AAuthenticate then
    AddHeader('Authorization', 'Bearer ' + LToken);
  AddHeader('Content-Type', 'application/json');
  AddHeader('Accept', 'application/json, text/event-stream');
  if ASession <> '' then
    AddHeader('Mcp-Session-Id', ASession);
  if AVersion <> '' then
    AddHeader('MCP-Protocol-Version', AVersion);
  if AMethod <> '' then
    AddHeader('Mcp-Method', AMethod);
  if AName <> '' then
    AddHeader('Mcp-Name', AName);
  if AOrigin <> '' then
    AddHeader('Origin', AOrigin);
  Body := TStringStream.Create(ABody, TEncoding.UTF8);
  try
    Result := Client.Post('http://127.0.0.1:' + IntToStr(LPort) + '/mcp', Body, nil, Headers);
  finally
    Body.Free;
  end;
end;

function DeleteSession(const ASession: string; const AVersion: string = ''; const AAuthenticate: Boolean = True;
  const AOrigin: string = ''): IHTTPResponse;
var
  Headers: TNetHeaders;
begin
  SetLength(Headers, 0);
  if ASession <> '' then
  begin
    SetLength(Headers, 1);
    Headers[0] := TNameValuePair.Create('Mcp-Session-Id', ASession);
  end;
  if AVersion <> '' then
  begin
    SetLength(Headers, Length(Headers) + 1);
    Headers[High(Headers)] := TNameValuePair.Create('MCP-Protocol-Version', AVersion);
  end;
  if AAuthenticate then
  begin
    SetLength(Headers, Length(Headers) + 1);
    Headers[High(Headers)] := TNameValuePair.Create('Authorization', 'Bearer isolated-test-token');
  end;
  if AOrigin <> '' then
  begin
    SetLength(Headers, Length(Headers) + 1);
    Headers[High(Headers)] := TNameValuePair.Create('Origin', AOrigin);
  end;
  Result := Client.Delete('http://127.0.0.1:' + IntToStr(TDAISettings.Instance.Port) + '/mcp', nil, Headers);
end;

function InitializeSession: IHTTPResponse;
begin
  Result := Post('{"jsonrpc":"2.0","id":"capacity","method":"initialize","params":' +
    '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"CapacityTest","version":"1"}}}');
end;

procedure RunChecks;
begin
  Response := Post('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
    '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"IsolatedTest","version":"1"}}}');
  Check(Response.StatusCode = 200, 'legacy initialize');
  SessionId := Response.HeaderValue['Mcp-Session-Id'];
  Check(SessionId <> '', 'server-issued legacy session');
  Check(Pos('2025-06-18', Response.ContentAsString) > 0, 'legacy negotiated version');

  Response := Post('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}', SessionId);
  Check((Response.StatusCode = 202) and (Response.ContentAsString = ''),
    'notification returns empty 202; status=' + IntToStr(Response.StatusCode) + '; body=' + Response.ContentAsString);
  Response := Post('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"test","arguments":{}}}', SessionId);
  Check((Response.StatusCode = 200) and (TDAIMCPTools.CallCount = 1), 'legacy tool executes once');
  Response := Post('{"jsonrpc":"2.0","method":"tools/call","params":{"name":"test","arguments":{}}}', SessionId);
  Check((Response.StatusCode = 202) and (TDAIMCPTools.CallCount = 1), 'tool notification cannot execute');
  Response := Post('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"test","arguments":{},"_meta":{"threadId":"*"}}}', SessionId);
  Check((Response.StatusCode = 200) and (Pos('"thread":""', Response.ContentAsString) > 0), 'remote wildcard is not a chat identity');

  Response := Post('{"jsonrpc":"2.0","id":3,"method":"ping"}', 'not-issued-by-server');
  Check(Response.StatusCode = 404, 'reject unknown session');
  Response := Post('{"jsonrpc":"2.0","id":3,"method":"ping"}');
  Check(Response.StatusCode = 400, 'reject absent legacy session');
  Response := Post('{"jsonrpc":"2.0","id":null,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 400, 'reject null id');
  Response := Post('{"jsonrpc":"2.0","id":1.5,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 400, 'reject fractional id');
  Response := Post('{"jsonrpc":"2.0","id":3,"method":"ping","params":[]}', SessionId);
  Check(Response.StatusCode = 400, 'reject nonobject params');
  Response := Post('this is not JSON', SessionId);
  Check((Response.StatusCode = 400) and (Pos('-32700', Response.ContentAsString) > 0), 'parse error');

  Response := Post('{"jsonrpc":"2.0","id":4,"method":"ping","params":{' + CModernMeta + '}}', '', '2026-07-28', 'ping');
  Check(Response.StatusCode = 200, 'modern stateless ping');
  Check(Response.HeaderValue['Mcp-Session-Id'] = '', 'modern response has no session');
  Check(Pos('"resultType":"complete"', Response.ContentAsString) > 0, 'modern result type');
  Response := Post('{"jsonrpc":"2.0","id":5,"method":"server/discover","params":{' + CModernMeta + '}}', '', '2026-07-28', 'server/discover');
  Check((Response.StatusCode = 200) and (Pos('supportedVersions', Response.ContentAsString) > 0), 'modern discovery');
  Response := Post('{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"test","arguments":{},' +
    CModernMeta + '}}', '', '2026-07-28', 'tools/call', 'test');
  Check((Response.StatusCode = 200) and (TDAIMCPTools.CallCount = 3), 'modern tool executes once');
  Response := Post('{"jsonrpc":"2.0","id":7,"method":"ping","params":{' + CModernMeta + '}}', '', '2026-07-28', 'tools/list');
  Check((Response.StatusCode = 400) and (Pos('-32020', Response.ContentAsString) > 0), 'reject mismatched method header');
  Response := Post('{"jsonrpc":"2.0","id":7,"method":"ping","params":{' +
    '"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}', '', '2026-07-28', 'ping');
  Check((Response.StatusCode = 400) and (Pos('-32602', Response.ContentAsString) > 0), 'require modern capabilities');
  Response := Post('{"jsonrpc":"2.0","id":8,"method":"ping"}', SessionId, '1900-01-01');
  Check((Response.StatusCode = 400) and (Pos('-32022', Response.ContentAsString) > 0), 'unsupported version');

  Response := Post('{"jsonrpc":"2.0","id":9,"method":"ping"}', SessionId, '', '', '', 'http://localhost.evil.example');
  Check(Response.StatusCode = 403, 'reject hostname prefix attack');
  Response := Post('{"jsonrpc":"2.0","id":9,"method":"ping"}', SessionId, '', '', '', 'http://127.0.0.1.evil.example');
  Check(Response.StatusCode = 403, 'reject IP prefix attack');
  Response := Post('{"jsonrpc":"2.0","id":9,"method":"ping"}', SessionId, '', '', '', 'http://localhost:1234');
  Check(Response.StatusCode = 200, 'allow exact loopback origin');
  Response := Post('{"jsonrpc":"2.0","id":9,"method":"ping"}', SessionId, '', '', '', '', False);
  Check(Response.StatusCode = 401, 'require bearer authentication');

  Response := DeleteSession(SessionId, '1900-01-01');
  Check(Response.StatusCode = 400, 'DELETE rejects unsupported protocol');
  Response := DeleteSession(SessionId, '2025-11-25');
  Check(Response.StatusCode = 400, 'DELETE rejects wrong negotiated protocol');
  Response := DeleteSession(SessionId, '2026-07-28');
  Check(Response.StatusCode = 405, 'modern stateless DELETE is unsupported');
  Response := DeleteSession(SessionId, '', False);
  Check(Response.StatusCode = 401, 'DELETE requires bearer');
  Response := DeleteSession(SessionId, '', True, 'http://evil.example');
  Check(Response.StatusCode = 403, 'DELETE validates Origin');
  Response := Post('{"jsonrpc":"2.0","id":10,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 200, 'rejected DELETE preserves session');
  Response := DeleteSession('unknown-session');
  Check(Response.StatusCode = 404, 'DELETE rejects unknown session');
  Response := DeleteSession('');
  Check(Response.StatusCode = 400, 'DELETE rejects absent session');

  Response := InitializeSession;
  Check(Response.StatusCode = 200, 'second session');
  Response := InitializeSession;
  Check(Response.StatusCode = 200, 'third session');
  Response := InitializeSession;
  Check((Response.StatusCode = 503) and (Response.HeaderValue['Mcp-Session-Id'] = ''), 'capacity rejects new session');
  Check(Pos('"id":"capacity"', Response.ContentAsString) > 0, 'capacity error retains request id');
  Response := Post('{"jsonrpc":"2.0","id":11,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 200, 'capacity preserves established session');
  Response := DeleteSession(SessionId, '2025-06-18');
  Check((Response.StatusCode = 204) and (Response.ContentAsString = ''), 'DELETE terminates with empty 204');
  Response := Post('{"jsonrpc":"2.0","id":12,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 404, 'deleted session cannot execute');
  Response := InitializeSession;
  Check(Response.StatusCode = 200, 'DELETE frees capacity');
  SessionId := Response.HeaderValue['Mcp-Session-Id'];

  ClockTick := CDAIMCPSessionIdleTimeoutMs div 2;
  Response := Post('{"jsonrpc":"2.0","id":13,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 200, 'session activity refreshes timeout');
  ClockTick := CDAIMCPSessionIdleTimeoutMs;
  Response := InitializeSession;
  Check(Response.StatusCode = 200, 'initialization reclaims other expired sessions');
  Response := Post('{"jsonrpc":"2.0","id":14,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 200, 'recently active session survives other expirations');
  ClockTick := 2 * CDAIMCPSessionIdleTimeoutMs;
  Response := Post('{"jsonrpc":"2.0","id":15,"method":"ping"}', SessionId);
  Check(Response.StatusCode = 404, 'idle timeout rejects expired session');
  Response := Post('{"jsonrpc":"2.0","id":16,"method":"ping","params":{' + CModernMeta + '}}', '', '2026-07-28', 'ping');
  Check(Response.StatusCode = 200, 'idle cleanup leaves modern stateless requests working');
end;

procedure RunInstanceChecks;
var
  Other: TDAIMCPServer;
  Blocker: TIdHTTPServer;
  OriginalPort: Integer;
begin
  OriginalPort := TDAISettings.Instance.Port;
  Other := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3, nil, InstanceName);
  Blocker := TIdHTTPServer.Create(nil);
  try
    TDAISettings.Instance.Port := OriginalPort + 20;
    Check(not Other.Start and not Other.Active, 'another instance cannot start even on another port');
    Check(Other.LastError <> '', 'waiting instance explains ownership');
    Check(Other.Stop, 'stopping waiting instance is harmless');
    TDAISettings.Instance.Port := OriginalPort;
    Response := Post('{"jsonrpc":"2.0","id":17,"method":"ping","params":{' + CModernMeta + '}}', '', '2026-07-28', 'ping');
    Check(Response.StatusCode = 200, 'waiting instance does not stop current owner');
    Check(Server.Stop, 'owner stops and releases lease');
    TDAISettings.Instance.Port := OriginalPort + 20;
    Check(Other.Start, 'manual takeover after owner stops');
    TDAISettings.Instance.Port := OriginalPort;
    Check(not Server.Start, 'previous owner cannot start while new owner serves another port');
    Check(Other.Stop, 'new owner can release ownership');
    Check(Server.Start, 'previous owner can reacquire');
    Check(Server.Start, 'repeated start stays idempotent');
    TDAISettings.Instance.Enabled := False;
    Check(Server.ApplySettings and Server.Active, 'disabling autostart preserves manually running server');
    TDAISettings.Instance.Port := OriginalPort + 40;
    Check(Server.ApplySettings and Server.Active, 'owner rebinds after port change');
    Response := Post('{"jsonrpc":"2.0","id":18,"method":"ping","params":{' + CModernMeta + '}}', '', '2026-07-28', 'ping');
    Check(Response.StatusCode = 200, 'rebound endpoint responds');
    TDAISettings.Instance.Port := OriginalPort + 20;
    Check(not Other.Start, 'reconfigure retains ownership');
    TDAISettings.Instance.Port := OriginalPort;
    Check(Server.ApplySettings and Server.Active, 'owner rebinds to original port');

    Check(Server.Stop, 'stop before failed-bind test');
    TDAISettings.Instance.Enabled := True;
    Check(Server.ApplySettings and not Server.Active, 'apply with autostart enabled preserves manual stop');
    Blocker.Bindings.Add.IP := '127.0.0.1';
    Blocker.Bindings[0].Port := OriginalPort;
    Blocker.Active := True;
    Check(not Server.Start, 'occupied port rejects startup');
    TDAISettings.Instance.Port := OriginalPort + 20;
    Check(Other.Start, 'failed bind releases ownership after cleanup');
    Check(Other.Stop, 'stop takeover after failed bind');
    Blocker.Active := False;
    TDAISettings.Instance.Port := OriginalPort;
    Check(Server.Start, 'successful restart after bind failure');
  finally
    Other.Free;
    Blocker.Free;
    TDAISettings.Instance.Port := OriginalPort;
  end;
end;

function ExplicitPing(APort: Integer; const AToken: string): IHTTPResponse;
begin
  Result := Post('{"jsonrpc":"2.0","id":"explicit","method":"ping","params":{' + CModernMeta + '}}',
    '', '2026-07-28', 'ping', '', '', True, APort, AToken);
end;

function StartOnFreePort(AServer: TDAIMCPServer; AFirstPort: Integer; const AToken: string): Integer;
begin
  for Result := AFirstPort to AFirstPort + 10 do
    if AServer.Start(Result, AToken) then
      Exit;
  raise Exception.Create('No isolated test port available: ' + AServer.LastError);
end;

procedure RunExplicitSettingsChecks;
const
  CTemporaryToken = 'isolated-temporary-token';
  CRotatedToken = 'isolated-rotated-token';
var
  LOriginalPort: Integer;
  LOriginalToken: string;
  LTemporaryPort: Integer;
  LLegacySession: string;
  LOther: TDAIMCPServer;
  LBlocker: TIdHTTPServer;
begin
  LOriginalPort := TDAISettings.Instance.Port;
  LOriginalToken := TDAISettings.Instance.Token;
  LOther := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3, nil, InstanceName);
  LBlocker := TIdHTTPServer.Create(nil);
  try
    Check(Server.Stop and (Server.Port = 0), 'explicit start test begins with stopped endpoint');
    Check(not Server.Start(1023, CTemporaryToken) and not Server.Active, 'explicit start rejects reserved port');
    Check(not Server.Start(65536, CTemporaryToken) and not Server.Active, 'explicit start rejects overflowing port');
    Check(not Server.Start(LOriginalPort + 60, '') and not Server.Active, 'explicit start rejects empty token');
    Check(not Server.Start(LOriginalPort + 60, 'invalid' + #13#10 + 'token') and not Server.Active, 'explicit start rejects control characters in token');
    LTemporaryPort := StartOnFreePort(Server, LOriginalPort + 60, CTemporaryToken);
    Check(Server.Active and (Server.Port = LTemporaryPort), 'explicit startup exposes actual listener port');
    Check((TDAISettings.Instance.Port = LOriginalPort) and (TDAISettings.Instance.Token = LOriginalToken), 'explicit startup retains stored settings');
    Response := ExplicitPing(LTemporaryPort, CTemporaryToken);
    Check(Response.StatusCode = 200, 'explicit endpoint accepts temporary token');
    Response := ExplicitPing(LTemporaryPort, LOriginalToken);
    Check(Response.StatusCode = 401, 'explicit endpoint rejects stored token');
    Check(Server.Start(LTemporaryPort, CTemporaryToken) and Server.Start and (Server.Port = LTemporaryPort),
      'same explicit settings and parameterless start remain idempotent');
    Check(not Server.Start(LTemporaryPort + 1, CTemporaryToken) and (Server.LastError <> ''), 'different explicit port cannot silently replace active endpoint');
    Check(not Server.Start(LTemporaryPort, CRotatedToken) and (Server.LastError <> ''), 'different explicit token cannot silently replace active endpoint');
    Response := ExplicitPing(LTemporaryPort, CTemporaryToken);
    Check(Response.StatusCode = 200, 'rejected explicit reconfiguration preserves running endpoint');
    Response := Post('{"jsonrpc":"2.0","id":"explicit-session","method":"initialize","params":' +
      '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ExplicitTest","version":"1"}}}',
      '', '', '', '', '', True, LTemporaryPort, CTemporaryToken);
    LLegacySession := Response.HeaderValue['Mcp-Session-Id'];
    Check((Response.StatusCode = 200) and (LLegacySession <> ''), 'explicit endpoint creates isolated legacy session');
    TDAISettings.Instance.Port := LTemporaryPort;
    TDAISettings.Instance.Token := CRotatedToken;
    Response := ExplicitPing(LTemporaryPort, CTemporaryToken);
    Check(Response.StatusCode = 200, 'settings mutation cannot change active auth snapshot');
    Response := ExplicitPing(LTemporaryPort, CRotatedToken);
    Check(Response.StatusCode = 401, 'unapplied settings token remains invalid');
    Check(Server.ApplySettings and Server.Active and (Server.Port = LTemporaryPort), 'apply updates token at unchanged port');
    Response := ExplicitPing(LTemporaryPort, CRotatedToken);
    Check(Response.StatusCode = 200, 'applied token accepted');
    Response := ExplicitPing(LTemporaryPort, CTemporaryToken);
    Check(Response.StatusCode = 401, 'old temporary token rejected after apply');
    Response := Post('{"jsonrpc":"2.0","id":"old-session","method":"ping"}', LLegacySession,
      '', '', '', '', True, LTemporaryPort, CRotatedToken);
    Check(Response.StatusCode = 404, 'token restart clears previous legacy sessions');
    TDAISettings.Instance.Port := LOriginalPort;
    TDAISettings.Instance.Token := LOriginalToken;
    Check(Server.Stop and not Server.Active and (Server.Port = 0), 'stop clears explicit active endpoint port');
    LBlocker.Bindings.Add.IP := '127.0.0.1';
    LBlocker.Bindings[0].Port := LTemporaryPort;
    LBlocker.Active := True;
    Check(not Server.Start(LTemporaryPort, CTemporaryToken) and not Server.Active and (Server.Port = 0) and (Server.LastError <> ''),
      'failed explicit bind clears listener state');
    Check((TDAISettings.Instance.Port = LOriginalPort) and (TDAISettings.Instance.Token = LOriginalToken), 'failed explicit bind retains stored settings');
    Check(StartOnFreePort(LOther, LTemporaryPort + 20, CTemporaryToken) > 0, 'failed explicit bind releases instance ownership');
    if not LOther.Stop then
      raise Exception.Create(LOther.LastError);
    LBlocker.Active := False;
    Check(Server.Start(LOriginalPort, LOriginalToken) and (Server.Port = LOriginalPort), 'explicit start recovers after failed bind');
  finally
    TDAISettings.Instance.Port := LOriginalPort;
    TDAISettings.Instance.Token := LOriginalToken;
    LOther.Free;
    LBlocker.Free;
  end;
end;

procedure RunSynchronizedShutdownChecks;
var
  LRequestThread: TThread;
  LWatchdog: TThread;
  LRequestFinished: TEvent;
  LTestFinished: TEvent;
  LOther: TDAIMCPServer;
  LPort: Integer;
  LToken: string;
  LMainThreadId: Cardinal;
  LReentrantStartRejected: Boolean;
  LReentrantStartError: string;
begin
  LPort := Server.Port;
  LToken := TDAISettings.Instance.Token;
  LMainThreadId := GetCurrentThreadId;
  LReentrantStartRejected := False;
  LReentrantStartError := '';
  LRequestFinished := TEvent.Create(nil, True, False, '');
  LTestFinished := TEvent.Create(nil, True, False, '');
  TDAIMCPTools.SynchronizeEntered := TEvent.Create(nil, True, False, '');
  TDAIMCPTools.SynchronizeCompleted := 0;
  TDAIMCPTools.SynchronizeCallbackThreadId := 0;
  TDAIMCPTools.SynchronizeCallback :=
    procedure
    begin
      LReentrantStartRejected := not Server.Start(LPort + 1, LToken);
      LReentrantStartError := Server.LastError;
    end;
  LOther := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3, nil, InstanceName);
  LRequestThread := TThread.CreateAnonymousThread(
    procedure
    var
      LClient: THTTPClient;
      LBody: TStringStream;
      LHeaders: TNetHeaders;
      LResponse: IHTTPResponse;
    begin
      try
        LClient := THTTPClient.Create;
        LBody := TStringStream.Create('{"jsonrpc":"2.0","id":"sync-stop","method":"tools/call","params":' +
          '{"name":"sync-stop","arguments":{},' + CModernMeta + '}}', TEncoding.UTF8);
        try
          LClient.ConnectionTimeout := 2000;
          LClient.ResponseTimeout := 5000;
          LHeaders := [TNameValuePair.Create('Authorization', 'Bearer ' + LToken),
            TNameValuePair.Create('Content-Type', 'application/json'), TNameValuePair.Create('MCP-Protocol-Version', '2026-07-28'),
            TNameValuePair.Create('Mcp-Method', 'tools/call'), TNameValuePair.Create('Mcp-Name', 'sync-stop')];
          try
            LResponse := LClient.Post('http://127.0.0.1:' + IntToStr(LPort) + '/mcp', LBody, nil, LHeaders);
          except
            // Deactivation may close the HTTP connection before the synchronized tool sends its response.
          end;
        finally
          LResponse := nil;
          LBody.Free;
          LClient.Free;
        end;
      finally
        LRequestFinished.SetEvent;
      end;
    end);
  LRequestThread.FreeOnTerminate := False;
  LWatchdog := TThread.CreateAnonymousThread(
    procedure
    begin
      if LTestFinished.WaitFor(10000) <> wrSignaled then
      begin
        Writeln('FAIL: synchronized HTTP shutdown exceeded the isolated 10-second watchdog');
        Flush(Output);
        ExitProcess(1);
      end;
    end);
  LWatchdog.FreeOnTerminate := False;
  try
    LWatchdog.Start;
    LRequestThread.Start;
    Check(TDAIMCPTools.SynchronizeEntered.WaitFor(5000) = wrSignaled, 'HTTP worker reaches main-thread synchronization before shutdown');
    Check(Server.Stop and not Server.Active and (Server.Port = 0), 'main-thread shutdown completes with synchronized HTTP worker');
    Check(TDAIMCPTools.SynchronizeCompleted = 1, 'shutdown executes pending synchronized tool before returning');
    Check(TDAIMCPTools.SynchronizeCallbackThreadId = LMainThreadId, 'shutdown executes synchronized tool on owning main thread');
    Check(LReentrantStartRejected and (LReentrantStartError <> ''), 'synchronized callback cannot restart listener during shutdown');
    Check(LRequestFinished.WaitFor(5000) = wrSignaled, 'synchronized request client finishes within bounded wait');
    LRequestThread.WaitFor;
    Check(StartOnFreePort(LOther, LPort + 80, LToken) > 0, 'synchronized shutdown releases instance lease after worker joins');
  finally
    LRequestThread.WaitFor;
    LTestFinished.SetEvent;
    LWatchdog.WaitFor;
    LRequestThread.Free;
    LWatchdog.Free;
    LOther.Free;
    TDAIMCPTools.SynchronizeCallback := nil;
    FreeAndNil(TDAIMCPTools.SynchronizeEntered);
    LRequestFinished.Free;
    LTestFinished.Free;
  end;
end;

begin
  CreateGUID(InstanceGuid);
  InstanceName := 'Local\DAI.ProtocolTests.' + GUIDToString(InstanceGuid);
  Client := THTTPClient.Create;
  ClockTick := 0;
  Server := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3,
    function: UInt64
    begin
      Result := ClockTick;
    end, InstanceName);
  try
    try
      TDAISettings.Instance.Port := 18751;
      while not Server.Start do
      begin
        Inc(TDAISettings.Instance.Port);
        if TDAISettings.Instance.Port > 18761 then
          raise Exception.Create(Server.LastError);
      end;
      RunChecks;
      RunInstanceChecks;
      RunExplicitSettingsChecks;
      RunSynchronizedShutdownChecks;
      Writeln('PASS: ', CheckCount, ' isolated native MCP HTTP checks');
    except
      on E: Exception do
      begin
        Writeln(E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Response := nil;
    Client.Free;
    Server.Free;
  end;
end.
