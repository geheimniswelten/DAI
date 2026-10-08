unit h5u.DAI.Launcher.Protocol;

interface

uses
  System.JSON,
  h5u.DAI.Launcher;

type
  TDAILauncherProtocol = class sealed
  private
    FLauncher: TDAILauncher;
  public
    constructor Create;
    destructor Destroy; override;
    function Handle(const AMessage: TJSONValue): TJSONObject;
  end;

implementation

uses
  System.SysUtils,
  h5u.DAI.Consts;

function RPCResponse(const AId, AResult: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if Assigned(AId) then
    Result.AddPair('id', AId.Clone as TJSONValue)
  else
    Result.AddPair('id', TJSONNull.Create);
  Result.AddPair('result', AResult);
end;

function RPCError(const AId: TJSONValue; const ACode: Integer; const AMessage: string): TJSONObject;
var
  LError: TJSONObject;
begin
  LError := TJSONObject.Create;
  LError.AddPair('code', TJSONNumber.Create(ACode));
  LError.AddPair('message', AMessage);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if Assigned(AId) then
    Result.AddPair('id', AId.Clone as TJSONValue)
  else
    Result.AddPair('id', TJSONNull.Create);
  Result.AddPair('error', LError);
end;

function ServerInfo: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', 'dai_start');
  Result.AddPair('version', CDAIVersion);
end;

function Capabilities: TJSONObject;
var
  LTools: TJSONObject;
begin
  LTools := TJSONObject.Create;
  LTools.AddPair('listChanged', TJSONBool.Create(False));
  Result := TJSONObject.Create;
  Result.AddPair('tools', LTools);
end;

function CompleteResult(const AModern: Boolean): TJSONObject;
var
  LMeta: TJSONObject;
begin
  Result := TJSONObject.Create;
  if AModern then
  begin
    Result.AddPair('resultType', 'complete');
    LMeta := TJSONObject.Create;
    LMeta.AddPair('io.modelcontextprotocol/serverInfo', ServerInfo);
    Result.AddPair('_meta', LMeta);
  end;
end;

function ToolResult(const AData: TJSONObject; const AError, AModern: Boolean): TJSONObject;
var
  LContent: TJSONArray;
  LText: TJSONObject;
begin
  LText := TJSONObject.Create;
  LText.AddPair('type', 'text');
  LText.AddPair('text', AData.ToJSON);
  LContent := TJSONArray.Create;
  LContent.AddElement(LText);
  Result := CompleteResult(AModern);
  Result.AddPair('content', LContent);
  Result.AddPair('structuredContent', AData);
  Result.AddPair('isError', TJSONBool.Create(AError));
end;

procedure AddTool(const ATools: TJSONArray; const AName, ADescription, ASchema: string; const AReadOnly, ADestructive: Boolean);
var
  LAnnotations, LTool: TJSONObject;
begin
  LAnnotations := TJSONObject.Create;
  LAnnotations.AddPair('readOnlyHint', TJSONBool.Create(AReadOnly));
  LAnnotations.AddPair('destructiveHint', TJSONBool.Create(ADestructive));
  LAnnotations.AddPair('openWorldHint', TJSONBool.Create(False));
  LTool := TJSONObject.Create;
  LTool.AddPair('name', AName);
  LTool.AddPair('description', ADescription);
  LTool.AddPair('inputSchema', TJSONObject.ParseJSONValue(ASchema));
  LTool.AddPair('annotations', LAnnotations);
  ATools.AddElement(LTool);
end;

function Tools: TJSONArray;
begin
  Result := TJSONArray.Create;
  AddTool(Result, 'delphi_status', 'Liest Helfer-/DAI-Versionen, registrierte IDE, laufende IDE-Instanzen, DAI-Erreichbarkeit und Start-/Beendigungserlaubnis.',
    '{"type":"object","properties":{},"additionalProperties":false}', True, False);
  AddTool(Result, 'delphi_start', 'Startet die registrierte Delphi-IDE oder wartet auf deren DAI-Bereitschaft. ' +
    'Eine laufende Instanz wird wiederverwendet. Die Start-/Beendigungserlaubnis in den DAI-Optionen muss aktiv sein.',
    '{"type":"object","properties":{"timeout_ms":{"type":"integer","minimum":0,"maximum":30000,"default":20000}},"additionalProperties":false}',
    False, False);
  AddTool(Result, 'delphi_stop', 'Fallback nach normalem DAI-Schließauftrag: close sendet WM_CLOSE, terminate beendet ausdrücklich hart ohne Speichern. ' +
    'Keine automatische Eskalation. Prozessende wird geprüft; explizite process_id benötigt creation_time aus delphi_status. ' +
    'Die Start-/Beendigungserlaubnis in den DAI-Optionen muss aktiv sein, auch für terminate und andere IDE-Instanzen.',
    '{"type":"object","properties":{"mode":{"type":"string","enum":["close","terminate"],"default":"close"},' +
    '"process_id":{"type":"integer","minimum":1,"maximum":4294967295},"creation_time":{"type":"string","pattern":"^[0-9]+$"},' +
    '"timeout_ms":{"type":"integer","minimum":0,"maximum":30000,"default":5000}},"additionalProperties":false}', False, True);
end;

constructor TDAILauncherProtocol.Create;
begin
  inherited Create;
  FLauncher := TDAILauncher.CreateFromCommandLine;
end;

destructor TDAILauncherProtocol.Destroy;
begin
  FLauncher.Free;
  inherited;
end;

function TDAILauncherProtocol.Handle(const AMessage: TJSONValue): TJSONObject;
var
  LArguments, LData, LMeta, LObject, LParams, LResult: TJSONObject;
  LCreatedArguments, LModern: Boolean;
  LId, LValue: TJSONValue;
  LMethod, LName, LVersion: string;
  LNumericId: Int64;
  LVersions: TJSONArray;
begin
  if not Assigned(AMessage) then
    Exit(RPCError(nil, -32700, 'Ungültiges JSON.'));
  if not (AMessage is TJSONObject) then
    Exit(RPCError(nil, -32600, 'Eine JSON-RPC-2.0-Anfrage pro Zeile wird erwartet.'));
  LObject := TJSONObject(AMessage);
  LId := LObject.GetValue('id');
  LValue := LObject.GetValue('jsonrpc');
  if not (LValue is TJSONString) then
    Exit(RPCError(nil, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  if LValue.Value <> '2.0' then
    Exit(RPCError(nil, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  LValue := LObject.GetValue('method');
  if not (LValue is TJSONString) then
    Exit(RPCError(nil, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  if LValue.Value = '' then
    Exit(RPCError(nil, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  if Assigned(LId) then
  begin
    if not ((LId is TJSONString) or (LId is TJSONNumber)) then
      Exit(RPCError(nil, -32600, 'Ungültige JSON-RPC-ID.'));
    if LId is TJSONNumber then
      if not TryStrToInt64(LId.Value, LNumericId) then
        Exit(RPCError(nil, -32600, 'Ungültige JSON-RPC-ID.'));
  end;
  if not Assigned(LId) then
    Exit(nil);
  LMethod := LValue.Value;
  LValue := LObject.GetValue('params');
  if Assigned(LValue) and not (LValue is TJSONObject) then
    Exit(RPCError(LId, -32602, 'params muss ein Objekt sein.'));
  LParams := LObject.GetValue<TJSONObject>('params', nil);
  LMeta := nil;
  if Assigned(LParams) then
  begin
    LValue := LParams.GetValue('_meta');
    if Assigned(LValue) and not (LValue is TJSONObject) then
      Exit(RPCError(LId, -32602, '_meta muss ein Objekt sein.'));
    LMeta := LParams.GetValue<TJSONObject>('_meta', nil);
  end;
  LModern := False;
  if Assigned(LMeta) then
  begin
    LValue := LMeta.GetValue('io.modelcontextprotocol/protocolVersion');
    if Assigned(LValue) then
    begin
      if not (LValue is TJSONString) then
        Exit(RPCError(LId, -32602, 'protocolVersion muss ein String sein.'));
      if (LValue.Value <> '2026-07-28') and (LValue.Value <> '2025-11-25') and (LValue.Value <> '2025-06-18') then
        Exit(RPCError(LId, -32022, 'Nicht unterstützte MCP-Protokollversion.'));
      LModern := LValue.Value = '2026-07-28';
      if LModern and not (LMeta.GetValue('io.modelcontextprotocol/clientCapabilities') is TJSONObject) then
        Exit(RPCError(LId, -32602, 'Moderne MCP-Anfragen benötigen clientCapabilities.'));
    end;
  end;
  if LMethod = 'initialize' then
  begin
    if LModern then
      Exit(RPCError(LId, -32601, 'Moderne MCP-Clients verwenden server/discover.'));
    LVersion := '2025-06-18';
    if Assigned(LParams) then
    begin
      LValue := LParams.GetValue('protocolVersion');
      if Assigned(LValue) then
      begin
        if not (LValue is TJSONString) then
          Exit(RPCError(LId, -32602, 'protocolVersion muss ein String sein.'));
        LVersion := LValue.Value;
      end;
    end;
    if LVersion <> '2025-06-18' then
      LVersion := '2025-11-25';
    LResult := TJSONObject.Create;
    LResult.AddPair('protocolVersion', LVersion);
    LResult.AddPair('serverInfo', ServerInfo);
    LResult.AddPair('capabilities', Capabilities);
    LResult.AddPair('instructions', 'Delphi zuerst über dai/ide_window_control schließen. dai_start prüft das Prozessende und hilft bei nicht erreichbarem DAI. ' +
      'terminate ausschließlich ausdrücklich aufrufen. Speicherrückfragen oder Timeout führen nie automatisch zum harten Beenden. ' +
      'delphi_status bleibt bei gesperrter Start-/Beendigungserlaubnis verfügbar und erklärt die Sperre.');
    Exit(RPCResponse(LId, LResult));
  end;
  if LMethod = 'server/discover' then
  begin
    LResult := CompleteResult(True);
    LVersions := TJSONArray.Create;
    LVersions.Add('2026-07-28');
    LVersions.Add('2025-11-25');
    LVersions.Add('2025-06-18');
    LResult.AddPair('supportedVersions', LVersions);
    LResult.AddPair('capabilities', Capabilities);
    Exit(RPCResponse(LId, LResult));
  end;
  if LMethod = 'ping' then
    Exit(RPCResponse(LId, CompleteResult(LModern)));
  if LMethod = 'tools/list' then
  begin
    LResult := CompleteResult(LModern);
    LResult.AddPair('tools', Tools);
    Exit(RPCResponse(LId, LResult));
  end;
  if LMethod <> 'tools/call' then
    Exit(RPCError(LId, -32601, 'Methode nicht gefunden.'));
  if not Assigned(LParams) then
    Exit(RPCError(LId, -32602, 'params muss ein Objekt sein.'));
  if not (LParams.GetValue('name') is TJSONString) then
    Exit(RPCError(LId, -32602, 'name muss ein Werkzeugname sein.'));
  LName := LParams.GetValue('name').Value;
  if (LName <> 'delphi_status') and (LName <> 'delphi_start') and (LName <> 'delphi_stop') then
    Exit(RPCError(LId, -32602, 'Unbekanntes Starthelfer-Werkzeug.'));
  LValue := LParams.GetValue('arguments');
  if Assigned(LValue) and not (LValue is TJSONObject) then
    Exit(RPCError(LId, -32602, 'arguments muss ein Objekt sein.'));
  LArguments := LParams.GetValue<TJSONObject>('arguments', nil);
  LCreatedArguments := not Assigned(LArguments);
  if LCreatedArguments then
    LArguments := TJSONObject.Create;
  try
    try
      LData := FLauncher.Call(LName, LArguments);
      Result := RPCResponse(LId, ToolResult(LData, False, LModern));
    except
      on E: EArgumentException do
        Result := RPCError(LId, -32602, E.Message);
      on E: Exception do
      begin
        LData := TJSONObject.Create;
        LData.AddPair('error', E.Message);
        Result := RPCResponse(LId, ToolResult(LData, True, LModern));
      end;
    end;
  finally
    if LCreatedArguments then
      LArguments.Free;
  end;
end;

end.
