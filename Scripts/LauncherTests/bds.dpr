program bds;

{$APPTYPE GUI}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer,
  Vcl.Forms,
  Winapi.Messages,
  Winapi.Windows;

type
  TAppBuilder = class(TForm)
  private
    FMode: string;
    FServer: TIdHTTPServer;
    procedure QueryClose(Sender: TObject; var CanClose: Boolean);
    procedure WriteMarker(const AName: string);
    procedure HandleCommand(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure ParseAuthentication(AContext: TIdContext;
      const AAuthType, AAuthData: string;
      var VUsername, VPassword: string; var VHandled: Boolean);
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  Fixture: TAppBuilder;

procedure TAppBuilder.WriteMarker(const AName: string);
var
  LDirectory: string;
begin
  LDirectory := GetEnvironmentVariable('DAI_LAUNCHER_FIXTURE_MARKER_DIR');
  if LDirectory = '' then
    Exit;
  TDirectory.CreateDirectory(LDirectory);
  TFile.WriteAllText(TPath.Combine(LDirectory,
    AName + '-' + IntToStr(GetCurrentProcessId) + '.txt'),
    ParamStr(0) + sLineBreak + FMode, TEncoding.UTF8);
end;

constructor TAppBuilder.Create(AOwner: TComponent);
var
  LPort: Integer;
begin
  inherited CreateNew(AOwner);
  Name := 'DAILauncherFixture';
  Caption := 'DAI isolated launcher fixture';
  FMode := GetEnvironmentVariable('DAI_LAUNCHER_FIXTURE_MODE');
  OnCloseQuery := QueryClose;
  HandleNeeded;
  if SameText(FMode, 'early-exit') then
    SetTimer(Handle, 1, 750, nil);
  if TryStrToInt(GetEnvironmentVariable('DAI_LAUNCHER_FIXTURE_PORT'), LPort) then
  begin
    FServer := TIdHTTPServer.Create(nil);
    FServer.Bindings.Add.IP := '127.0.0.1';
    FServer.Bindings[0].Port := LPort;
    FServer.OnCommandGet := HandleCommand;
    FServer.OnCommandOther := HandleCommand;
    FServer.OnParseAuthentication := ParseAuthentication;
    FServer.Active := True;
  end;
  WriteMarker('ready');
end;

destructor TAppBuilder.Destroy;
begin
  FServer.Free;
  inherited;
end;

procedure TAppBuilder.ParseAuthentication(AContext: TIdContext;
  const AAuthType, AAuthData: string;
  var VUsername, VPassword: string; var VHandled: Boolean);
begin
  if SameText(AAuthType, 'Bearer') then
  begin
    VUsername := '';
    VPassword := AAuthData;
    VHandled := True;
  end;
end;

procedure TAppBuilder.HandleCommand(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LBody: TStringStream;
  LRequest: TJSONValue;
  LResponse: TJSONObject;
  LResult, LMeta, LInfo, LCapabilities, LTools, LError: TJSONObject;
  LVersions: TJSONArray;
  LId: TJSONValue;
begin
  AResponseInfo.ContentType := 'application/json';
  AResponseInfo.CharSet := 'utf-8';
  if ARequestInfo.RawHeaders.Values['Authorization'] <>
     'Bearer ' + GetEnvironmentVariable('DAI_LAUNCHER_FIXTURE_TOKEN') then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.ContentText := '{}';
    Exit;
  end;
  if (ARequestInfo.Command = 'DELETE') and (ARequestInfo.Document = '/mcp') then
  begin
    WriteMarker('legacy-delete');
    AResponseInfo.ResponseNo := 204;
    AResponseInfo.ContentLength := 0;
    Exit;
  end;
  if (ARequestInfo.Command <> 'POST') or (ARequestInfo.Document <> '/mcp') then
  begin
    AResponseInfo.ResponseNo := 405;
    AResponseInfo.ContentText := '{}';
    Exit;
  end;
  LBody := TStringStream.Create('', TEncoding.UTF8);
  try
    ARequestInfo.PostStream.Position := 0;
    LBody.CopyFrom(ARequestInfo.PostStream, 0);
    LRequest := TJSONObject.ParseJSONValue(LBody.DataString);
  finally
    LBody.Free;
  end;
  try
    if not (LRequest is TJSONObject) then
    begin
      AResponseInfo.ResponseNo := 400;
      AResponseInfo.ContentText := '{}';
      Exit;
    end;
    WriteMarker('discovery');
    LId := TJSONObject(LRequest).GetValue('id');
    LResponse := TJSONObject.Create;
    try
      LResponse.AddPair('jsonrpc', '2.0');
      if Assigned(LId) then
        LResponse.AddPair('id', LId.Clone as TJSONValue);
      if SameText(FMode, 'legacy') then
      begin
        if TJSONObject(LRequest).GetValue<string>('method', '') <> 'initialize' then
        begin
          LError := TJSONObject.Create;
          LError.AddPair('code', TJSONNumber.Create(-32601));
          LError.AddPair('message', 'Fixture only supports classical initialize.');
          LResponse.AddPair('error', LError);
        end
        else
        begin
          WriteMarker('legacy-initialize');
          LInfo := TJSONObject.Create;
          LInfo.AddPair('name', 'DAI');
          LInfo.AddPair('version', GetEnvironmentVariable('DAI_LAUNCHER_FIXTURE_VERSION'));
          LResult := TJSONObject.Create;
          LResult.AddPair('protocolVersion', '2025-06-18');
          LResult.AddPair('serverInfo', LInfo);
          LResult.AddPair('capabilities', TJSONObject.Create);
          LResponse.AddPair('result', LResult);
          AResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := 'launcher-fixture-session';
        end;
        AResponseInfo.ContentText := LResponse.ToJSON;
        Exit;
      end;
      LInfo := TJSONObject.Create;
      LInfo.AddPair('name', 'DAI');
      LInfo.AddPair('version', GetEnvironmentVariable('DAI_LAUNCHER_FIXTURE_VERSION'));
      LMeta := TJSONObject.Create;
      LMeta.AddPair('io.modelcontextprotocol/serverInfo', LInfo);
      LMeta.AddPair('io.modelcontextprotocol/protocolVersion', '2026-07-28');
      LTools := TJSONObject.Create;
      LTools.AddPair('listChanged', TJSONBool.Create(False));
      LCapabilities := TJSONObject.Create;
      LCapabilities.AddPair('tools', LTools);
      LVersions := TJSONArray.Create;
      LVersions.Add('2026-07-28');
      LVersions.Add('2025-11-25');
      LVersions.Add('2025-06-18');
      LResult := TJSONObject.Create;
      LResult.AddPair('resultType', 'complete');
      LResult.AddPair('_meta', LMeta);
      LResult.AddPair('capabilities', LCapabilities);
      LResult.AddPair('supportedVersions', LVersions);
      LResponse.AddPair('result', LResult);
      AResponseInfo.ContentText := LResponse.ToJSON;
    finally
      LResponse.Free;
    end;
  finally
    LRequest.Free;
  end;
end;

procedure TAppBuilder.QueryClose(Sender: TObject; var CanClose: Boolean);
begin
  WriteMarker('close-query');
  CanClose := not SameText(FMode, 'cancel');
end;

procedure TAppBuilder.WndProc(var Message: TMessage);
begin
  if (Message.Msg = WM_TIMER) and (Message.WParam = 1) and SameText(FMode, 'early-exit') then
  begin
    KillTimer(Handle, 1);
    Application.Terminate;
    Exit;
  end;
  if Message.Msg = WM_CLOSE then
  begin
    WriteMarker('wm-close');
    if SameText(FMode, 'hang') then
      Sleep(INFINITE);
  end;
  inherited;
end;

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := False;
  Application.ShowMainForm := False;
  Application.CreateForm(TAppBuilder, Fixture);
  Application.Run;
end.
