program TestProtocol;

{$APPTYPE CONSOLE}

// Compile with the isolated test stubs first on the unit search path.
// The real MCP.Server/MCP.Protocol units are exercised against loopback HTTP.

uses
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SysUtils,
  h5u.DAI.MCP.Server,
  h5u.DAI.MCP.Tools,
  h5u.DAI.Settings;

const
  CModernMeta = '"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' +
    '"io.modelcontextprotocol/clientCapabilities":{}}';

var
  Client: THTTPClient;
  Server: TDAIMCPServer;
  CheckCount: Integer;
  SessionId: string;
  Response: IHTTPResponse;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function Post(const ABody: string; const ASession: string = ''; const AVersion: string = ''; const AMethod: string = '';
  const AName: string = ''; const AOrigin: string = ''; const AAuthenticate: Boolean = True): IHTTPResponse;
var
  Body: TStringStream;
  Headers: TNetHeaders;
  Count: Integer;

  procedure AddHeader(const AKey, AValue: string);
  begin
    SetLength(Headers, Count + 1);
    Headers[Count] := TNameValuePair.Create(AKey, AValue);
    Inc(Count);
  end;

begin
  Count := 0;
  if AAuthenticate then
    AddHeader('Authorization', 'Bearer isolated-test-token');
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
    Result := Client.Post('http://127.0.0.1:' + IntToStr(TDAISettings.Instance.Port) + '/mcp', Body, nil, Headers);
  finally
    Body.Free;
  end;
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
end;

begin
  Client := THTTPClient.Create;
  Server := TDAIMCPServer.Create;
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
