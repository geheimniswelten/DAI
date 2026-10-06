program Test.DesignerDispatch;
{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}
uses
  System.JSON, System.SysUtils, System.Classes,
  DAI.DesignerDispatch.ProductionBranch,
  h5u.DAI.OTA.Designer, h5u.DAI.OTA.Palette,
  h5u.DAI.Permissions.Manager, h5u.DAI.Types;
const
  CFile = 'C:\Workspace\MainForm.pas';
  CTools: array[0..6] of string = ('form_components_search', 'form_components_select', 'form_component_properties',
    'form_component_set_property', 'form_component_move', 'form_component_create', 'form_palette_list');
  CMethods: array[0..5] of string = ('search', 'select', 'properties', 'set_property', 'move', 'create');
var
  Checks: Integer;
  Context: TDAIRequestContext;
procedure Check(const ACondition: Boolean; const AMessage: string);
begin Inc(Checks); if not ACondition then raise EInvalidOperation.Create('Assertion failed: ' + AMessage); end;
procedure Reset(const AReadAllowed: Boolean = True; const AEditAllowed: Boolean = True);
begin
  TDAIPermissionManager.Instance.Reset(AReadAllowed, AEditAllowed);
  TDAIDesignerService.Reset; TDAIPaletteService.Reset;
  Context.ProjectKey := 'C:\Workspace\Main.dproj';
  Context.ThreadId := 'designer-thread'; Context.TransportSessionId := 'designer-transport'; Context.ClientName := 'designer-client';
end;
function Arguments(const AIndex: Integer): TJSONObject;
var Names: TJSONArray;
begin
  Result := TJSONObject.Create;
  if AIndex <> 6 then Result.AddPair('file', CFile);
  case AIndex of
    1: begin Names := TJSONArray.Create; Names.Add('Button1'); Names.Add('Panel1'); Result.AddPair('components', Names); end;
    2, 3, 4: Result.AddPair('component', 'Button1');
    5: Result.AddPair('class_name', 'TButton');
  end;
  if AIndex = 3 then begin Result.AddPair('property', 'Name'); Result.AddPair('value', 'SaveButton'); end;
end;
procedure Replace(const AArguments: TJSONObject; const AName: string; const AValue: TJSONValue);
begin AArguments.RemovePair(AName).Free; AArguments.AddPair(AName, AValue); end;
function IsMutation(const AIndex: Integer): Boolean;
begin Result := AIndex in [1, 3, 4, 5]; end;
procedure TestForwarding(const AIndex: Integer; const AExplicit: Boolean);
var
  Args, Response: TJSONObject;
  Original: string;
  Expected, I: Integer;
  Request: TPermissionRequest;
  Names: TJSONArray;
begin
  Reset; Args := Arguments(AIndex); Response := nil;
  try
    if AExplicit then
      case AIndex of
        0: begin
          Args.AddPair('query', '^Button[0-9]+$'); Args.AddPair('use_regex', TJSONBool.Create(True));
          Args.AddPair('class_name', 'TButton'); Args.AddPair('parent', 'Panel1');
          Args.AddPair('case_sensitive', TJSONBool.Create(True)); Args.AddPair('maximum_results', TJSONNumber.Create(4096));
        end;
        1: begin Args.AddPair('add_to_selection', TJSONBool.Create(True)); Args.AddPair('focus', TJSONBool.Create(False)); end;
        2: begin Names := TJSONArray.Create; Names.Add('Name'); Names.Add('Font.Size'); Args.AddPair('properties', Names); end;
        3: begin Replace(Args, 'property', TJSONString.Create('Tag')); Replace(Args, 'value', TJSONNumber.Create(17)); end;
        4: begin
          Args.AddPair('parent', 'Panel1'); Args.AddPair('parent_mode', 'explicit');
          Args.AddPair('x', TJSONNumber.Create(12.5)); Args.AddPair('y', TJSONNumber.Create(-4.25));
          Args.AddPair('width', TJSONNumber.Create(120)); Args.AddPair('height', TJSONNumber.Create(0));
        end;
        5: begin
          Args.AddPair('name', 'SaveButton'); Args.AddPair('parent', 'Panel1'); Args.AddPair('parent_mode', 'explicit');
          Args.AddPair('x', TJSONNumber.Create(-1)); Args.AddPair('y', TJSONNumber.Create(16));
          Args.AddPair('width', TJSONNumber.Create(100)); Args.AddPair('height', TJSONNumber.Create(24));
          Args.AddPair('select', TJSONBool.Create(False));
        end;
        6: begin
          Args.AddPair('query', 'Button'); Args.AddPair('category', 'Standard');
          Args.AddPair('include_unavailable', TJSONBool.Create(True)); Args.AddPair('maximum_results', TJSONNumber.Create(4096));
        end;
      end;
    Original := Args.ToJSON;
    Response := DispatchDesigner(CTools[AIndex], Args, Context);
    Expected := 1; if IsMutation(AIndex) then Expected := 2;
    Check(Length(TDAIPermissionManager.Instance.Requests) = Expected, 'exact permissions for ' + CTools[AIndex]);
    for I := 0 to Expected - 1 do
    begin
      Request := TDAIPermissionManager.Instance.Requests[I];
      if I = 0 then Check(Request.Category = pcReadAccess, 'read precedes operation')
      else Check(Request.Category = pcEditInsideIDE, 'edit precedes mutation');
      if AIndex = 6 then Check(Request.Resource = '', 'palette resource global')
      else Check(Request.Resource = CFile, 'actual form permission resource');
      Check(Request.Context.ProjectKey = Context.ProjectKey, 'owning project retained');
      Check(Request.Context.ThreadId = Context.ThreadId, 'thread retained');
      Check(Request.Context.TransportSessionId = Context.TransportSessionId, 'transport retained');
      Check(Request.Context.ClientName = Context.ClientName, 'client retained');
    end;
    Check(Args.ToJSON = Original, 'argument object unchanged');
    if AIndex = 6 then
    begin
      Check(TDAIPaletteService.Calls = 1, 'one palette service call'); Check(TDAIDesignerService.Calls = 0, 'no designer call for palette');
      Check(TDAIPaletteService.PermissionCount = Expected, 'palette authorization before read');
      Check(TDAIPaletteService.LastArguments = Original, 'palette arguments forwarded');
      Check(Response = TDAIPaletteService.LastResponse, 'palette response retained');
      Check(not Response.GetValue<Boolean>('available'), 'unavailable status retained');
    end
    else
    begin
      Check(TDAIDesignerService.Calls = 1, 'one designer service call'); Check(TDAIPaletteService.Calls = 0, 'no palette side operation');
      Check(TDAIDesignerService.LastMethod = CMethods[AIndex], 'correct SDK method');
      Check(TDAIDesignerService.LastFile = CFile, 'exact form file forwarded');
      Check(TDAIDesignerService.LastArguments = Original, 'all arguments forwarded');
      Check(TDAIDesignerService.PermissionCount = Expected, 'all authorization before SDK call');
      Check(Response = TDAIDesignerService.LastResponse, 'SDK response retained');
      Check(not Response.GetValue<Boolean>('modified'), 'actual unmodified status retained');
      Check(Response.GetValue('actual_value') is TJSONNull, 'unknown property value retained');
    end;
  finally Response.Free; Args.Free; end;
end;
procedure Rejected(const AIndex: Integer; const AArguments: TJSONObject; const APermissionCount: Integer);
var Failed: Boolean; Response: TJSONObject;
begin
  Failed := False;
  try Response := DispatchDesigner(CTools[AIndex], AArguments, Context); Response.Free;
  except on E: Exception do Failed := True; end;
  Check(Failed, 'invalid or denied operation rejected: ' + CTools[AIndex]);
  Check(TDAIDesignerService.Calls = 0, 'no designer SDK call after rejection');
  Check(TDAIPaletteService.Calls = 0, 'no palette SDK call after rejection');
  Check(Length(TDAIPermissionManager.Instance.Requests) = APermissionCount, 'exact permissions before rejection');
end;
procedure InvalidValue(const AIndex: Integer; const AName: string; const AValue: TJSONValue);
var Args: TJSONObject;
begin
  Reset; Args := Arguments(AIndex);
  try Replace(Args, AName, AValue); Rejected(AIndex, Args, 0); finally Args.Free; end;
end;
procedure MissingValue(const AIndex: Integer; const AName: string);
var Args: TJSONObject;
begin
  Reset; Args := Arguments(AIndex);
  try Args.RemovePair(AName).Free; Rejected(AIndex, Args, 0); finally Args.Free; end;
end;
procedure TestRejections;
var I: Integer; Args: TJSONObject;
begin
  for I := 0 to High(CTools) do
  begin
    Args := Arguments(I);
    try
      Reset(False, True); Rejected(I, Args, 1);
      if IsMutation(I) then begin Reset(True, False); Rejected(I, Args, 2); end;
    finally Args.Free; end;
    if I <> 6 then
    begin
      MissingValue(I, 'file'); InvalidValue(I, 'file', TJSONNumber.Create(1)); InvalidValue(I, 'file', TJSONString.Create(' '));
    end;
  end;
  InvalidValue(0, 'query', TJSONBool.Create(True)); InvalidValue(0, 'class_name', TJSONNumber.Create(1));
  InvalidValue(0, 'parent', TJSONNull.Create); InvalidValue(0, 'use_regex', TJSONString.Create('true'));
  InvalidValue(0, 'case_sensitive', TJSONNumber.Create(1)); InvalidValue(0, 'maximum_results', TJSONNumber.Create(0));
  InvalidValue(0, 'maximum_results', TJSONNumber.Create(4097)); InvalidValue(0, 'maximum_results', TJSONNumber.Create(1.5));
  MissingValue(1, 'components'); InvalidValue(1, 'components', TJSONArray.Create);
  InvalidValue(1, 'components', TJSONString.Create('Button1'));
  InvalidValue(1, 'add_to_selection', TJSONNumber.Create(0)); InvalidValue(1, 'focus', TJSONString.Create('true'));
  MissingValue(2, 'component'); InvalidValue(2, 'properties', TJSONString.Create('Name'));
  MissingValue(3, 'property'); MissingValue(3, 'value'); InvalidValue(3, 'value', TJSONObject.Create);
  InvalidValue(3, 'value', TJSONArray.Create); InvalidValue(3, 'property', TJSONNull.Create);
  InvalidValue(4, 'parent_mode', TJSONString.Create('owner')); InvalidValue(4, 'x', TJSONString.Create('12'));
  InvalidValue(4, 'y', TJSONBool.Create(False)); InvalidValue(4, 'width', TJSONNumber.Create(-1));
  InvalidValue(4, 'height', TJSONBool.Create(False)); MissingValue(5, 'class_name');
  InvalidValue(5, 'name', TJSONNumber.Create(1)); InvalidValue(5, 'x', TJSONNumber.Create(0.5));
  InvalidValue(5, 'width', TJSONNumber.Create(-2)); InvalidValue(5, 'select', TJSONString.Create('false'));
  InvalidValue(6, 'category', TJSONArray.Create); InvalidValue(6, 'include_unavailable', TJSONString.Create('true'));
  InvalidValue(6, 'maximum_results', TJSONNumber.Create(4097));
end;
procedure TestScalarsAndParentModes;
var Args, Response: TJSONObject; Mode: string; Value: TJSONValue;
begin
  for Mode in ['explicit', 'selected', 'selected_parent', 'root'] do
  begin
    Reset; Args := Arguments(4); Args.AddPair('parent_mode', Mode);
    try Response := DispatchDesigner(CTools[4], Args, Context); Response.Free; Check(TDAIDesignerService.Calls = 1, 'parent mode accepted');
    finally Args.Free; end;
  end;
  for Mode in ['boolean', 'null'] do
  begin
    Reset; Args := Arguments(3);
    if Mode = 'boolean' then Value := TJSONBool.Create(True) else Value := TJSONNull.Create;
    try
      Replace(Args, 'value', Value); Response := DispatchDesigner(CTools[3], Args, Context); Response.Free;
      Check(TDAIDesignerService.LastArguments = Args.ToJSON, 'typed scalar forwarded');
    finally Args.Free; end;
  end;
  Reset; Response := DispatchDesigner(CTools[6], nil, Context);
  try Check(TDAIPaletteService.Calls = 1, 'palette accepts no arguments'); finally Response.Free; end;
end;
procedure TestSchemas;
var Schemas: TJSONArray; Tool, Schema, Props: TJSONObject; I: Integer;
begin
  Schemas := ListDesignerSchemas;
  try
    Check(Schemas.Count = Length(CTools), 'seven production tools');
    for I := 0 to High(CTools) do
    begin
      Tool := TJSONObject(Schemas.Items[I]); Check(Tool.GetValue<string>('name') = CTools[I], 'actual registered name');
      Check(Tool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint') = not IsMutation(I), 'readonly annotation');
      Schema := Tool.GetValue<TJSONObject>('inputSchema'); Check(not Schema.GetValue<Boolean>('additionalProperties'), 'strict schema');
      Props := Schema.GetValue<TJSONObject>('properties');
      if I <> 6 then Check(Props.GetValue<TJSONObject>('file').GetValue<Integer>('minLength') = 1, 'required filename type');
      if I = 0 then Check(Props.GetValue<TJSONObject>('maximum_results').GetValue<Integer>('default') = 100, 'search default');
      if I = 1 then Check(Props.GetValue<TJSONObject>('components').GetValue<Integer>('minItems') = 1, 'nonempty selection schema');
      if I = 3 then Check(Props.GetValue<TJSONObject>('value').GetValue<TJSONArray>('type').Count = 4, 'scalar types schema');
      if I = 4 then Check(Props.GetValue<TJSONObject>('parent_mode').GetValue<string>('default') = 'explicit', 'move retains parent default');
      if I = 5 then Check(Props.GetValue<TJSONObject>('parent_mode').GetValue<string>('default') = 'selected', 'create selection default');
      if I = 6 then Check(Props.GetValue<TJSONObject>('maximum_results').GetValue<Integer>('default') = 500, 'palette default');
    end;
  finally Schemas.Free; end;
end;
var I: Integer;
begin
  try
    TestSchemas;
    for I := 0 to High(CTools) do begin TestForwarding(I, False); TestForwarding(I, True); end;
    TestRejections; TestScalarsAndParentModes;
    Writeln('PASS DesignerDispatch: ', Checks, ' checks');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
