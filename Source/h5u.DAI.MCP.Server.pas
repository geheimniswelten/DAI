unit h5u.DAI.MCP.Server;

interface

uses
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer;

type
  TDAIMCPServer = class sealed
  private
    FHTTPServer: TIdHTTPServer;
    FLastError: string;
    procedure HandleCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure ResetAfterFailedStart;
  public
    constructor Create;
    destructor Destroy; override;
    function Start: Boolean;
    function Stop: Boolean;
    function ApplySettings: Boolean;
    function Active: Boolean;
    property LastError: string read FLastError;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  IdException,
  IdSocketHandle,
  h5u.DAI.Consts,
  h5u.DAI.Log,
  h5u.DAI.MCP.Protocol,
  h5u.DAI.Settings,
  h5u.DAI.WinAPI.TCP;

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
var
  LOrigin: string;
begin
  LOrigin := LowerCase(Trim(AOrigin));
  Result := (LOrigin = '') or LOrigin.StartsWith('http://127.0.0.1') or LOrigin.StartsWith('http://localhost') or
    LOrigin.StartsWith('https://127.0.0.1') or LOrigin.StartsWith('https://localhost');
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

function ErrorJson(const AMessage: string): string;
var
  LError: TJSONObject;
  LRoot: TJSONObject;
begin
  LError := TJSONObject.Create;
  LRoot := TJSONObject.Create;
  try
    LError.AddPair('code', TJSONNumber.Create(-32603));
    LError.AddPair('message', AMessage);
    LRoot.AddPair('jsonrpc', '2.0');
    LRoot.AddPair('id', TJSONNull.Create);
    LRoot.AddPair('error', LError);
    LError := nil;
    Result := LRoot.ToJSON;
  finally
    LError.Free;
    LRoot.Free;
  end;
end;

constructor TDAIMCPServer.Create;
begin
  inherited Create;
  FLastError := '';
  FHTTPServer := TIdHTTPServer.Create(nil);
  FHTTPServer.ServerSoftware := CDAIDisplayName + '/' + CDAIVersion;
  FHTTPServer.OnCommandGet := HandleCommand;
  FHTTPServer.OnCommandOther := HandleCommand;
end;

destructor TDAIMCPServer.Destroy;
begin
  Stop;
  FHTTPServer.Free;
  inherited Destroy;
end;

function TDAIMCPServer.Active: Boolean;
begin
  Result := Assigned(FHTTPServer) and FHTTPServer.Active;
end;

function TDAIMCPServer.ApplySettings: Boolean;
begin
  if not Stop then
    Exit(False);

  FLastError := '';
  if not TDAISettings.Instance.Enabled then
    Exit(True);

  Result := Start;
end;

procedure TDAIMCPServer.HandleCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LHTTPStatus: Integer;
  LHealth: TJSONObject;
  LMessage: TJSONObject;
  LOrigin: string;
  LResponseJson: TJSONObject;
  LSessionId: string;
  LText: string;
  LValue: TJSONValue;
begin
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

  if not SameText(Trim(ARequestInfo.RawHeaders.Values['Authorization']), 'Bearer ' + TDAISettings.Instance.Token) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.CustomHeaders.Values['WWW-Authenticate'] := 'Bearer realm="DAI"';
    AResponseInfo.ContentText := ErrorJson('Ungültige oder fehlende Autorisierung.');
    Exit;
  end;

  if not SameText(ARequestInfo.Command, 'POST') then
  begin
    AResponseInfo.ResponseNo := 405;
    AResponseInfo.CustomHeaders.Values['Allow'] := 'POST';
    AResponseInfo.ContentText := ErrorJson('Für den MCP-Endpunkt ist ausschließlich POST erlaubt.');
    Exit;
  end;

  LSessionId := Trim(ARequestInfo.RawHeaders.Values['Mcp-Session-Id']);
  if LSessionId = '' then
    LSessionId := NewSessionId;
  AResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := LSessionId;

  try
    LText := ReadRequestBody(ARequestInfo);
    LValue := TJSONObject.ParseJSONValue(LText);
    try
      if not (LValue is TJSONObject) then
      begin
        AResponseInfo.ResponseNo := 400;
        AResponseInfo.ContentText := ErrorJson('Der Request-Body muss ein JSON-Objekt sein.');
        Exit;
      end;

      LMessage := TJSONObject(LValue);
      LResponseJson := TDAIMCPProtocol.HandleMessage(LMessage, LSessionId, LHTTPStatus);
      try
        AResponseInfo.ResponseNo := LHTTPStatus;
        if Assigned(LResponseJson) then
          AResponseInfo.ContentText := LResponseJson.ToJSON
        else
          AResponseInfo.ContentText := '';
      finally
        LResponseJson.Free;
      end;
    finally
      LValue.Free;
    end;
  except
    on E: Exception do
    begin
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
      FHTTPServer.Active := False;
  except
  end;

  try
    if Assigned(FHTTPServer) then
      FHTTPServer.Bindings.Clear;
  except
  end;
end;

function TDAIMCPServer.Start: Boolean;
var
  LBinding: TIdSocketHandle;
  LOwnerDescription: string;
  LPort: Integer;
begin
  if Active then
  begin
    FLastError := '';
    Exit(True);
  end;

  FLastError := '';
  LPort := TDAISettings.Instance.Port;
  try
    FHTTPServer.Bindings.Clear;
    LBinding := FHTTPServer.Bindings.Add;
    LBinding.IP := CDAIDefaultBindAddress;
    LBinding.Port := LPort;
    FHTTPServer.Active := True;
    TDAILog.Access(Format('MCP-Server gestartet: http://%s:%d%s', [CDAIDefaultBindAddress, LPort, CDAIMcpPath]));
    Result := True;
  except
    on E: EIdCouldNotBindSocket do
    begin
      ResetAfterFailedStart;
      LOwnerDescription := TDAITCPListener.DescribeIPv4Owner(LPort);
      FLastError := Format(
        'Der MCP-Server konnte nicht an %s:%d gebunden werden. Der Port ist bereits belegt. %s ' +
        'Das DAI-Package bleibt geladen; wählen Sie in den DAI-Einstellungen einen freien Port. Indy: %s',
        [CDAIDefaultBindAddress, LPort, LOwnerDescription, E.Message]
      );
      TDAILog.Error(FLastError);
      Result := False;
    end;
    on E: Exception do
    begin
      ResetAfterFailedStart;
      FLastError := Format('Der MCP-Server konnte auf %s:%d nicht gestartet werden: %s: %s', [CDAIDefaultBindAddress, LPort, E.ClassName, E.Message]);
      TDAILog.Error(FLastError);
      Result := False;
    end;
  end;
end;

function TDAIMCPServer.Stop: Boolean;
begin
  if not Assigned(FHTTPServer) or not FHTTPServer.Active then
    Exit(True);

  try
    FHTTPServer.Active := False;
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
