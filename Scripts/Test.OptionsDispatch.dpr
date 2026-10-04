program Test.OptionsDispatch;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.JSON, System.SysUtils,
  DAI.OptionsDispatch.ProductionBranch,
  h5u.DAI.Options.Search, h5u.DAI.Options.Navigation,
  h5u.DAI.Permissions.Manager, h5u.DAI.Types;

const
  COpenNames: array[0..8] of string = ('scope', 'project', 'area', 'page', 'option', 'control', 'query', 'configuration', 'platform');
  COpenValues: array[0..8] of string = ('project', 'Exact Project', 'Delphi Compiler', 'Output', 'DCC_ExeOutput',
    'ExactControl', 'Ausgabepfad', 'Release', 'Win64');
  CSearchNames: array[0..2] of string = ('query', 'scope', 'project');
  CRequestId = 'exact-request-id';

var
  GChecks: Integer;
  GContext: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + ADescription);
end;

procedure Reset;
begin
  TDAIPermissionManager.Instance.Reset;
  TDAIOptionsSearchService.Reset;
  TDAIOptionsNavigationService.Reset;
  GContext.ThreadId := 'options-dispatch-thread';
  GContext.TransportSessionId := 'options-dispatch-transport';
  GContext.ProjectKey := 'C:\IsolatedOptionsDispatch\CapturedActive.dproj';
  GContext.ClientName := 'options-dispatch-client';
end;

procedure CheckNoServiceCalls;
begin
  Check(TDAIOptionsSearchService.Calls = 0, 'no final search');
  Check(TDAIOptionsNavigationService.OpenCalls = 0, 'no final open');
  Check(TDAIOptionsNavigationService.StatusCalls = 0, 'no final status');
end;

procedure CheckPermission(const AIndex: Integer; const ACategory: TDAIPermissionCategory; const AResource, AOperation: string);
var
  LRequest: TPermissionRequest;
begin
  LRequest := TDAIPermissionManager.Instance.Requests[AIndex];
  Check(LRequest.Category = ACategory, 'correct permission category/order');
  Check(LRequest.Resource = AResource, 'exact requested permission resource');
  Check(LRequest.Operation = AOperation, 'meaningful permission operation');
  Check(LRequest.Context.ThreadId = GContext.ThreadId, 'thread retained');
  Check(LRequest.Context.TransportSessionId = GContext.TransportSessionId, 'transport retained');
  Check(LRequest.Context.ProjectKey = GContext.ProjectKey, 'captured project retained');
  Check(LRequest.Context.ClientName = GContext.ClientName, 'client retained');
end;

function SearchArguments: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('query', 'Ausgabepfad');
end;

function OpenArguments: TJSONObject;
var
  LIndex: Integer;
begin
  Result := TJSONObject.Create;
  for LIndex := 0 to 8 do
    Result.AddPair(COpenNames[LIndex], COpenValues[LIndex]);
end;

procedure TestSearch(const AExplicit: Boolean; const AMaximum: Integer = 100);
var
  LArguments, LResult: TJSONObject;
  LProject: string;
begin
  Reset;
  LArguments := SearchArguments;
  LResult := nil;
  LProject := '';
  try
    if AExplicit then
    begin
      LProject := 'Exact Project';
      LArguments.AddPair('scope', 'insight');
      LArguments.AddPair('project', LProject);
      LArguments.AddPair('maximum_results', TJSONNumber.Create(AMaximum));
    end;
    LResult := DispatchOptions('OPTIONS_SEARCH', LArguments, GContext);
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'search only requests read access');
    CheckPermission(0, pcReadAccess, LProject, 'Optionsnamen und IDE-Insight-Metadaten durchsuchen');
    Check(TDAIOptionsSearchService.Calls = 1, 'one final search');
    Check(TDAIOptionsSearchService.PermissionCount = 1, 'read permission precedes search');
    Check(TDAIOptionsSearchService.Query = 'Ausgabepfad', 'query forwarded exactly');
    Check(TDAIOptionsSearchService.Project = LProject, 'project selector forwarded exactly');
    if AExplicit then
      Check(TDAIOptionsSearchService.Scope = 'insight', 'explicit scope forwarded')
    else
      Check(TDAIOptionsSearchService.Scope = 'all', 'default scope all');
    Check(TDAIOptionsSearchService.MaximumResults = AMaximum, 'maximum result count/default forwarded');
    Check(TDAIOptionsNavigationService.OpenCalls = 0, 'search never opens UI');
    Check(TDAIOptionsNavigationService.StatusCalls = 0, 'search never calls navigation status');
    Check(LResult = TDAIOptionsSearchService.LastResponse, 'search JSON object returned unchanged');
    Check(LResult.GetValue('catalog_complete') is TJSONNull, 'unknown catalog completeness preserved');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestOpen(const AExplicit: Boolean);
var
  LArguments, LResult: TJSONObject;
  LRequest: TDAIOptionsNavigationRequest;
  LProject: string;
begin
  Reset;
  LArguments := nil;
  LResult := nil;
  LProject := GContext.ProjectKey;
  try
    if AExplicit then
    begin
      LArguments := OpenArguments;
      LProject := 'Exact Project';
    end;
    LResult := DispatchOptions('OPTIONS_OPEN', LArguments, GContext);
    Check(Length(TDAIPermissionManager.Instance.Requests) = 3, 'opening checks read/edit/execute');
    CheckPermission(0, pcReadAccess, LProject, 'Ziel der Optionsnavigation lesen');
    CheckPermission(1, pcEditInsideIDE, LProject, 'Optionsdialog öffnen und Option auswählen');
    CheckPermission(2, pcExecute, LProject, 'Optionsnavigation über die IDE ausführen');
    Check(TDAIOptionsNavigationService.OpenCalls = 1, 'one final open');
    Check(TDAIOptionsNavigationService.OpenPermissionCount = 3, 'all permissions precede opening');
    Check(TDAIOptionsNavigationService.StatusCalls = 0, 'opening does not dispatch poll');
    Check(TDAIOptionsSearchService.Calls = 0, 'opening is separate from catalog search');
    LRequest := TDAIOptionsNavigationService.LastRequest;
    Check(LRequest.Scope = 'project', 'default/explicit project scope');
    Check(LRequest.Project = LProject, 'exact project selector/default');
    if AExplicit then
    begin
      Check(LRequest.Area = COpenValues[2], 'area forwarded');
      Check(LRequest.Page = COpenValues[3], 'page forwarded');
      Check(LRequest.Option = COpenValues[4], 'option forwarded');
      Check(LRequest.Control = COpenValues[5], 'control forwarded');
      Check(LRequest.Query = COpenValues[6], 'query forwarded');
      Check(LRequest.Configuration = COpenValues[7], 'configuration forwarded');
      Check(LRequest.Platform = COpenValues[8], 'platform forwarded');
    end
    else
    begin
      Check(LRequest.Area = '', 'default area empty');
      Check(LRequest.Page = '', 'default page empty');
      Check(LRequest.Option = '', 'default option empty');
      Check(LRequest.Control = '', 'default control empty');
      Check(LRequest.Query = '', 'default query empty');
      Check(LRequest.Configuration = '', 'default configuration empty');
      Check(LRequest.Platform = '', 'default platform empty');
    end;
    Check(LResult = TDAIOptionsNavigationService.LastResponse, 'open JSON object returned unchanged');
    Check(LResult.GetValue<string>('state') = 'unsupported', 'unsupported service state preserved');
    Check(not LResult.GetValue<Boolean>('option_focused'), 'false focus result preserved');
    Check(LResult.GetValue<string>('request_id') = 'actual-final-request-id', 'actual request ID preserved');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestOtherScope(const AScope: string);
var
  LArguments, LResult: TJSONObject;
begin
  Reset;
  LArguments := TJSONObject.Create;
  LResult := nil;
  try
    LArguments.AddPair('scope', AScope);
    LArguments.AddPair('query', 'Ausgabepfad');
    LResult := DispatchOptions('options_open', LArguments, GContext);
    Check(Length(TDAIPermissionManager.Instance.Requests) = 3, 'IDE/Insight opening also requires all permissions');
    CheckPermission(0, pcReadAccess, '', 'Ziel der Optionsnavigation lesen');
    CheckPermission(1, pcEditInsideIDE, '', 'Optionsdialog öffnen und Option auswählen');
    CheckPermission(2, pcExecute, '', 'Optionsnavigation über die IDE ausführen');
    Check(TDAIOptionsNavigationService.LastRequest.Project = '', 'IDE/Insight do not bind active project selector');
    Check(TDAIOptionsNavigationService.LastRequest.Scope = AScope, 'IDE/Insight exact scope');
    Check(TDAIOptionsNavigationService.LastRequest.Query = 'Ausgabepfad', 'IDE/Insight exact query');
    Check(TDAIOptionsNavigationService.OpenCalls = 1, 'one final IDE/Insight open');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestNoActiveContext;
var
  LResult: TJSONObject;
  LRejected: Boolean;
begin
  Reset;
  GContext.ProjectKey := '';
  LResult := nil;
  LRejected := False;
  try
    try
      LResult := DispatchOptions('options_open', nil, GContext);
    except
      on E: EArgumentException do LRejected := True;
    end;
    Check(LRejected, 'project-default opening without active context rejected');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'missing active context rejected before permission');
    CheckNoServiceCalls;
  finally LResult.Free end;
end;

procedure TestStatus;
var
  LArguments, LResult: TJSONObject;
begin
  Reset;
  LArguments := TJSONObject.Create;
  LResult := nil;
  try
    LArguments.AddPair('request_id', CRequestId);
    LResult := DispatchOptions('options_open', LArguments, GContext);
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'status only checks read');
    CheckPermission(0, pcReadAccess, CRequestId, 'Status der Optionsnavigation lesen');
    Check(TDAIOptionsNavigationService.LastRequestId = CRequestId, 'request ID forwarded exactly');
    Check(TDAIOptionsNavigationService.StatusCalls = 1, 'one final status');
    Check(TDAIOptionsNavigationService.StatusPermissionCount = 1, 'read precedes status');
    Check(TDAIOptionsNavigationService.OpenCalls = 0, 'status never opens UI');
    Check(TDAIOptionsSearchService.Calls = 0, 'status never catalog-searches');
    Check(LResult = TDAIOptionsNavigationService.LastResponse, 'status JSON object preserved');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestDenied(const AMode, AIndex: Integer);
var
  LArguments, LResult: TJSONObject;
  LTool: string;
  LDenied: Boolean;
begin
  Reset;
  TDAIPermissionManager.Instance.DeniedRequestIndex := AIndex;
  LTool := 'options_open';
  if AMode = 0 then
  begin
    LTool := 'options_search';
    LArguments := SearchArguments;
  end
  else if AMode = 1 then
    LArguments := OpenArguments
  else
  begin
    LArguments := TJSONObject.Create;
    LArguments.AddPair('request_id', CRequestId);
  end;
  LResult := nil;
  LDenied := False;
  try
    try
      LResult := DispatchOptions(LTool, LArguments, GContext);
    except
      on E: EAbort do LDenied := True;
    end;
    Check(LDenied, 'denied permission aborts');
    Check(not Assigned(LResult), 'denied permission has no success response');
    Check(Length(TDAIPermissionManager.Instance.Requests) = AIndex + 1, 'stops at denied gate');
    CheckNoServiceCalls;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

function WrongValue(const AIndex: Integer): TJSONValue;
begin
  case AIndex of
    0: Result := TJSONNull.Create;
    1: Result := TJSONBool.Create(True);
    2: Result := TJSONNumber.Create(42);
    3: Result := TJSONArray.Create;
  else
    Result := TJSONObject.Create;
  end;
end;

procedure Reject(const ATool: string; const AArguments: TJSONObject);
var
  LRejected: Boolean;
  LResult: TJSONObject;
begin
  Reset;
  LRejected := False;
  LResult := nil;
  try
    try
      LResult := DispatchOptions(ATool, AArguments, GContext);
    except
      on E: EArgumentException do LRejected := True;
    end;
    Check(LRejected, 'invalid arguments rejected');
    Check(not Assigned(LResult), 'invalid arguments have no success result');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'validation precedes permission');
    CheckNoServiceCalls;
  finally
    LResult.Free;
  end;
end;

procedure TestInvalidArguments;
var
  LArguments: TJSONObject;
  LIndex, LVariant: Integer;
  LName: string;
begin
  Reject('options_search', nil);
  for LIndex := 0 to 1 do
  begin
    LArguments := TJSONObject.Create;
    try
      if LIndex = 0 then LArguments.AddPair('query', '') else LArguments.AddPair('query', '   ');
      Reject('options_search', LArguments);
    finally
      LArguments.Free;
    end;
  end;
  for LVariant := 0 to 4 do
  begin
    for LName in CSearchNames do
    begin
      LArguments := SearchArguments;
      try
        LArguments.RemovePair(LName).Free;
        LArguments.AddPair(LName, WrongValue(LVariant));
        Reject('options_search', LArguments);
      finally LArguments.Free end;
    end;
    for LName in COpenNames do
    begin
      LArguments := TJSONObject.Create;
      try
        LArguments.AddPair(LName, WrongValue(LVariant));
        Reject('options_open', LArguments);
      finally LArguments.Free end;
    end;
    LArguments := TJSONObject.Create;
    try
      LArguments.AddPair('request_id', WrongValue(LVariant));
      Reject('options_open', LArguments);
    finally LArguments.Free end;
  end;
  for LName in COpenNames do
  begin
    LArguments := TJSONObject.Create;
    try
      LArguments.AddPair('request_id', CRequestId);
      LArguments.AddPair(LName, TJSONNull.Create);
      Reject('options_open', LArguments);
    finally LArguments.Free end;
  end;
  for LIndex := 0 to 1 do
  begin
    LArguments := TJSONObject.Create;
    try
      if LIndex = 0 then LArguments.AddPair('request_id', '') else LArguments.AddPair('request_id', '   ');
      Reject('options_open', LArguments);
    finally LArguments.Free end;
  end;
  for LVariant := 0 to 8 do
  begin
    LArguments := SearchArguments;
    try
      case LVariant of
        0: LArguments.AddPair('maximum_results', TJSONNull.Create);
        1: LArguments.AddPair('maximum_results', TJSONString.Create('100'));
        2: LArguments.AddPair('maximum_results', TJSONBool.Create(True));
        3: LArguments.AddPair('maximum_results', TJSONArray.Create);
        4: LArguments.AddPair('maximum_results', TJSONObject.Create);
        5: LArguments.AddPair('maximum_results', TJSONNumber.Create('1.5'));
        6: LArguments.AddPair('maximum_results', TJSONNumber.Create(0));
        7: LArguments.AddPair('maximum_results', TJSONNumber.Create(501));
        8: LArguments.AddPair('maximum_results', TJSONNumber.Create('2147483648'));
      end;
      Reject('options_search', LArguments);
    finally LArguments.Free end;
  end;
end;

procedure TestSchemas;
var
  LCatalog, LRequired, LEnum: TJSONArray;
  LTool, LSchema, LProperties, LProperty: TJSONObject;
  LIndex: Integer;
  LName: string;
begin
  LCatalog := ListOptionsSchemas;
  try
    Check(LCatalog.Count = 2, 'two actual schemas extracted');
    for LIndex := 0 to 1 do
    begin
      LTool := TJSONObject(LCatalog.Items[LIndex]);
      if LIndex = 0 then Check(LTool.GetValue<string>('name') = 'options_search', 'search tool name')
      else Check(LTool.GetValue<string>('name') = 'options_open', 'open tool name');
      Check(LTool.GetValue<string>('description') <> '', 'tool description');
      Check(LTool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint') = (LIndex = 0), 'correct readOnly hint');
      LSchema := LTool.GetValue<TJSONObject>('inputSchema');
      Check(LSchema.GetValue<string>('type') = 'object', 'object schema');
      Check(not LSchema.GetValue<Boolean>('additionalProperties'), 'no extra properties');
      LProperties := LSchema.GetValue<TJSONObject>('properties');
      if LIndex = 0 then
      begin
        Check(LProperties.Count = 4, 'search schema four arguments');
        for LName in CSearchNames do
          Check(LProperties.GetValue<TJSONObject>(LName).GetValue<string>('type') = 'string', 'search string argument');
        LProperty := LProperties.GetValue<TJSONObject>('maximum_results');
        Check(LProperty.GetValue<string>('type') = 'integer', 'result limit integer');
        Check(LProperty.GetValue<Integer>('minimum') = 1, 'result minimum');
        Check(LProperty.GetValue<Integer>('maximum') = 500, 'result maximum');
        LRequired := LSchema.GetValue<TJSONArray>('required');
        Check(LRequired.Count = 1, 'query alone required');
        Check(LRequired.Items[0].Value = 'query', 'query explicitly required');
        LEnum := LProperties.GetValue<TJSONObject>('scope').GetValue<TJSONArray>('enum');
        Check(LEnum.ToJSON = '["all","ide","project","insight"]', 'search scopes');
      end
      else
      begin
        Check(LProperties.Count = 10, 'open schema nine selectors plus request ID');
        for LName in COpenNames do
          Check(LProperties.GetValue<TJSONObject>(LName).GetValue<string>('type') = 'string', 'open string argument');
        Check(LProperties.GetValue<TJSONObject>('request_id').GetValue<string>('type') = 'string', 'request ID string');
        LEnum := LProperties.GetValue<TJSONObject>('scope').GetValue<TJSONArray>('enum');
        Check(LEnum.ToJSON = '["project","ide","insight"]', 'open scopes');
        Check(not Assigned(LProperties.GetValue('result_index')), 'no invented popup result index');
      end;
    end;
  finally LCatalog.Free end;
end;

begin
  try
    TestSearch(False);
    TestSearch(True, 1);
    TestSearch(True, 500);
    TestOpen(False);
    TestOpen(True);
    TestOtherScope('ide');
    TestOtherScope('insight');
    TestNoActiveContext;
    TestStatus;
    TestDenied(0, 0);
    TestDenied(1, 0);
    TestDenied(1, 1);
    TestDenied(1, 2);
    TestDenied(2, 0);
    TestInvalidArguments;
    TestSchemas;
    Writeln('PASS OptionsDispatch: ', GChecks, ' assertions');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
