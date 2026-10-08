unit h5u.DAI.MCP.Protocol;

interface

uses
  System.JSON;

type
  TDAIMCPProtocol = class sealed
  public
    class function HandleMessage(const AMessage: TJSONObject; const ATransportSessionId: string; out AHTTPStatus: Integer; const AClientName: string = ''): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  h5u.DAI.Consts,
  h5u.DAI.MCP.Tools,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Types;

function CloneJsonValue(const AValue: TJSONValue): TJSONValue;
begin
  if not Assigned(AValue) then
    Exit(TJSONNull.Create);
  Result := TJSONObject.ParseJSONValue(AValue.ToJSON);
end;

function JsonRpcResponse(const AId: TJSONValue; const AResult: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', CloneJsonValue(AId));
  Result.AddPair('result', AResult);
end;

function JsonRpcError(const AId: TJSONValue; const ACode: Integer; const AMessage: string; const AData: string = ''): TJSONObject;
var
  LError: TJSONObject;
begin
  LError := TJSONObject.Create;
  LError.AddPair('code', TJSONNumber.Create(ACode));
  LError.AddPair('message', AMessage);
  if AData <> '' then
    LError.AddPair('data', AData);

  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', CloneJsonValue(AId));
  Result.AddPair('error', LError);
end;

function BuildServerMeta: TJSONObject;
var
  LServerInfo: TJSONObject;
begin
  LServerInfo := TJSONObject.Create;
  LServerInfo.AddPair('name', CDAIName);
  LServerInfo.AddPair('version', CDAIVersion);

  Result := TJSONObject.Create;
  Result.AddPair('io.modelcontextprotocol/serverInfo', LServerInfo);
end;

function BuildTextContent(const AText: string): TJSONArray;
var
  LTextItem: TJSONObject;
begin
  LTextItem := TJSONObject.Create;
  LTextItem.AddPair('type', 'text');
  LTextItem.AddPair('text', AText);

  Result := TJSONArray.Create;
  Result.AddElement(LTextItem);
end;

function BuildToolResult(const AResult: TJSONObject; const AModern: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AModern then
  begin
    Result.AddPair('resultType', 'complete');
    Result.AddPair('_meta', BuildServerMeta);
  end;
  Result.AddPair('content', BuildTextContent(AResult.ToJSON));
  Result.AddPair('structuredContent', CloneJsonValue(AResult));
  Result.AddPair('isError', TJSONBool.Create(False));
end;

function BuildToolErrorResult(const AMessage: string; const AModern: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AModern then
  begin
    Result.AddPair('resultType', 'complete');
    Result.AddPair('_meta', BuildServerMeta);
  end;
  Result.AddPair('content', BuildTextContent(AMessage));
  Result.AddPair('isError', TJSONBool.Create(True));
end;

function IsModernRequest(const AMessage: TJSONObject): Boolean;
var
  LMeta: TJSONObject;
  LParams: TJSONObject;
begin
  Result := False;
  LParams := AMessage.GetValue<TJSONObject>('params', nil);
  if not Assigned(LParams) then
    Exit;
  LMeta := LParams.GetValue<TJSONObject>('_meta', nil);
  if Assigned(LMeta) then
    Result := (LMeta.GetValue('io.modelcontextprotocol/protocolVersion') is TJSONString) and
      (LMeta.GetValue('io.modelcontextprotocol/protocolVersion').Value = '2026-07-28');
end;

function ExtractRequestContext(const AParams: TJSONObject; const AArguments: TJSONObject; const ATransportSessionId: string; const AClientName: string): TDAIRequestContext;
var
  LClientInfo: TJSONObject;
  LMeta: TJSONObject;
begin
  Result := Default(TDAIRequestContext);
  Result.TransportSessionId := ATransportSessionId;
  Result.ProjectKey := TDAIOTA.ActiveProjectFileName;
  Result.ClientName := AClientName;

  LMeta := nil;
  if Assigned(AParams) then
    LMeta := AParams.GetValue<TJSONObject>('_meta', nil);
  if not Assigned(LMeta) and Assigned(AArguments) then
    LMeta := AArguments.GetValue<TJSONObject>('_meta', nil);

  if Assigned(LMeta) then
  begin
    Result.ThreadId := Trim(LMeta.GetValue<string>('threadId', ''));
    // The wildcard is reserved for IDE options and is never a remote chat identity.
    if Result.ThreadId = '*' then
      Result.ThreadId := '';
    if Result.ClientName = '' then
    begin
      LClientInfo := LMeta.GetValue<TJSONObject>('io.modelcontextprotocol/clientInfo', nil);
      if Assigned(LClientInfo) then
        Result.ClientName := LClientInfo.GetValue<string>('name', '');
      if Result.ClientName = '' then
        Result.ClientName := LMeta.GetValue<string>('clientName', '');
    end;
  end;

  if Result.ClientName = '' then
    Result.ClientName := 'KI-Client';
end;

function BuildServerInstructions: string;
begin
  Result :=
    'DAI (Delphi AI) steuert die aktuell geöffnete Delphi-IDE. Bei Anfragen zu Delphi oder zur Delphi-IDE die DAI-Werkzeuge berücksichtigen. ' +
    'Vor Dateiänderungen, besonders an PAS, DFM, FMX, DPR, DPK und DPROJ, mit ide_status und open_files_list den IDE-/Editorzustand prüfen; ' +
    'bei Bedarf projects_list verwenden und bei mehreren erreichbaren IDEs diejenige mit den betroffenen Dateien wählen. ' +
    'Geöffnete Dateien möglichst über DAI bearbeiten; ungespeicherte IDE-Puffer sind maßgeblich. ' +
    'Vor Textänderungen den vollständigen aktuellen Inhalt mit file_read (interfaces_only: false, maximum_characters: 0) lesen. ' +
    'Nur vollständigen Inhalt mit file_write und expected_sha256 zurückschreiben; danach Inhalt und Speicherstatus prüfen. ' +
    'Hashkonflikte durch erneutes Lesen und Abgleichen lösen. ' +
    'Vorhandene Benutzeränderungen nicht ungefragt speichern, verwerfen oder mit einer älteren Datenträgerdatei überschreiben. ' +
    'DFM/FMX bevorzugt über die Designerwerkzeuge ändern; Textänderungen nur im IDE-Textpuffer. DPROJ-Optionen über die Projektwerkzeuge ändern. ' +
    'form_show_as_text schaltet normalerweise den vorhandenen PAS-Editor-Tab auf DFM-/FMX-Text um; standardmäßig sind das keine getrennten Tabs. ' +
    'Danach die gewünschte Formulartextdatei über den vollständigen Pfad erneut mit file_read lesen und den tatsächlichen Puffer prüfen. ' +
    'Nicht annehmen, dass der bisher aktive Tab weiterhin PAS-Text enthält. Bei ungespeicherten PAS-Änderungen die Umschaltgrenzen beachten. ' +
    'Direkte Dateibearbeitung ist ein Ausweichweg bei unerreichbarem DAI, geschlossener Datei oder fehlender passender Operation; ' +
    'die Einschränkung kurz nennen und bekannte offene/ungespeicherte Inhalte schützen. Unbekannten Editorzustand nicht als geschlossen ausgeben. ' +
    'Die IDE allein für diese Prüfung nicht ungefragt starten. Berechtigungen werden in der IDE nach Projekt und KI-Chat bzw. MCP-Sitzung abgefragt.';
end;

function BuildInitializationResult(const ARequestedVersion: string): TJSONObject;
var
  LCapabilities: TJSONObject;
  LProtocolVersion: string;
  LServerInfo: TJSONObject;
  LTools: TJSONObject;
begin
  if SameText(ARequestedVersion, '2025-06-18') then
    LProtocolVersion := '2025-06-18'
  else
    LProtocolVersion := '2025-11-25';

  LTools := TJSONObject.Create;
  LTools.AddPair('listChanged', TJSONBool.Create(False));
  LCapabilities := TJSONObject.Create;
  LCapabilities.AddPair('tools', LTools);
  LServerInfo := TJSONObject.Create;
  LServerInfo.AddPair('name', CDAIName);
  LServerInfo.AddPair('version', CDAIVersion);

  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', LProtocolVersion);
  Result.AddPair('capabilities', LCapabilities);
  Result.AddPair('serverInfo', LServerInfo);
  Result.AddPair('instructions', BuildServerInstructions);
end;

function BuildDiscoveryResult: TJSONObject;
var
  LCapabilities: TJSONObject;
  LTools: TJSONObject;
  LVersions: TJSONArray;
begin
  LTools := TJSONObject.Create;
  LTools.AddPair('listChanged', TJSONBool.Create(False));
  LCapabilities := TJSONObject.Create;
  LCapabilities.AddPair('tools', LTools);

  LVersions := TJSONArray.Create;
  LVersions.Add('2026-07-28');
  LVersions.Add('2025-11-25');
  LVersions.Add('2025-06-18');

  Result := TJSONObject.Create;
  Result.AddPair('resultType', 'complete');
  Result.AddPair('_meta', BuildServerMeta);
  Result.AddPair('supportedVersions', LVersions);
  Result.AddPair('capabilities', LCapabilities);
  Result.AddPair('instructions', BuildServerInstructions);
end;

class function TDAIMCPProtocol.HandleMessage(const AMessage: TJSONObject; const ATransportSessionId: string; out AHTTPStatus: Integer; const AClientName: string): TJSONObject;
var
  LArguments: TJSONObject;
  LContext: TDAIRequestContext;
  LCreatedArguments: Boolean;
  LCreatedParams: Boolean;
  LId: TJSONValue;
  LNumericId: Int64;
  LMethod: string;
  LMeta: TJSONObject;
  LModern: Boolean;
  LName: string;
  LParams: TJSONObject;
  LResult: TJSONObject;
  LToolResult: TJSONObject;
  LValue: TJSONValue;
begin
  AHTTPStatus := 200;
  LId := AMessage.GetValue('id');
  LValue := AMessage.GetValue('method');
  if not (AMessage.GetValue('jsonrpc') is TJSONString) or not (LValue is TJSONString) then
  begin
    AHTTPStatus := 400;
    Exit(JsonRpcError(nil, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  end;
  LMethod := AMessage.GetValue<string>('method', '');
  LValue := AMessage.GetValue('params');
  if Assigned(LValue) and not (LValue is TJSONObject) then
  begin
    AHTTPStatus := 400;
    Exit(JsonRpcError(LId, -32602, 'params muss ein Objekt sein.'));
  end;
  LParams := AMessage.GetValue<TJSONObject>('params', nil);

  if (AMessage.GetValue<string>('jsonrpc', '') <> '2.0') or (LMethod = '') or
     (Assigned(LId) and not ((LId is TJSONString) or (LId is TJSONNumber))) or
     ((LId is TJSONNumber) and not TryStrToInt64(LId.Value, LNumericId)) then
  begin
    AHTTPStatus := 400;
    Exit(JsonRpcError(LId, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  end;

  // Notifications must never execute an RPC or return a JSON-RPC response.
  if not Assigned(LId) then
  begin
    AHTTPStatus := 202;
    Exit(nil);
  end;
  LMeta := nil;
  if Assigned(LParams) then
  begin
    LValue := LParams.GetValue('_meta');
    if Assigned(LValue) and not (LValue is TJSONObject) then
    begin
      AHTTPStatus := 400;
      Exit(JsonRpcError(LId, -32602, '_meta muss ein Objekt sein.'));
    end;
    LMeta := LParams.GetValue<TJSONObject>('_meta', nil);
  end;
  LModern := IsModernRequest(AMessage);
  if LModern then
  begin
    if not (LMeta.GetValue('io.modelcontextprotocol/clientCapabilities') is TJSONObject) then
    begin
      AHTTPStatus := 400;
      Exit(JsonRpcError(LId, -32602, 'Moderne MCP-Anfragen benötigen clientCapabilities in _meta.'));
    end;
  end;

  if (LMethod = 'initialize') then
  begin
    if LModern then
    begin
      AHTTPStatus := 404;
      Exit(JsonRpcError(LId, -32601, 'initialize gehört zu den MCP-Versionen vor 2026-07-28.'));
    end;
    LCreatedParams := not Assigned(LParams);
    if LCreatedParams then
      LParams := TJSONObject.Create;
    try
      if Assigned(LParams.GetValue('protocolVersion')) and not (LParams.GetValue('protocolVersion') is TJSONString) then
      begin
        AHTTPStatus := 400;
        Exit(JsonRpcError(LId, -32602, 'protocolVersion muss ein String sein.'));
      end;
      Exit(JsonRpcResponse(LId, BuildInitializationResult(LParams.GetValue<string>('protocolVersion', '2025-06-18'))));
    finally
      if LCreatedParams then
        LParams.Free;
    end;
  end;

  if (LMethod = 'server/discover') then
    Exit(JsonRpcResponse(LId, BuildDiscoveryResult));

  if (LMethod = 'ping') then
  begin
    LResult := TJSONObject.Create;
    if LModern then
    begin
      LResult.AddPair('resultType', 'complete');
      LResult.AddPair('_meta', BuildServerMeta);
    end;
    Exit(JsonRpcResponse(LId, LResult));
  end;

  if (LMethod = 'tools/list') then
  begin
    LResult := TJSONObject.Create;
    if LModern then
    begin
      LResult.AddPair('resultType', 'complete');
      LResult.AddPair('_meta', BuildServerMeta);
    end;
    LResult.AddPair('tools', TDAIMCPTools.ListTools);
    Exit(JsonRpcResponse(LId, LResult));
  end;

  if (LMethod = 'tools/call') then
  begin
    if not Assigned(LParams) then
      Exit(JsonRpcError(LId, -32602, 'params muss ein Objekt sein.'));

    if not (LParams.GetValue('name') is TJSONString) then
      Exit(JsonRpcError(LId, -32602, 'name muss ein nichtleerer String sein.'));
    LName := LParams.GetValue<string>('name', '');
    if LName = '' then
      Exit(JsonRpcError(LId, -32602, 'name muss ein nichtleerer String sein.'));
    LValue := LParams.GetValue('arguments');
    if Assigned(LValue) and not (LValue is TJSONObject) then
      Exit(JsonRpcError(LId, -32602, 'arguments muss ein Objekt sein.'));
    LArguments := LParams.GetValue<TJSONObject>('arguments', nil);
    LCreatedArguments := not Assigned(LArguments);
    if LCreatedArguments then
      LArguments := TJSONObject.Create;
    try
      try
        LContext := ExtractRequestContext(LParams, LArguments, ATransportSessionId, AClientName);
        LToolResult := TDAIMCPTools.CallTool(LName, LArguments, LContext);
        try
          Exit(JsonRpcResponse(LId, BuildToolResult(LToolResult, LModern)));
        finally
          LToolResult.Free;
        end;
      except
        on E: EAbort do
          Exit(JsonRpcResponse(LId, BuildToolErrorResult(E.Message, LModern)));
        on E: Exception do
          Exit(JsonRpcResponse(LId, BuildToolErrorResult(E.ClassName + ': ' + E.Message, LModern)));
      end;
    finally
      if LCreatedArguments then
        LArguments.Free;
    end;
  end;

  AHTTPStatus := 404;
  Result := JsonRpcError(LId, -32601, 'Unbekannte MCP-Methode: ' + LMethod);
end;

end.
