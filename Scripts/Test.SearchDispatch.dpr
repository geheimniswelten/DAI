program Test.SearchDispatch;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  ToolsAPI,
  DAI.SearchDispatch.ProductionBranch,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Search,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Types;

const
  CToolNames: array[0..3] of string = ('source_search', 'directory_files_list', 'project_directory_files_list', 'reference_files_list');
  CDirectory = 'C:\IsolatedSearchDispatch\Sources';
  CProject = 'C:\IsolatedSearchDispatch\Project\Example.dproj';
  CFilenameRegex = '^h5u\.DAI\..*\.pas$';
  CQuery = 'T(Button|Edit)';

var
  GChecks: Integer;
  GContext: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + ADescription);
end;

procedure Reset(const AReadAllowed: Boolean = True);
begin
  TDAISourceSearchService.Reset;
  TDAIFileService.Reset;
  TDAIOTA.Reset;
  TDAIOTA.Project := TTestProject.Create(CProject, nil);
  TDAIPermissionManager.Instance.Reset(AReadAllowed, False);
end;

function ArgumentsFor(const AToolIndex: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  case AToolIndex of
    0: Result.AddPair('query', CQuery);
    2: Result.AddPair('project', 'ExplicitProject');
  else
    Result.AddPair('directory', CDirectory);
  end;
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

function NonBooleanValue(const AIndex: Integer): TJSONValue;
begin
  if AIndex = 1 then
    Result := TJSONString.Create('true')
  else
    Result := NonStringValue(AIndex);
end;

procedure CheckPermission(const AToolIndex: Integer);
var
  LRequest: TPermissionRequest;
begin
  Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'one permission request per single-project search');
  LRequest := TDAIPermissionManager.Instance.Requests[0];
  Check(LRequest.Category = pcReadAccess, 'all search tools request read access');
  Check(LRequest.Operation <> '', 'permission includes meaningful operation');
  if AToolIndex = 2 then
    Check(LRequest.Resource = 'ExplicitProject', 'project-directory permission targets requested project')
  else if AToolIndex <> 0 then
    Check(LRequest.Resource = CDirectory, 'directory permission targets exact requested directory')
  else
    Check(LRequest.Resource = '', 'default source search has no explicit directory');
  Check(LRequest.Context.ThreadId = GContext.ThreadId, 'thread context retained');
  Check(LRequest.Context.TransportSessionId = GContext.TransportSessionId, 'transport context retained');
  Check(LRequest.Context.ProjectKey = GContext.ProjectKey, 'project context retained');
  Check(LRequest.Context.ClientName = GContext.ClientName, 'client context retained');
end;

procedure CheckServiceResponse(const AToolIndex: Integer; const AResult: TJSONObject);
begin
  if AToolIndex = 0 then
    Check(AResult.GetValue<string>('service_response') = 'final-source-service-response', 'source service response returned unchanged')
  else
  begin
    Check(AResult.GetValue<TJSONArray>('files').Count = 1, 'directory result contains returned array');
    Check(AResult.GetValue<TJSONArray>('files').Items[0].Value = 'final-directory-service-response', 'directory service response preserved');
  end;
end;

procedure TestPermission(const AToolIndex: Integer; const AReadAllowed: Boolean);
var
  LArguments: TJSONObject;
  LDenied: Boolean;
  LResult: TJSONObject;
begin
  Reset(AReadAllowed);
  LArguments := ArgumentsFor(AToolIndex);
  LResult := nil;
  LDenied := False;
  try
    try
      LResult := DispatchSearch(UpperCase(CToolNames[AToolIndex]), LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    CheckPermission(AToolIndex);
    Check(LDenied = not AReadAllowed, 'denied read access aborts request');
    Check(Assigned(LResult) = AReadAllowed, 'denied read access cannot produce success');
    if AToolIndex = 0 then
    begin
      Check(TDAISourceSearchService.SearchCalls = Ord(AReadAllowed), 'source text reads occur only after read permission');
      Check(TDAIFileService.Calls = 0, 'source tool does not dispatch directory listing');
    end
    else
    begin
      Check(TDAIFileService.Calls = Ord(AReadAllowed), 'directory reads occur only after read permission');
      Check(TDAISourceSearchService.SearchCalls = 0, 'directory tool does not dispatch source search');
      if AToolIndex = 2 then
        Check(TDAIOTA.Calls = Ord(AReadAllowed), 'project lookup occurs only after read permission');
    end;
    if AReadAllowed then
      CheckServiceResponse(AToolIndex, LResult);
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestDefaults(const AToolIndex: Integer);
var
  LArguments: TJSONObject;
  LResult: TJSONObject;
begin
  Reset;
  LArguments := ArgumentsFor(AToolIndex);
  LResult := nil;
  try
    LResult := DispatchSearch(CToolNames[AToolIndex], LArguments, GContext);
    if AToolIndex = 0 then
    begin
      Check(not TDAISourceSearchService.LastOptions.UseRegex, 'source query remains literal by default');
      Check(TDAISourceSearchService.LastOptions.FilenameRegex = '', 'default source filename has no RegEx filter');
      Check(not TDAISourceSearchService.LastOptions.CaseSensitive, 'source case default false');
      Check(not TDAISourceSearchService.LastOptions.WholeWord, 'source whole-word default false');
      Check(TDAISourceSearchService.LastOptions.InterfacesOnly, 'source interface default retained');
      Check(TDAISourceSearchService.LastOptions.MaximumResults = 200, 'source default result limit retained');
      Check(TDAISourceSearchService.LastOptions.MaximumFiles = 10000, 'source default file limit retained');
      Check(TDAISourceSearchService.LastOptions.TimeoutMs = 5000, 'source default timeout retained');
      Check(TDAISourceSearchService.LastScope = 'all', 'source default scope retained');
      Check(TDAISourceSearchService.LastPlan.PreparationMs = 7, 'prepared production plan forwarded intact');
    end
    else
    begin
      Check(TDAIFileService.LastSearchPattern = '*', 'directory default wildcard retained');
      Check(TDAIFileService.LastRecursive, 'directory recursive default retained');
      Check(TDAIFileService.LastMaximumCount = 5000, 'directory count default retained');
      Check(TDAIFileService.LastFilenameRegex = '', 'default directory filename has no RegEx filter');
      Check(TDAIFileService.LastContentQuery = '', 'default directory has no content filter');
      Check(not TDAIFileService.LastContentUseRegex, 'directory content query literal by default');
      Check(not TDAIFileService.LastCaseSensitive, 'directory case default false');
      Check(not TDAIFileService.LastWholeWord, 'directory whole-word default false');
      if AToolIndex = 2 then
      begin
        Check(TDAIFileService.LastDirectory = TPath.GetDirectoryName(CProject), 'project lookup provides actual project directory');
        Check(TDAIOTA.LastProject = 'ExplicitProject', 'project lookup receives exact requested project');
      end
      else
        Check(TDAIFileService.LastDirectory = CDirectory, 'directory argument forwarded intact');
    end;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestExplicitFilters(const AToolIndex: Integer);
var
  LArguments: TJSONObject;
  LPatterns: TJSONArray;
  LResult: TJSONObject;
  LVariant: Boolean;
begin
  for LVariant := False to True do
  begin
    Reset;
    LArguments := ArgumentsFor(AToolIndex);
    LResult := nil;
    try
      LArguments.AddPair('filename_regex', CFilenameRegex);
      LArguments.AddPair('case_sensitive', TJSONBool.Create(LVariant));
      LArguments.AddPair('whole_word', TJSONBool.Create(LVariant));
      if AToolIndex = 0 then
      begin
        LArguments.AddPair('use_regex', TJSONBool.Create(LVariant));
        LArguments.AddPair('interfaces_only', TJSONBool.Create(False));
        LArguments.AddPair('scope', 'project');
        LArguments.AddPair('project', 'SelectedProject');
        LArguments.AddPair('directory', CDirectory);
        LArguments.AddPair('maximum_results', TJSONNumber.Create(73));
        LArguments.AddPair('maximum_files', TJSONNumber.Create(321));
        LArguments.AddPair('timeout_ms', TJSONNumber.Create(1234));
        LPatterns := TJSONArray.Create;
        LPatterns.Add('*.pas');
        LPatterns.Add('*.inc');
        LArguments.AddPair('file_patterns', LPatterns);
      end
      else
      begin
        LArguments.AddPair('content_query', CQuery);
        LArguments.AddPair('content_use_regex', TJSONBool.Create(LVariant));
        LArguments.AddPair('search_pattern', '*.pas');
        LArguments.AddPair('recursive', TJSONBool.Create(False));
        LArguments.AddPair('maximum_count', TJSONNumber.Create(42));
      end;
      LResult := DispatchSearch(CToolNames[AToolIndex], LArguments, GContext);
      if AToolIndex = 0 then
      begin
        Check(TDAISourceSearchService.LastQuery = CQuery, 'source RegEx query forwarded without modification');
        Check(TDAISourceSearchService.LastOptions.FilenameRegex = CFilenameRegex, 'source filename RegEx forwarded without modification');
        Check(TDAISourceSearchService.LastOptions.UseRegex = LVariant, 'source RegEx flag forwarded exactly');
        Check(TDAISourceSearchService.LastOptions.CaseSensitive = LVariant, 'source case flag forwarded exactly');
        Check(TDAISourceSearchService.LastOptions.WholeWord = LVariant, 'source whole-word flag forwarded exactly');
        Check(not TDAISourceSearchService.LastOptions.InterfacesOnly, 'full source text request forwarded');
        Check(Length(TDAISourceSearchService.LastOptions.FilePatterns) = 2, 'original source patterns retained');
        Check(TDAISourceSearchService.LastOptions.FilePatterns[1] = '*.inc', 'original source pattern value retained');
        Check(TDAISourceSearchService.LastOptions.MaximumResults = 73, 'explicit source result limit');
        Check(TDAISourceSearchService.LastOptions.MaximumFiles = 321, 'explicit source file limit');
        Check(TDAISourceSearchService.LastOptions.TimeoutMs = 1234, 'explicit source timeout');
        Check(TDAISourceSearchService.LastTimeoutMs = 1234, 'preparation receives explicit source timeout');
        Check(TDAISourceSearchService.LastScope = 'project', 'preparation receives explicit scope');
        Check(TDAISourceSearchService.LastProject = 'SelectedProject', 'preparation receives explicit project');
        Check(TDAISourceSearchService.LastDirectory = CDirectory, 'preparation receives explicit directory');
      end
      else
      begin
        Check(TDAIFileService.LastFilenameRegex = CFilenameRegex, 'directory filename RegEx forwarded without modification');
        Check(TDAIFileService.LastContentQuery = CQuery, 'directory content query forwarded without modification');
        Check(TDAIFileService.LastContentUseRegex = LVariant, 'directory content RegEx flag forwarded exactly');
        Check(TDAIFileService.LastCaseSensitive = LVariant, 'directory case flag forwarded exactly');
        Check(TDAIFileService.LastWholeWord = LVariant, 'directory whole-word flag forwarded exactly');
        Check(TDAIFileService.LastSearchPattern = '*.pas', 'original directory wildcard retained with new filters');
        Check(not TDAIFileService.LastRecursive, 'explicit directory nonrecursive request retained');
        Check(TDAIFileService.LastMaximumCount = 42, 'explicit directory count retained');
      end;
      CheckServiceResponse(AToolIndex, LResult);
    finally
      LResult.Free;
      LArguments.Free;
    end;
  end;
end;

procedure TestArgumentType(const AToolIndex: Integer; const AName: string; const ABoolean: Boolean);
var
  LArguments: TJSONObject;
  LRejected: Boolean;
  LResult: TJSONObject;
  LVariant: Integer;
begin
  for LVariant := 0 to 4 do
  begin
    Reset;
    LArguments := ArgumentsFor(AToolIndex);
    LResult := nil;
    LRejected := False;
    try
      if ABoolean then
        LArguments.AddPair(AName, NonBooleanValue(LVariant))
      else
        LArguments.AddPair(AName, NonStringValue(LVariant));
      try
        LResult := DispatchSearch(CToolNames[AToolIndex], LArguments, GContext);
      except
        on E: EArgumentException do
          LRejected := True;
      end;
      Check(LRejected, CToolNames[AToolIndex] + '/' + AName + '/nonmatching JSON type rejected');
      Check(not Assigned(LResult), 'invalid filter argument has no success response');
      Check(TDAISourceSearchService.SearchCalls = 0, 'invalid filter never reaches final source search');
      Check(TDAIFileService.Calls = 0, 'invalid filter never reaches final directory service');
      if AToolIndex = 0 then
      begin
        Check(TDAISourceSearchService.PrepareCalls = 0, 'invalid new source filters rejected before preparation');
        Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'invalid new source filters rejected before permission');
      end
      else
        Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'directory dispatch preserves read permission gating');
    finally
      LResult.Free;
      LArguments.Free;
    end;
  end;
end;

procedure TestProjectPermissions;
const
  CSecondProject = 'C:\IsolatedSearchDispatch\Second.dproj';
  CDeniedProject = 'C:\IsolatedSearchDispatch\Denied.dproj';
var
  LArguments: TJSONObject;
  LDenied: Boolean;
  LResult: TJSONObject;
begin
  Reset;
  LArguments := ArgumentsFor(0);
  LResult := nil;
  try
    TDAISourceSearchService.PreparedProjectKeys := [LowerCase(GContext.ProjectKey), CSecondProject];
    LResult := DispatchSearch('source_search', LArguments, GContext);
    Check(Length(TDAIPermissionManager.Instance.Requests) = 2, 'source search checks each additional affected project');
    Check(TDAIPermissionManager.Instance.Requests[1].Context.ProjectKey = CSecondProject, 'additional project permission context');
    Check(TDAIPermissionManager.Instance.Requests[1].Resource = CSecondProject, 'additional project permission resource');
    Check(TDAISourceSearchService.SearchCalls = 1, 'permitted affected projects reach source service');
    LResult.Free;
    LResult := nil;
    Reset;
    TDAISourceSearchService.PreparedProjectKeys := [CSecondProject, CDeniedProject];
    TDAIPermissionManager.Instance.DeniedProjectKey := CDeniedProject;
    LDenied := False;
    try
      LResult := DispatchSearch('source_search', LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(LDenied, 'one denied affected project aborts whole source search');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 3, 'all permissions up to denied affected project evaluated');
    Check(TDAISourceSearchService.SearchCalls = 0, 'denied affected project prevents source content access');
  finally
    LResult.Free;
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

procedure CheckProperty(const AProperties: TJSONObject; const AName, AType: string; const AFalseDefault: Boolean = False);
var
  LProperty: TJSONObject;
begin
  LProperty := AProperties.GetValue<TJSONObject>(AName);
  Check(Assigned(LProperty), 'schema includes ' + AName);
  Check(LProperty.GetValue<string>('type') = AType, 'schema type for ' + AName);
  if AFalseDefault then
    Check(not LProperty.GetValue<Boolean>('default'), 'schema false default for ' + AName);
end;

procedure TestSchemas;
var
  LCatalog: TJSONArray;
  LIndex: Integer;
  LProperties, LSchema, LTool: TJSONObject;
  LRequired: TJSONArray;
begin
  LCatalog := ListSearchSchemas;
  try
    Check(LCatalog.Count = Length(CToolNames), 'all four actual production schemas extracted');
    for LIndex := 0 to LCatalog.Count - 1 do
    begin
      LTool := TJSONObject(LCatalog.Items[LIndex]);
      Check(LTool.GetValue<string>('name') = CToolNames[LIndex], 'schema exposes expected tool name');
      Check(LTool.GetValue<string>('description') <> '', 'schema has description');
      Check(LTool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint'), 'search schema is read only');
      LSchema := LTool.GetValue<TJSONObject>('inputSchema');
      Check(LSchema.GetValue<string>('type') = 'object', 'search input schema is object');
      Check(not LSchema.GetValue<Boolean>('additionalProperties'), 'schema rejects undeclared properties');
      LProperties := LSchema.GetValue<TJSONObject>('properties');
      CheckProperty(LProperties, 'filename_regex', 'string');
      Check(LProperties.GetValue<TJSONObject>('filename_regex').GetValue<Integer>('maxLength') = 256, 'filename RegEx schema bounded');
      CheckProperty(LProperties, 'case_sensitive', 'boolean', LIndex <> 0);
      CheckProperty(LProperties, 'whole_word', 'boolean', LIndex <> 0);
      LRequired := LSchema.GetValue('required') as TJSONArray;
      if LIndex = 0 then
      begin
        Check(LRequired.Count = 1, 'source search requires only query');
        Check(StringArrayContains(LRequired, 'query'), 'source query required');
        CheckProperty(LProperties, 'query', 'string');
        CheckProperty(LProperties, 'use_regex', 'boolean', True);
        CheckProperty(LProperties, 'interfaces_only', 'boolean');
        Check(LProperties.GetValue<TJSONObject>('interfaces_only').GetValue<Boolean>('default'), 'source interface schema default true');
        Check(not Assigned(LProperties.GetValue('content_query')), 'source search uses query rather than content-filter alias');
        Check(LProperties.GetValue<TJSONObject>('query').GetValue<Integer>('minLength') = 1, 'source query nonempty schema');
        Check(LProperties.GetValue<TJSONObject>('query').GetValue<Integer>('maxLength') = 256, 'source query schema bounded');
      end
      else
      begin
        CheckProperty(LProperties, 'content_query', 'string');
        CheckProperty(LProperties, 'content_use_regex', 'boolean', True);
        Check(LProperties.GetValue<TJSONObject>('content_query').GetValue<Integer>('maxLength') = 256, 'content query schema bounded');
        CheckProperty(LProperties, 'search_pattern', 'string');
        Check(not Assigned(LProperties.GetValue('use_regex')), 'directory content uses explicit content_use_regex flag');
        if LIndex = 2 then
        begin
          CheckProperty(LProperties, 'project', 'string');
          if Assigned(LRequired) then
            Check(LRequired.Count = 0, 'project-directory defaults to active project')
          else
            Check(True, 'project-directory defaults to active project');
        end
        else
        begin
          CheckProperty(LProperties, 'directory', 'string');
          Check(LRequired.Count = 1, 'directory tool requires only directory');
          Check(StringArrayContains(LRequired, 'directory'), 'directory explicitly required');
        end;
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
begin
  GContext.ThreadId := 'search-dispatch-thread';
  GContext.TransportSessionId := 'search-dispatch-session';
  GContext.ProjectKey := 'C:\IsolatedSearchDispatch\CapturedActive.dproj';
  GContext.ClientName := 'search-dispatch-client';
  for LIndex := Low(CToolNames) to High(CToolNames) do
  begin
    TestPermission(LIndex, False);
    TestPermission(LIndex, True);
    TestDefaults(LIndex);
    TestExplicitFilters(LIndex);
    TestArgumentType(LIndex, 'filename_regex', False);
    if LIndex = 0 then
      TestArgumentType(LIndex, 'use_regex', True)
    else
    begin
      TestArgumentType(LIndex, 'content_query', False);
      TestArgumentType(LIndex, 'content_use_regex', True);
      TestArgumentType(LIndex, 'case_sensitive', True);
      TestArgumentType(LIndex, 'whole_word', True);
    end;
  end;
  TestProjectPermissions;
  TestSchemas;
  Reset;
  LArguments := ArgumentsFor(2);
  try
    TDAIOTA.Project := nil;
    try
      DispatchSearch('project_directory_files_list', LArguments, GContext).Free;
      Check(False, 'missing project rejected');
    except
      on E: EArgumentException do
        Check(True, 'missing project rejected');
    end;
    Check(TDAIFileService.Calls = 0, 'missing project does not dispatch directory read');
  finally
    LArguments.Free;
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS SearchDispatch: ', GChecks, ' assertions');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
