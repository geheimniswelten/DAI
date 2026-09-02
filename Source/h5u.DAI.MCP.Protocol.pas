unit h5u.DAI.MCP.Protocol;

interface

uses
  System.JSON;

type
  TDAIMCPProtocol = class sealed
  public
    class function HandleMessage( const AMessage: TJSONObject;
      const ATransportSessionId: string;
      out AHTTPStatus: Integer
    ): TJSONObject; static;
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

function JsonRpcError( const AId: TJSONValue;
  const ACode: Integer;
  const AMessage: string;
  const AData: string = ''
): TJSONObject;
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
  Result := SameText(AMessage.GetValue<string>('method', ''), 'server/discover');
  LParams := AMessage.GetValue<TJSONObject>('params');
  if not Assigned(LParams) then
    Exit;
  LMeta := LParams.GetValue<TJSONObject>('_meta');
  if Assigned(LMeta) then
    Result := SameText(LMeta.GetValue<string>('io.modelcontextprotocol/protocolVersion', ''), '2026-07-28');
end;

function ExtractRequestContext( const AParams: TJSONObject;
  const AArguments: TJSONObject;
  const ATransportSessionId: string
): TDAIRequestContext;
var
  LMeta: TJSONObject;
begin
  Result := Default(TDAIRequestContext);
  Result.TransportSessionId := ATransportSessionId;
  Result.ProjectKey := TDAIOTA.ActiveProjectFileName;

  LMeta := nil;
  if Assigned(AParams) then
    LMeta := AParams.GetValue<TJSONObject>('_meta');
  if not Assigned(LMeta) and Assigned(AArguments) then
    LMeta := AArguments.GetValue<TJSONObject>('_meta');

  if Assigned(LMeta) then
  begin
    Result.ThreadId := LMeta.GetValue<string>('threadId', '');
    Result.ClientName := LMeta.GetValue<string>('clientName', 'Codex');
  end;

  if Result.ClientName = '' then
    Result.ClientName := 'Codex';
end;

function BuildInitializationResult(const ARequestedVersion: string): TJSONObject;
var
  LCapabilities: TJSONObject;
  LProtocolVersion: string;
  LServerInfo: TJSONObject;
  LTools: TJSONObject;
begin
  if SameText(ARequestedVersion, '2026-07-28') then
    LProtocolVersion := '2026-07-28'
  else if SameText(ARequestedVersion, '2025-11-25') then
    LProtocolVersion := '2025-11-25'
  else
    LProtocolVersion := '2025-06-18';

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
  Result.AddPair(
    'instructions',
    'DAI steuert die aktuell geöffnete Delphi-IDE. Berechtigungen werden in der IDE nach Projekt und Codex-Chat getrennt abgefragt.'
  );
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
  Result.AddPair('instructions', 'DAI unterstützt die moderne MCP-Erkennung sowie den klassischen initialize-Ablauf.');
end;

class function TDAIMCPProtocol.HandleMessage( const AMessage: TJSONObject;
  const ATransportSessionId: string;
  out AHTTPStatus: Integer
): TJSONObject;
var
  LArguments: TJSONObject;
  LContext: TDAIRequestContext;
  LCreatedArguments: Boolean;
  LCreatedParams: Boolean;
  LId: TJSONValue;
  LMethod: string;
  LModern: Boolean;
  LName: string;
  LParams: TJSONObject;
  LResult: TJSONObject;
  LToolResult: TJSONObject;
begin
  Result := nil;
  AHTTPStatus := 200;
  LId := AMessage.GetValue('id');
  LMethod := AMessage.GetValue<string>('method', '');
  LParams := AMessage.GetValue<TJSONObject>('params');
  LModern := IsModernRequest(AMessage);

  if AMessage.GetValue<string>('jsonrpc', '') <> '2.0' then
  begin
    AHTTPStatus := 400;
    Exit(JsonRpcError(LId, -32600, 'Ungültige JSON-RPC-2.0-Anfrage.'));
  end;

  if SameText(LMethod, 'notifications/initialized') or SameText(LMethod, 'notifications/cancelled') then
  begin
    AHTTPStatus := 202;
    Exit(nil);
  end;

  if SameText(LMethod, 'initialize') then
  begin
    LCreatedParams := not Assigned(LParams);
    if LCreatedParams then
      LParams := TJSONObject.Create;
    try
      Exit(JsonRpcResponse(LId, BuildInitializationResult(LParams.GetValue<string>('protocolVersion', '2025-06-18'))));
    finally
      if LCreatedParams then
        LParams.Free;
    end;
  end;

  if SameText(LMethod, 'server/discover') then
    Exit(JsonRpcResponse(LId, BuildDiscoveryResult));

  if SameText(LMethod, 'ping') then
    Exit(JsonRpcResponse(LId, TJSONObject.Create));

  if SameText(LMethod, 'tools/list') then
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

  if SameText(LMethod, 'tools/call') then
  begin
    if not Assigned(LParams) then
      Exit(JsonRpcError(LId, -32602, 'params muss ein Objekt sein.'));

    LName := LParams.GetValue<string>('name', '');
    LArguments := LParams.GetValue<TJSONObject>('arguments');
    LCreatedArguments := not Assigned(LArguments);
    if LCreatedArguments then
      LArguments := TJSONObject.Create;
    try
      LContext := ExtractRequestContext(LParams, LArguments, ATransportSessionId);
      try
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
