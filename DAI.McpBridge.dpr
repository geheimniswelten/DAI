program DAI.McpBridge;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SysUtils;

function FailureResponse(const ARequest: TJSONObject; const AMessage: string): string;
var
  LError: TJSONObject;
  LId: TJSONValue;
  LResponse: TJSONObject;
begin
  Result := '';
  LId := ARequest.GetValue('id');
  if not Assigned(LId) then
    Exit;
  LResponse := TJSONObject.Create;
  try
    LResponse.AddPair('jsonrpc', '2.0');
    LResponse.AddPair('id', LId.Clone as TJSONValue);
    LError := TJSONObject.Create;
    LError.AddPair('code', TJSONNumber.Create(-32000));
    LError.AddPair('message', AMessage);
    LResponse.AddPair('error', LError);
    Result := LResponse.ToJSON;
  finally
    LResponse.Free;
  end;
end;

function Endpoint: string;
var
  LPort: Integer;
  LPortText: string;
begin
  if (ParamCount <> 2) or (ParamStr(1) <> '--url') then
    raise EArgumentException.Create('Aufruf: DAI.McpBridge.exe --url http://127.0.0.1:<Port>/mcp');
  Result := ParamStr(2);
  if not Result.StartsWith('http://127.0.0.1:') or not Result.EndsWith('/mcp') then
    raise EArgumentException.Create('Die Brücke unterstützt ausschließlich den lokalen DAI-Endpunkt.');
  LPortText := Copy(Result, Length('http://127.0.0.1:') + 1, Length(Result) - Length('http://127.0.0.1:') - Length('/mcp'));
  if not TryStrToInt(LPortText, LPort) or (LPort < 1024) or (LPort > 65535) then
    raise EArgumentException.Create('Ungültiger DAI-Port.');
end;

procedure CloseSession(AClient: THTTPClient; const AUrl, AToken, ASession, AProtocolVersion: string);
var
  LHeaders: TNetHeaders;
begin
  if ASession = '' then
    Exit;
  try
    AClient.ConnectionTimeout := 1000;
    AClient.ResponseTimeout := 1000;
    SetLength(LHeaders, 3);
    LHeaders[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AToken);
    LHeaders[1] := TNameValuePair.Create('Mcp-Session-Id', ASession);
    LHeaders[2] := TNameValuePair.Create('MCP-Protocol-Version', AProtocolVersion);
    AClient.Delete(AUrl, nil, LHeaders);
  except
    // Closing stdin must also work when the IDE has already stopped.
  end;
end;

procedure Run;
var
  LClient: THTTPClient;
  LHeaders: TNetHeaders;
  LInput: string;
  LOutput: string;
  LParams: TJSONObject;
  LProtocolVersion: string;
  LRequest: TJSONValue;
  LResponse: IHTTPResponse;
  LResponseValue: TJSONValue;
  LSession: string;
  LStream: TStringStream;
  LToken: string;
  LUrl: string;
begin
  LUrl := Endpoint;
  LToken := GetEnvironmentVariable('DAI_MCP_TOKEN');
  if LToken.Trim = '' then
    raise EArgumentException.Create('DAI_MCP_TOKEN fehlt. Bitte den Client erneut über DAI registrieren.');
  if (Pos(#13, LToken) > 0) or (Pos(#10, LToken) > 0) then
    raise EArgumentException.Create('DAI_MCP_TOKEN enthält einen ungültigen Headerwert.');

  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 5000;
    LClient.ResponseTimeout := 180000;
    LClient.HandleRedirects := False;
    LClient.ProxySettings := TProxySettings.Create('', 0);
    LSession := '';
    LProtocolVersion := '';
    while not Eof(Input) do
    begin
      Readln(Input, LInput);
      if LInput.Trim = '' then
        Continue;
      LRequest := TJSONObject.ParseJSONValue(LInput);
      try
        if not (LRequest is TJSONObject) then
          raise EConvertError.Create('Eine JSON-RPC-Nachricht pro Zeile wird erwartet.');
        SetLength(LHeaders, 4);
        LHeaders[0] := TNameValuePair.Create('Authorization', 'Bearer ' + LToken);
        LHeaders[1] := TNameValuePair.Create('Content-Type', 'application/json');
        LHeaders[2] := TNameValuePair.Create('Accept', 'application/json, text/event-stream');
        LHeaders[3] := TNameValuePair.Create('Mcp-Method', TJSONObject(LRequest).GetValue<string>('method', ''));
        LParams := TJSONObject(LRequest).GetValue<TJSONObject>('params', nil);
        if TJSONObject(LRequest).GetValue<string>('method', '') = 'initialize' then
          if Assigned(LParams) then
            LProtocolVersion := LParams.GetValue<string>('protocolVersion', '2025-06-18');
        if Assigned(LParams) and (LParams.GetValue<string>('name', '') <> '') then
        begin
          SetLength(LHeaders, Length(LHeaders) + 1);
          LHeaders[High(LHeaders)] := TNameValuePair.Create('Mcp-Name', LParams.GetValue<string>('name', ''));
        end;
        if LProtocolVersion <> '' then
        begin
          SetLength(LHeaders, Length(LHeaders) + 1);
          LHeaders[High(LHeaders)] := TNameValuePair.Create('MCP-Protocol-Version', LProtocolVersion);
        end;
        if LSession <> '' then
        begin
          SetLength(LHeaders, Length(LHeaders) + 1);
          LHeaders[High(LHeaders)] := TNameValuePair.Create('Mcp-Session-Id', LSession);
        end;
        LOutput := '';
        LStream := TStringStream.Create(LInput, TEncoding.UTF8);
        try
          try
            LResponse := LClient.Post(LUrl, LStream, nil, LHeaders);
            if (LResponse.StatusCode < 200) or (LResponse.StatusCode >= 300) then
              LOutput := FailureResponse(TJSONObject(LRequest), Format('DAI meldet HTTP %d. IDE und Registrierung prüfen.', [LResponse.StatusCode]))
            else
            begin
              if LResponse.HeaderValue['Mcp-Session-Id'] <> '' then
                LSession := LResponse.HeaderValue['Mcp-Session-Id'];
              LOutput := LResponse.ContentAsString(TEncoding.UTF8).Trim;
              if LOutput <> '' then
              begin
                LResponseValue := TJSONObject.ParseJSONValue(LOutput);
                try
                  if not (LResponseValue is TJSONObject) then
                    raise EConvertError.Create('DAI hat keine JSON-RPC-Antwort geliefert.');
                  LOutput := LResponseValue.ToJSON;
                  if TJSONObject(LRequest).GetValue<string>('method', '') = 'initialize' then
                  begin
                    LParams := TJSONObject(LResponseValue).GetValue<TJSONObject>('result', nil);
                    if Assigned(LParams) then
                      LProtocolVersion := LParams.GetValue<string>('protocolVersion', LProtocolVersion);
                  end;
                finally
                  LResponseValue.Free;
                end;
              end;
            end;
          except
            on E: Exception do
              LOutput := FailureResponse(TJSONObject(LRequest), 'Die DAI-IDE-Verbindung ist nicht erreichbar oder hat das Zeitlimit überschritten.');
          end;
        finally
          LStream.Free;
        end;
        if LOutput <> '' then
        begin
          Writeln(Output, LOutput);
          Flush(Output);
        end;
      finally
        LRequest.Free;
      end;
    end;
  finally
    CloseSession(LClient, LUrl, LToken, LSession, LProtocolVersion);
    LClient.Free;
  end;
end;

begin
  SetTextCodePage(Input, 65001);
  SetTextCodePage(Output, 65001);
  SetTextCodePage(ErrOutput, 65001);
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.Message);
      ExitCode := 1;
    end;
  end;
end.
