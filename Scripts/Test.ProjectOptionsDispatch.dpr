program Test.ProjectOptionsDispatch;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  DAI.ProjectOptionsDispatch.ProductionBranch,
  h5u.DAI.OTA.ProjectOptions,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Types;

const
  CToolNames: array[0..4] of string = ('project_activate', 'project_options_configurations', 'project_options_read',
    'project_option_set', 'project_option_remove');
  CMethods: array[0..4] of string = ('activate', 'configurations', 'read', 'set', 'remove');
  COperations: array[0..4] of string = ('Geöffnetes Gruppenprojekt aktivieren', 'Konfigurationen des aktiven Projekts lesen',
    'Optionen und Vererbung des aktiven Projekts lesen', 'Lokale Projektoption setzen',
    'Lokale Projektoption entfernen und Vererbung wiederherstellen');
  CExplicitProject = 'C:\IsolatedProjectOptionsTest\Explicit.dproj';

var
  GChecks: Integer;
  GContext: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + ADescription);
end;

procedure Reset(const AReadAllowed: Boolean = True; const AEditAllowed: Boolean = True);
begin
  TDAIProjectOptionsService.Reset;
  TDAIPermissionManager.Instance.Reset(AReadAllowed, AEditAllowed);
end;

function ArgumentsFor(const AToolIndex: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', CExplicitProject);
  if AToolIndex in [3, 4] then
  begin
    Result.AddPair('configuration', 'Base');
    Result.AddPair('platform', '');
    Result.AddPair('name', 'DCC_UnitSearchPath');
  end;
  if AToolIndex = 3 then
    Result.AddPair('value', '');
end;

procedure ReplaceValue(const AArguments: TJSONObject; const AName: string; const AValue: TJSONValue);
begin
  AArguments.RemovePair(AName).Free;
  AArguments.AddPair(AName, AValue);
end;

function NonStringValue(const AIndex: Integer): TJSONValue;
begin
  case AIndex of
    0: Result := TJSONNull.Create;
    1: Result := TJSONBool.Create(True);
    2: Result := TJSONNumber.Create(42);
    3: Result := TJSONArray.Create;
    4: Result := TJSONObject.Create;
  else
    raise EArgumentException.Create('Invalid fixture value index.');
  end;
end;

procedure CheckPermission(const AToolIndex: Integer; const AProject: string);
var
  LExpectedCategory: TDAIPermissionCategory;
  LRequest: TPermissionRequest;
begin
  Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'exactly one permission request');
  LRequest := TDAIPermissionManager.Instance.Requests[0];
  if AToolIndex in [1, 2] then
    LExpectedCategory := pcReadAccess
  else
    LExpectedCategory := pcEditInsideIDE;
  Check(LRequest.Category = LExpectedCategory, 'correct permission category for ' + CToolNames[AToolIndex]);
  Check(LRequest.Operation = COperations[AToolIndex], 'meaningful permission operation for ' + CToolNames[AToolIndex]);
  Check(LRequest.Resource = AProject, 'permission bound to exact requested project');
  Check(LRequest.Context.ThreadId = GContext.ThreadId, 'thread context retained');
  Check(LRequest.Context.TransportSessionId = GContext.TransportSessionId, 'transport context retained');
  Check(LRequest.Context.ProjectKey = GContext.ProjectKey, 'supplied project context retained');
  Check(LRequest.Context.ClientName = GContext.ClientName, 'client context retained');
end;

procedure TestPermission(const AToolIndex: Integer; const AReadAllowed, AEditAllowed: Boolean);
var
  LArguments: TJSONObject;
  LAllowed: Boolean;
  LDenied: Boolean;
  LResult: TJSONObject;
begin
  Reset(AReadAllowed, AEditAllowed);
  LArguments := ArgumentsFor(AToolIndex);
  LResult := nil;
  LDenied := False;
  if AToolIndex in [1, 2] then
    LAllowed := AReadAllowed
  else
    LAllowed := AEditAllowed;
  try
    try
      LResult := DispatchProjectOptions(UpperCase(CToolNames[AToolIndex]), LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    CheckPermission(AToolIndex, CExplicitProject);
    Check(LDenied = not LAllowed, 'denial occurs before service execution');
    Check(Assigned(LResult) = LAllowed, 'no success response after permission denial');
    Check(TDAIProjectOptionsService.Calls = Ord(LAllowed), 'service called exactly once only when permitted');
    if LAllowed then
    begin
      Check(TDAIProjectOptionsService.LastMethod = CMethods[AToolIndex], 'correct dispatch target');
      Check(TDAIProjectOptionsService.LastProject = CExplicitProject, 'service receives exact project');
      Check(LResult.GetValue<string>('method') = CMethods[AToolIndex], 'service response returned unchanged');
    end;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestContextProject(const AToolIndex, AProjectVariant: Integer);
var
  LArguments: TJSONObject;
  LResult: TJSONObject;
begin
  Reset;
  LArguments := ArgumentsFor(AToolIndex);
  LResult := nil;
  try
    LArguments.RemovePair('project').Free;
    if AProjectVariant = 1 then
      LArguments.AddPair('project', '')
    else if AProjectVariant = 2 then
      LArguments.AddPair('project', ' ' + #9);
    LResult := DispatchProjectOptions(CToolNames[AToolIndex], LArguments, GContext);
    CheckPermission(AToolIndex, GContext.ProjectKey);
    Check(TDAIProjectOptionsService.Calls = 1, 'implicit-project request reaches service once');
    Check(TDAIProjectOptionsService.LastProject = GContext.ProjectKey, 'implicit project is bound to captured permission context');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure ExpectInvalid(const AToolIndex: Integer; const AArguments: TJSONObject; const ADescription: string);
var
  LRejected: Boolean;
  LResult: TJSONObject;
begin
  Reset;
  LResult := nil;
  LRejected := False;
  try
    try
      LResult := DispatchProjectOptions(CToolNames[AToolIndex], AArguments, GContext);
    except
      on E: EArgumentException do
        LRejected := True;
    end;
    Check(LRejected, ADescription + ' rejected as an argument error');
    Check(not Assigned(LResult), ADescription + ' produces no success response');
    Check(TDAIProjectOptionsService.Calls = 0, ADescription + ' never reaches OTA service');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, ADescription + ' rejected before permission prompt');
  finally
    LResult.Free;
  end;
end;

procedure TestStringTypes(const AToolIndex: Integer; const AField: string);
var
  LArguments: TJSONObject;
  LValueIndex: Integer;
begin
  for LValueIndex := 0 to 4 do
  begin
    LArguments := ArgumentsFor(AToolIndex);
    try
      ReplaceValue(LArguments, AField, NonStringValue(LValueIndex));
      ExpectInvalid(AToolIndex, LArguments, CToolNames[AToolIndex] + '/' + AField + '/nonstring-' + IntToStr(LValueIndex));
    finally
      LArguments.Free;
    end;
  end;
end;

procedure TestRequired(const AToolIndex: Integer; const AField: string; const AAllowEmpty: Boolean);
var
  LArguments: TJSONObject;
begin
  LArguments := ArgumentsFor(AToolIndex);
  try
    LArguments.RemovePair(AField).Free;
    ExpectInvalid(AToolIndex, LArguments, CToolNames[AToolIndex] + '/' + AField + '/missing');
    if not AAllowEmpty then
    begin
      LArguments.AddPair(AField, '');
      ExpectInvalid(AToolIndex, LArguments, CToolNames[AToolIndex] + '/' + AField + '/empty');
      ReplaceValue(LArguments, AField, TJSONString.Create(' ' + #9));
      ExpectInvalid(AToolIndex, LArguments, CToolNames[AToolIndex] + '/' + AField + '/whitespace');
    end;
  finally
    LArguments.Free;
  end;
end;

procedure TestReadArguments;
const
  CInvalidCounts: array[0..2] of Integer = (-1, 0, 1001);
  CValidCounts: array[0..1] of Integer = (1, 1000);
  CNamesCounts: array[0..2] of Integer = (0, 1000, 1001);
var
  LArguments: TJSONObject;
  LArray: TJSONArray;
  LIndex: Integer;
  LResult: TJSONObject;
  LVariant: Integer;
begin
  Reset;
  LResult := DispatchProjectOptions('project_options_read', nil, GContext);
  try
    CheckPermission(2, GContext.ProjectKey);
    Check(TDAIProjectOptionsService.LastConfiguration = 'active', 'read defaults to active configuration');
    Check(TDAIProjectOptionsService.LastPlatform = 'active', 'read defaults to active platform');
    Check(TDAIProjectOptionsService.LastMaximumOptions = 200, 'read default is bounded to 200 options');
    Check(Length(TDAIProjectOptionsService.LastNames) = 0, 'read omitted names enumerates local/ancestor names');
  finally
    LResult.Free;
  end;
  LArguments := ArgumentsFor(2);
  try
    LArguments.AddPair('configuration', 'Release');
    LArguments.AddPair('platform', 'Win64');
    LArguments.AddPair('maximum_options', TJSONNumber.Create(77));
    LArray := TJSONArray.Create;
    LArray.Add('DCC_UnitSearchPath');
    LArray.Add('DCC_Define');
    LArguments.AddPair('names', LArray);
    Reset;
    LResult := DispatchProjectOptions('project_options_read', LArguments, GContext);
    try
      Check(TDAIProjectOptionsService.LastConfiguration = 'Release', 'read preserves explicit configuration');
      Check(TDAIProjectOptionsService.LastPlatform = 'Win64', 'read preserves explicit platform');
      Check(TDAIProjectOptionsService.LastMaximumOptions = 77, 'read preserves explicit limit');
      Check(Length(TDAIProjectOptionsService.LastNames) = 2, 'read preserves names count');
      Check(TDAIProjectOptionsService.LastNames[0] = 'DCC_UnitSearchPath', 'read preserves first name');
      Check(TDAIProjectOptionsService.LastNames[1] = 'DCC_Define', 'read preserves second name');
    finally
      LResult.Free;
    end;
    for LVariant := 0 to 4 do
    begin
      ReplaceValue(LArguments, 'maximum_options', NonStringValue(LVariant));
      if LVariant = 2 then
        Continue; // An actual JSON integer in range is valid.
      ExpectInvalid(2, LArguments, 'maximum_options/noninteger-' + IntToStr(LVariant));
    end;
    ReplaceValue(LArguments, 'maximum_options', TJSONString.Create('77'));
    ExpectInvalid(2, LArguments, 'maximum_options/numeric-string');
    ReplaceValue(LArguments, 'maximum_options', TJSONNumber.Create(1.5));
    ExpectInvalid(2, LArguments, 'maximum_options/fraction');
    ReplaceValue(LArguments, 'maximum_options', TJSONNumber.Create(Int64(2147483648)));
    ExpectInvalid(2, LArguments, 'maximum_options/integer-overflow');
    for LIndex in CInvalidCounts do
    begin
      ReplaceValue(LArguments, 'maximum_options', TJSONNumber.Create(LIndex));
      ExpectInvalid(2, LArguments, 'maximum_options/outside-bounds-' + IntToStr(LIndex));
    end;
    for LIndex in CValidCounts do
    begin
      ReplaceValue(LArguments, 'maximum_options', TJSONNumber.Create(LIndex));
      Reset;
      LResult := DispatchProjectOptions('project_options_read', LArguments, GContext);
      try
        Check(TDAIProjectOptionsService.LastMaximumOptions = LIndex, 'integer bound accepted exactly');
      finally
        LResult.Free;
      end;
    end;
    LArguments.RemovePair('maximum_options').Free;
    for LVariant := 0 to 4 do
    begin
      if LVariant = 3 then
        Continue; // The outer names value must be an array.
      ReplaceValue(LArguments, 'names', NonStringValue(LVariant));
      ExpectInvalid(2, LArguments, 'names/nonarray-' + IntToStr(LVariant));
    end;
    ReplaceValue(LArguments, 'names', TJSONString.Create('DCC_Define'));
    ExpectInvalid(2, LArguments, 'names/string-instead-of-array');
    for LVariant := 0 to 4 do
    begin
      LArray := TJSONArray.Create;
      LArray.Add('DCC_Define');
      LArray.AddElement(NonStringValue(LVariant));
      ReplaceValue(LArguments, 'names', LArray);
      ExpectInvalid(2, LArguments, 'names/mixed-element-' + IntToStr(LVariant));
    end;
    for LIndex in CNamesCounts do
    begin
      LArray := TJSONArray.Create;
      for LVariant := 1 to LIndex do
        LArray.Add('DCC_Define');
      ReplaceValue(LArguments, 'names', LArray);
      if LIndex = 1001 then
        ExpectInvalid(2, LArguments, 'names/above-1000-elements')
      else
      begin
        Reset;
        LResult := DispatchProjectOptions('project_options_read', LArguments, GContext);
        try
          Check(Length(TDAIProjectOptionsService.LastNames) = LIndex, 'names count bound retained');
        finally
          LResult.Free;
        end;
      end;
    end;
  finally
    LArguments.Free;
  end;
end;

procedure TestWriteArguments;
var
  LArguments: TJSONObject;
  LIndex: Integer;
  LResult: TJSONObject;
  LValue: string;
begin
  for LIndex := 3 to 4 do
  begin
    LArguments := ArgumentsFor(LIndex);
    Reset;
    LResult := nil;
    try
      LResult := DispatchProjectOptions(CToolNames[LIndex], LArguments, GContext);
      Check(TDAIProjectOptionsService.LastConfiguration = 'Base', 'write uses explicit Base, not active config');
      Check(TDAIProjectOptionsService.LastPlatform = '', 'explicit empty platform means all platforms');
      Check(TDAIProjectOptionsService.LastName = 'DCC_UnitSearchPath', 'write preserves option name');
      if LIndex = 3 then
      begin
        Check(TDAIProjectOptionsService.LastValue = '', 'set passes empty value without converting it to deletion');
        Check(TDAIProjectOptionsService.LastMergeMode = 'preserve', 'set preserves merge mode by default');
      end;
    finally
      LResult.Free;
      LArguments.Free;
    end;
  end;
  LArguments := ArgumentsFor(3);
  try
    ReplaceValue(LArguments, 'configuration', TJSONString.Create('Release'));
    ReplaceValue(LArguments, 'platform', TJSONString.Create('Win32'));
    LValue := ' $(BDS)\source;C:\Ünicode\Libraries ' + #13#10 + 'second line';
    ReplaceValue(LArguments, 'value', TJSONString.Create(LValue));
    LArguments.AddPair('merge_mode', 'replace');
    Reset;
    LResult := DispatchProjectOptions('project_option_set', LArguments, GContext);
    try
      Check(TDAIProjectOptionsService.LastConfiguration = 'Release', 'explicit different config retained');
      Check(TDAIProjectOptionsService.LastPlatform = 'Win32', 'explicit different platform retained');
      Check(TDAIProjectOptionsService.LastValue = LValue, 'value whitespace, Unicode, macro and line endings retained exactly');
      Check(TDAIProjectOptionsService.LastMergeMode = 'replace', 'explicit replace mode retained');
    finally
      LResult.Free;
    end;
  finally
    LArguments.Free;
  end;
end;

function StringArrayContains(const AArray: TJSONArray; const AValue: string): Boolean;
var
  LItem: TJSONValue;
begin
  Result := False;
  if Assigned(AArray) then
    for LItem in AArray do
      if (LItem is TJSONString) and (LItem.Value = AValue) then
        Exit(True);
end;

procedure CheckRequired(const ASchema: TJSONObject; const AExpected: TArray<string>);
var
  LArray: TJSONArray;
  LName: string;
begin
  LArray := ASchema.GetValue('required') as TJSONArray;
  if Length(AExpected) = 0 then
  begin
    if Assigned(LArray) then
      Check(LArray.Count = 0, 'read/configuration schema has no mandatory writes')
    else
      Check(True, 'read/configuration schema has no mandatory writes');
  end
  else
  begin
    Check(Assigned(LArray), 'schema declares required arguments');
    Check(LArray.Count = Length(AExpected), 'schema requires only the explicitly documented arguments');
    for LName in AExpected do
      Check(StringArrayContains(LArray, LName), 'schema requires ' + LName);
  end;
end;

procedure TestSchemas;
var
  LAnnotations: TJSONObject;
  LCatalog: TJSONArray;
  LIndex: Integer;
  LProperties: TJSONObject;
  LProperty: TJSONObject;
  LSchema: TJSONObject;
  LTool: TJSONObject;
begin
  LCatalog := ListProjectOptionsSchemas;
  try
    Check(LCatalog.Count = Length(CToolNames), 'all five actual production schemas extracted');
    for LIndex := 0 to LCatalog.Count - 1 do
    begin
      LTool := TJSONObject(LCatalog.Items[LIndex]);
      Check(LTool.GetValue<string>('name') = CToolNames[LIndex], 'schema tool name');
      Check(LTool.GetValue<string>('description') <> '', 'schema includes useful description');
      LSchema := LTool.GetValue<TJSONObject>('inputSchema');
      Check(LSchema.GetValue<string>('type') = 'object', 'schema is an object');
      Check(not LSchema.GetValue<Boolean>('additionalProperties'), 'schema rejects undeclared arguments');
      LAnnotations := LTool.GetValue<TJSONObject>('annotations');
      Check(LAnnotations.GetValue<Boolean>('readOnlyHint') = (LIndex in [1, 2]), 'schema identifies mutations accurately');
      LProperties := LSchema.GetValue<TJSONObject>('properties');
      Check(LProperties.GetValue<TJSONObject>('project').GetValue<string>('type') = 'string', 'project uses string schema');
      case LIndex of
        0: CheckRequired(LSchema, ['project']);
        1, 2: CheckRequired(LSchema, []);
        3: CheckRequired(LSchema, ['configuration', 'platform', 'name', 'value']);
        4: CheckRequired(LSchema, ['configuration', 'platform', 'name']);
      end;
      if LIndex in [2, 3, 4] then
      begin
        Check(LProperties.GetValue<TJSONObject>('configuration').GetValue<string>('type') = 'string', 'configuration is a string');
        Check(LProperties.GetValue<TJSONObject>('platform').GetValue<string>('type') = 'string', 'platform is a string');
      end;
      if LIndex = 2 then
      begin
        Check(LProperties.GetValue<TJSONObject>('configuration').GetValue<string>('default') = 'active', 'read config schema default');
        Check(LProperties.GetValue<TJSONObject>('platform').GetValue<string>('default') = 'active', 'read platform schema default');
        LProperty := LProperties.GetValue<TJSONObject>('names');
        Check(LProperty.GetValue<string>('type') = 'array', 'names schema is an array');
        Check(LProperty.GetValue<TJSONObject>('items').GetValue<string>('type') = 'string', 'names elements must be strings');
        Check(LProperty.GetValue<Integer>('maxItems') = 1000, 'names schema has a finite bound');
        LProperty := LProperties.GetValue<TJSONObject>('maximum_options');
        Check(LProperty.GetValue<string>('type') = 'integer', 'option-count schema requires integers');
        Check(LProperty.GetValue<Integer>('default') = 200, 'schema count default matches dispatcher');
        Check(LProperty.GetValue<Integer>('minimum') = 1, 'schema lower count bound');
        Check(LProperty.GetValue<Integer>('maximum') = 1000, 'schema upper count bound');
      end;
      if LIndex in [3, 4] then
      begin
        Check(not Assigned(LProperties.GetValue<TJSONObject>('configuration').GetValue('default')), 'write config has no active default');
        Check(not Assigned(LProperties.GetValue<TJSONObject>('platform').GetValue('default')), 'write platform has no active default');
        Check(LProperties.GetValue<TJSONObject>('name').GetValue<string>('type') = 'string', 'write name uses string schema');
        Check(not Assigned(LProperties.GetValue<TJSONObject>('platform').GetValue('minLength')), 'explicit empty platform remains valid');
      end;
      if LIndex = 3 then
      begin
        LProperty := LProperties.GetValue<TJSONObject>('value');
        Check(LProperty.GetValue<string>('type') = 'string', 'set value uses string schema');
        Check(not Assigned(LProperty.GetValue('minLength')), 'explicit empty value remains valid');
        Check(LProperty.GetValue<Integer>('maxLength') = 65536, 'set value schema has a finite bound');
        LProperty := LProperties.GetValue<TJSONObject>('merge_mode');
        Check(LProperty.GetValue<string>('default') = 'preserve', 'merge-mode schema default matches dispatcher');
        Check(LProperty.GetValue<TJSONArray>('enum').Count = 3, 'all merge modes exposed');
        Check(StringArrayContains(LProperty.GetValue<TJSONArray>('enum'), 'preserve'), 'preserve merge mode exposed');
        Check(StringArrayContains(LProperty.GetValue<TJSONArray>('enum'), 'merge'), 'merge mode exposed');
        Check(StringArrayContains(LProperty.GetValue<TJSONArray>('enum'), 'replace'), 'replace mode exposed');
      end;
    end;
  finally
    LCatalog.Free;
  end;
end;

procedure RunTests;
var
  LArguments: TJSONObject;
  LIndex: Integer;
  LReadAllowed: Boolean;
  LEditAllowed: Boolean;
  LVariant: Integer;
begin
  GContext.ThreadId := 'project-options-dispatch-thread';
  GContext.TransportSessionId := 'project-options-dispatch-session';
  GContext.ProjectKey := 'C:\IsolatedProjectOptionsTest\CapturedActive.dproj';
  GContext.ClientName := 'project-options-dispatch-client';
  for LIndex := Low(CToolNames) to High(CToolNames) do
  begin
    for LReadAllowed := False to True do
      for LEditAllowed := False to True do
        TestPermission(LIndex, LReadAllowed, LEditAllowed);
    TestStringTypes(LIndex, 'project');
    if LIndex > 0 then
      for LVariant := 0 to 2 do
        TestContextProject(LIndex, LVariant);
    if LIndex in [2, 3, 4] then
    begin
      TestStringTypes(LIndex, 'configuration');
      TestStringTypes(LIndex, 'platform');
    end;
    if LIndex in [3, 4] then
    begin
      TestStringTypes(LIndex, 'name');
      TestRequired(LIndex, 'configuration', False);
      TestRequired(LIndex, 'platform', True);
      TestRequired(LIndex, 'name', False);
      ExpectInvalid(LIndex, nil, CToolNames[LIndex] + '/nil-arguments');
    end;
  end;
  TestRequired(0, 'project', False);
  ExpectInvalid(0, nil, 'project_activate/nil-arguments');
  TestStringTypes(3, 'value');
  TestStringTypes(3, 'merge_mode');
  TestRequired(3, 'value', True);
  TestReadArguments;
  TestWriteArguments;
  TestSchemas;
  LArguments := TJSONObject.Create;
  try
    Reset;
    try
      DispatchProjectOptions('unrelated_tool', LArguments, GContext).Free;
      Check(False, 'unrelated tool rejected');
    except
      on E: EArgumentException do
        Check(True, 'fixture excludes unrelated dispatch');
    end;
    Check(TDAIProjectOptionsService.Calls = 0, 'unrelated tool does not reach service');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'unrelated tool does not request permission');
  finally
    LArguments.Free;
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS ProjectOptionsDispatch: ', GChecks, ' assertions');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
