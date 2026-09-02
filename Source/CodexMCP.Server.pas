unit CodexMCP.Server;

interface

uses
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer;

type
  TCodexMCPServer = class sealed
  strict private
    FHTTPServer: TIdHTTPServer;
    FLastError: string;
    FPort: Integer;
    FToken: string;
    function GetActive: Boolean;
    function IsAuthorized(const ARequestInfo: TIdHTTPRequestInfo): Boolean;
    function IsOriginAllowed(const ARequestInfo: TIdHTTPRequestInfo): Boolean;
    function IsProtocolVersionAllowed(
      const ARequestInfo: TIdHTTPRequestInfo
    ): Boolean;
    function ReadRequestBody(const ARequestInfo: TIdHTTPRequestInfo): string;
    procedure Command(
      AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo
    );
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const APort: Integer; const AToken: string);
    procedure Stop;
    property Active: Boolean read GetActive;
    property Port: Integer read FPort;
    property LastError: string read FLastError;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  IdSocketHandle,
  CodexMCP.Constants,
  CodexMCP.Protocol;

function JsonServerError(const AMessage: string): string;
var
  LError: TJSONObject;
  LErrorData: TJSONObject;
begin
  LError := TJSONObject.Create;
  try
    LError.AddPair('jsonrpc', '2.0');
    LError.AddPair('id', TJSONNull.Create);
    LErrorData := TJSONObject.Create;
    LErrorData.AddPair('code', TJSONNumber.Create(-32603));
    LErrorData.AddPair('message', 'Internal error');
    LErrorData.AddPair('data', AMessage);
    LError.AddPair('error', LErrorData);
    Result := LError.ToJSON;
  finally
    LError.Free;
  end;
end;

function IsLoopbackOriginValue(const AOrigin: string): Boolean;

  function MatchesAuthority(const APrefix: string): Boolean;
  var
    LIndex: Integer;
    LRemainder: string;
  begin
    Result := False;
    if not StartsText(APrefix, AOrigin) then
      Exit;
    LRemainder := Copy(AOrigin, Length(APrefix) + 1, MaxInt);
    if LRemainder = '' then
      Exit(True);
    if (LRemainder[1] <> ':') or (Length(LRemainder) = 1) then
      Exit(False);
    for LIndex := 2 to Length(LRemainder) do
      if not CharInSet(LRemainder[LIndex], ['0'..'9']) then
        Exit(False);
    Result := True;
  end;

begin
  Result := MatchesAuthority('http://127.0.0.1') or
    MatchesAuthority('https://127.0.0.1') or
    MatchesAuthority('http://localhost') or
    MatchesAuthority('https://localhost') or
    MatchesAuthority('http://[::1]') or
    MatchesAuthority('https://[::1]');
end;

{ TCodexMCPServer }

constructor TCodexMCPServer.Create;
begin
  inherited Create;
  FHTTPServer := TIdHTTPServer.Create(nil);
  FHTTPServer.KeepAlive := True;
  FHTTPServer.ParseParams := False;
  FHTTPServer.OnCommandGet := Command;
  FHTTPServer.OnCommandOther := Command;
  FLastError := '';
  FPort := 0;
  FToken := '';
end;

destructor TCodexMCPServer.Destroy;
begin
  Stop;
  FHTTPServer.Free;
  inherited;
end;

procedure TCodexMCPServer.Command(
  AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo
);
var
  LHasResponse: Boolean;
  LHttpStatus: Integer;
  LRequestBody: string;
  LResponseBody: string;
begin
  AResponseInfo.CacheControl := 'no-store';

  if not SameText(ARequestInfo.Document, CCodexMCPPath) then
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentType := 'text/plain; charset=utf-8';
    AResponseInfo.ContentText := 'Not Found';
    Exit;
  end;

  if not IsOriginAllowed(ARequestInfo) then
  begin
    AResponseInfo.ResponseNo := 403;
    AResponseInfo.ContentType := 'text/plain; charset=utf-8';
    AResponseInfo.ContentText := 'Forbidden Origin';
    Exit;
  end;

  if SameText(ARequestInfo.Command, 'OPTIONS') then
  begin
    AResponseInfo.ResponseNo := 204;
    AResponseInfo.CustomHeaders.Values['Allow'] := 'POST, OPTIONS';
    Exit;
  end;

  if not SameText(ARequestInfo.Command, 'POST') then
  begin
    AResponseInfo.ResponseNo := 405;
    AResponseInfo.CustomHeaders.Values['Allow'] := 'POST, OPTIONS';
    AResponseInfo.ContentType := 'text/plain; charset=utf-8';
    AResponseInfo.ContentText := 'Method Not Allowed';
    Exit;
  end;

  if not IsProtocolVersionAllowed(ARequestInfo) then
  begin
    AResponseInfo.ResponseNo := 400;
    AResponseInfo.ContentType := 'text/plain; charset=utf-8';
    AResponseInfo.ContentText := 'Unsupported MCP-Protocol-Version';
    Exit;
  end;

  if not IsAuthorized(ARequestInfo) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.CustomHeaders.Values['WWW-Authenticate'] := 'Bearer';
    AResponseInfo.ContentType := 'text/plain; charset=utf-8';
    AResponseInfo.ContentText := 'Unauthorized';
    Exit;
  end;

  try
    LRequestBody := ReadRequestBody(ARequestInfo);
    LHasResponse := TCodexMCPProtocol.HandleRequest(
      LRequestBody,
      LResponseBody,
      LHttpStatus
    );
    AResponseInfo.ResponseNo := LHttpStatus;
    if LHasResponse then
    begin
      AResponseInfo.ContentType := 'application/json; charset=utf-8';
      AResponseInfo.CharSet := 'utf-8';
      AResponseInfo.ContentText := LResponseBody;
    end
    else
      AResponseInfo.ContentText := '';
  except
    on E: Exception do
    begin
      FLastError := E.ClassName + ': ' + E.Message;
      AResponseInfo.ResponseNo := 500;
      AResponseInfo.ContentType := 'application/json; charset=utf-8';
      AResponseInfo.CharSet := 'utf-8';
      AResponseInfo.ContentText := JsonServerError(E.Message);
    end;
  end;
end;

function TCodexMCPServer.GetActive: Boolean;
begin
  Result := Assigned(FHTTPServer) and FHTTPServer.Active;
end;

function TCodexMCPServer.IsAuthorized(
  const ARequestInfo: TIdHTTPRequestInfo
): Boolean;
var
  LAuthorization: string;
begin
  LAuthorization := Trim(
    ARequestInfo.RawHeaders.Values['Authorization']
  );
  Result := (FToken <> '') and
    StartsText('Bearer ', LAuthorization) and
    SameStr(Copy(LAuthorization, 8, MaxInt), FToken);
end;

function TCodexMCPServer.IsOriginAllowed(
  const ARequestInfo: TIdHTTPRequestInfo
): Boolean;
var
  LOrigin: string;
begin
  LOrigin := Trim(ARequestInfo.RawHeaders.Values['Origin']);
  if LOrigin = '' then
    Exit(True);
  Result := IsLoopbackOriginValue(LOrigin);
end;

function TCodexMCPServer.IsProtocolVersionAllowed(
  const ARequestInfo: TIdHTTPRequestInfo
): Boolean;
var
  LVersion: string;
begin
  LVersion := Trim(
    ARequestInfo.RawHeaders.Values['MCP-Protocol-Version']
  );
  Result := (LVersion = '') or
    SameText(LVersion, '2025-03-26') or
    SameText(LVersion, '2025-06-18') or
    SameText(LVersion, '2025-11-25');
end;

function TCodexMCPServer.ReadRequestBody(
  const ARequestInfo: TIdHTTPRequestInfo
): string;
var
  LBytes: TBytes;
  LStream: TStream;
begin
  Result := '';
  LStream := ARequestInfo.PostStream;
  if Assigned(LStream) then
  begin
    if LStream.Position <> 0 then
      LStream.Position := 0;
    if LStream.Size > 32 * 1024 * 1024 then
      raise ERangeError.Create('Der MCP-Request ist größer als 32 MiB.');
    SetLength(LBytes, NativeInt(LStream.Size));
    if Length(LBytes) > 0 then
      LStream.ReadBuffer(LBytes[0], Length(LBytes));
    Result := TEncoding.UTF8.GetString(LBytes);
  end
  else
    Result := ARequestInfo.UnparsedParams;
end;

procedure TCodexMCPServer.Start(
  const APort: Integer;
  const AToken: string
);
var
  LBinding: TIdSocketHandle;
begin
  Stop;
  if not InRange(APort, 1, 65535) then
    raise EArgumentOutOfRangeException.Create(
      'Der MCP-Port muss zwischen 1 und 65535 liegen.'
    );
  if Trim(AToken) = '' then
    raise EArgumentException.Create(
      'Für den MCP-Server ist ein Bearer-Token erforderlich.'
    );
  FLastError := '';
  FPort := APort;
  FToken := AToken;
  try
    FHTTPServer.DefaultPort := APort;
    FHTTPServer.Bindings.Clear;
    LBinding := FHTTPServer.Bindings.Add;
    LBinding.IP := '127.0.0.1';
    LBinding.Port := APort;
    FHTTPServer.Active := True;
  except
    on E: Exception do
    begin
      FLastError := E.ClassName + ': ' + E.Message;
      Stop;
      raise;
    end;
  end;
end;

procedure TCodexMCPServer.Stop;
begin
  if Assigned(FHTTPServer) and FHTTPServer.Active then
    FHTTPServer.Active := False;
  if Assigned(FHTTPServer) then
    FHTTPServer.Bindings.Clear;
  FPort := 0;
  FToken := '';
end;

end.
