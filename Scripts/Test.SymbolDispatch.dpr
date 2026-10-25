program Test.SymbolDispatch;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  DAI.SymbolDispatch.ProductionBranch,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Symbols.Service,
  h5u.DAI.Types;

const
  CNames: array[0..5] of string = ('ide_ai_status', 'project_index_status', 'project_index_build', 'project_index_delete',
    'symbols_search', 'symbols_query');
  CMethods: array[0..5] of string = ('ai', 'list', 'build', 'delete', 'search', 'query');
  CScopes: array[0..3] of string = ('project', 'group', 'delphi', 'getit');

var
  GChecks: Integer;
  GContext: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + AMessage);
end;

procedure Reset;
begin
  TDAISymbolService.Reset;
  TDAIPermissionManager.Instance.Reset;
end;

function Arguments(const ATool: Integer; const AScope: string = ''): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AScope <> '' then
    Result.AddPair('scope', AScope);
  if ATool = 4 then
    Result.AddPair('query', 'TÜbersicht');
  if ATool = 5 then
    Result.AddPair('sql', 'SELECT name FROM symbols WHERE name = :name');
end;

procedure CheckRequest(const AIndex: Integer; const ACategory: TDAIPermissionCategory; const AProject: string);
var
  LRequest: TPermissionRequest;
begin
  LRequest := TDAIPermissionManager.Instance.Requests[AIndex];
  Check(LRequest.Category = ACategory, 'the exact read/write permission category is requested');
  Check(LRequest.Context.ProjectKey = AProject, 'permission is bound to the exact source project or global scope');
  Check(LRequest.Resource = '', 'the scope is bound through the captured permission context');
  Check(LRequest.Context.ThreadId = GContext.ThreadId, 'thread identity is retained');
  Check(LRequest.Context.TransportSessionId = GContext.TransportSessionId, 'transport session is retained');
  Check(LRequest.Context.ClientName = GContext.ClientName, 'client identity is retained');
  Check(LRequest.Operation <> '', 'permission request has a human-readable operation');
end;

procedure CheckAllowed(const ATool: Integer; const AScope: string; const AOmitScope: Boolean = False; const AProjectReadAllowed: Boolean = True);
var
  LArguments, LResult: TJSONObject;
  LWrite: Boolean;
  LCount, LStride, LIndex: Integer;
  LProject: string;
  LReadCategory, LWriteCategory: TDAIPermissionCategory;
begin
  Reset;
  TDAIPermissionManager.Instance.ReadAllowed := AProjectReadAllowed;
  if AOmitScope then
    LArguments := Arguments(ATool)
  else
    LArguments := Arguments(ATool, AScope);
  try
    LResult := DispatchSymbols(UpperCase(CNames[ATool]), LArguments, GContext);
    try
      Check(LResult.GetValue<string>('method') = CMethods[ATool], 'the actual branch returns the final service response');
      Check(TDAISymbolService.Calls = 1, 'one dispatch performs exactly one operation');
      Check(TDAISymbolService.SnapshotCalls = 1, 'one immutable permission snapshot is used');
      Check(TDAISymbolService.LastScope = AScope, 'explicit or default scope reaches the service unchanged');
      Check(TDAISymbolService.LastIdentity = 'captured-owner-and-membership-identity', 'captured owner/membership identity reaches the service');
      LWrite := ATool in [2, 3];
      LStride := 1 + Ord(LWrite);
      if AScope = 'group' then
        LCount := 80
      else
        LCount := 1;
      Check(Length(TDAIPermissionManager.Instance.Requests) = LCount * LStride, 'every group member has the required permissions');
      for LIndex := 0 to LCount - 1 do
      begin
        if (AScope = 'group') or (AScope = 'project') then
        begin
          LProject := TDAISymbolService.Projects[LIndex];
          LReadCategory := pcProjectRead;
          LWriteCategory := pcProjectWrite;
        end
        else
        begin
          LProject := '';
          LReadCategory := pcReferenceRead;
          LWriteCategory := pcIDEOptions;
        end;
        CheckRequest(LIndex * LStride, LReadCategory, LProject);
        if LWrite then
          CheckRequest(LIndex * LStride + 1, LWriteCategory, LProject);
      end;
      if ATool = 4 then
      begin
        Check(TDAISymbolService.LastQuery = 'TÜbersicht', 'search query preserves Unicode');
        Check(TDAISymbolService.LastVisibility = 'all', 'default visibility is all');
        Check(TDAISymbolService.LastMaximum = 100, 'default search limit is 100');
      end;
      if ATool = 5 then
      begin
        Check(TDAISymbolService.LastQuery = LArguments.GetValue<string>('sql'), 'SQL reaches the read-only service unchanged');
        Check(TDAISymbolService.LastParameters = nil, 'omitted parameters remain absent');
        Check(TDAISymbolService.LastMaximum = 100, 'default SQL result limit is 100');
      end;
    finally
      LResult.Free;
    end;
  finally
    LArguments.Free;
  end;
end;

procedure CheckDenied(const ATool: Integer; const AScope: string; const ARead, AEdit: Boolean);
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
begin
  Reset;
  TDAIPermissionManager.Instance.ReadAllowed := ARead;
  TDAIPermissionManager.Instance.EditAllowed := AEdit;
  LArguments := Arguments(ATool, AScope);
  LResult := nil;
  LDenied := False;
  try
    try
      LResult := DispatchSymbols(CNames[ATool], LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(LDenied, 'denied read/write blocks the index operation');
    Check(LResult = nil, 'denial never produces a success response');
    Check(TDAISymbolService.Calls = 0, 'no final index service operation occurs after denial');
    Check(TDAISymbolService.SnapshotCalls = 1, 'only metadata scope capture may precede permission denial');
    if ARead then
      Check(Length(TDAIPermissionManager.Instance.Requests) = 2, 'write denial follows the read permission for that same project')
    else
      Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'read denial aborts before requesting write permission');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure CheckGroupDenial(const ATool, ADeniedMember: Integer; const ACategory: TDAIPermissionCategory);
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
  LExpectedCount, LStride: Integer;
begin
  Reset;
  TDAIPermissionManager.Instance.DeniedProject := TDAISymbolService.Projects[ADeniedMember];
  TDAIPermissionManager.Instance.DeniedCategory := ACategory;
  LArguments := Arguments(ATool, 'group');
  LResult := nil;
  LDenied := False;
  try
    try
      LResult := DispatchSymbols(CNames[ATool], LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(LDenied, 'a denied member of an 80-project group blocks the whole operation');
    Check(TDAISymbolService.Calls = 0, 'group denial prevents any index build/delete/search/query');
    LStride := 1 + Ord(ATool in [2, 3]);
    LExpectedCount := ADeniedMember * LStride + 1 + Ord(ACategory = pcProjectWrite);
    Check(Length(TDAIPermissionManager.Instance.Requests) = LExpectedCount, 'permission traversal stops at exactly the denied member');
    CheckRequest(LExpectedCount - 1, ACategory, TDAISymbolService.Projects[ADeniedMember]);
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestStatus(const ATool: Integer; const ARequestId: string; const AAllowed: Boolean);
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
begin
  Reset;
  TDAIPermissionManager.Instance.ReadAllowed := AAllowed;
  LArguments := Arguments(ATool);
  LResult := nil;
  LDenied := False;
  if ARequestId <> '' then
    LArguments.AddPair('request_id', ARequestId);
  try
    try
      LResult := DispatchSymbols(CNames[ATool], LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(not LDenied, 'status and AI metadata always allow reference reads');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'status requires one read permission');
    CheckRequest(0, pcReferenceRead, GContext.ProjectKey);
    Check(TDAISymbolService.SnapshotCalls = 0, 'status does not resolve source membership or create an index');
    Check(TDAISymbolService.Calls = 1, 'project denial never blocks public status metadata');
    if ARequestId <> '' then
    begin
      Check(TDAISymbolService.LastMethod = 'job', 'request_id polls an existing job instead of listing/building');
      Check(TDAISymbolService.LastRequestId = ARequestId, 'request identifier passes unchanged');
      Check(LResult.GetValue('errors') = nil, 'Public project job status omits private file failure details');
      Check(LResult.GetValue('error') = nil, 'Public project job status omits private general failure text');
      Check(LResult.GetValue<Integer>('error_count') = 1, 'Public status retains the metadata failure count');
      Check(LResult.GetValue<Boolean>('error_details_omitted'), 'Public status explicitly reports omitted project error details');
    end
    else
      Check(TDAISymbolService.LastMethod = CMethods[ATool], 'status routes to metadata only');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestReferenceJobDetails;
var
  LArguments, LResult: TJSONObject;
begin
  for var LScope in ['delphi', 'getit'] do
  begin
    Reset;
    TDAISymbolService.JobScope := LScope;
    TDAIPermissionManager.Instance.ReadAllowed := False;
    LArguments := TJSONObject.Create.AddPair('request_id', 'reference-job');
    try
      LResult := DispatchSymbols('project_index_status', LArguments, GContext);
      try
        Check(LResult.GetValue<TJSONArray>('errors').Count = 1, 'Reference failures remain readable under reference permissions');
        Check(LResult.GetValue<string>('error') = 'Private project failure text', 'Reference job details retain the service error text');
        Check(LResult.GetValue('error_details_omitted') = nil, 'Reference failure details are not silently redacted');
      finally
        LResult.Free;
      end;
    finally
      LArguments.Free;
    end;
  end;
end;

procedure TestArgumentsAndSnapshot;
var
  LArguments, LResult, LParameters: TJSONObject;
begin
  Reset;
  LArguments := Arguments(4, 'project');
  try
    LArguments.AddPair('visibility', 'published').AddPair('maximum_results', TJSONNumber.Create(17));
    TDAIPermissionManager.Instance.OnAuthorize :=
      procedure
      begin
        TDAISymbolService.SnapshotIdentity := 'changed-during-permission-prompt';
      end;
    LResult := DispatchSymbols('symbols_search', LArguments, GContext);
    LResult.Free;
    Check(TDAISymbolService.LastIdentity = 'captured-owner-and-membership-identity', 'identity is captured before permission prompts and never silently rebound');
    Check(TDAISymbolService.LastVisibility = 'published', 'visibility passes unchanged');
    Check(TDAISymbolService.LastMaximum = 17, 'explicit search limit passes unchanged');
    Check(TDAISymbolService.SnapshotCalls = 1, 'authorization does not re-snapshot a changed selection');
  finally
    LArguments.Free;
  end;
  Reset;
  LArguments := Arguments(5, 'getit');
  try
    LParameters := TJSONObject.Create.AddPair('name', 'TÜbersicht');
    LArguments.AddPair('parameters', LParameters).AddPair('maximum_rows', TJSONNumber.Create(23));
    LResult := DispatchSymbols('symbols_query', LArguments, GContext);
    LResult.Free;
    Check(TDAISymbolService.LastParameters = LParameters, 'parameter object reaches SQL service without conversion');
    Check(TDAISymbolService.LastMaximum = 23, 'explicit SQL row limit passes unchanged');
  finally
    LArguments.Free;
  end;
end;

procedure ExpectInvalid(const ATool: Integer; const AField: string; const AValue: TJSONValue);
var
  LArguments, LResult: TJSONObject;
  LRejected: Boolean;
begin
  Reset;
  LArguments := Arguments(ATool, 'project');
  LResult := nil;
  LRejected := False;
  try
    LArguments.RemovePair(AField).Free;
    if Assigned(AValue) then
      LArguments.AddPair(AField, AValue);
    try
      LResult := DispatchSymbols(CNames[ATool], LArguments, GContext);
    except
      on E: EArgumentException do
        LRejected := True;
    end;
    Check(LRejected, CNames[ATool] + '/' + AField + ' rejects invalid arguments');
    Check(TDAISymbolService.Calls = 0, 'invalid arguments never execute the final service operation');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

function Contains(const AValues: TJSONArray; const AText: string): Boolean;
begin
  Result := False;
  if Assigned(AValues) then
    for var LValue in AValues do
      if LValue.Value = AText then
        Exit(True);
end;

procedure TestSchemas;
var
  LTools: TJSONArray;
  LTool, LSchema, LProperties, LScope, LAnnotation: TJSONObject;
  LRequired, LEnum: TJSONArray;
begin
  LTools := ListSymbolSchemas;
  try
    Check(LTools.Count = Length(CNames), 'all six production schemas are present');
    for var LIndex := Low(CNames) to High(CNames) do
    begin
      LTool := TJSONObject(LTools.Items[LIndex]);
      Check(LTool.GetValue<string>('name') = CNames[LIndex], 'schema name matches its production dispatch branch');
      Check(LTool.GetValue<string>('description') <> '', 'each index tool has a description');
      LSchema := LTool.GetValue<TJSONObject>('inputSchema');
      Check(LSchema.GetValue<string>('type') = 'object', 'tool schema is an object');
      Check(not LSchema.GetValue<Boolean>('additionalProperties'), 'tool schema rejects unrelated arguments');
      LAnnotation := LTool.GetValue<TJSONObject>('annotations');
      Check(LAnnotation.GetValue<Boolean>('readOnlyHint') = not (LIndex in [2, 3]), 'build/delete alone are annotated as mutations');
      LProperties := LSchema.GetValue<TJSONObject>('properties', nil);
      if LIndex >= 2 then
      begin
        LScope := LProperties.GetValue<TJSONObject>('scope');
        Check(LScope.GetValue<string>('default') = 'group', 'the documented default scope is the project group');
        LEnum := LScope.GetValue<TJSONArray>('enum');
        Check(LEnum.Count = Length(CScopes), 'scope schema lists exactly the supported scopes');
        for var LName in CScopes do
          Check(Contains(LEnum, LName), 'scope schema includes ' + LName);
      end;
      if LIndex in [4, 5] then
      begin
        LRequired := LSchema.GetValue<TJSONArray>('required');
        if LIndex = 4 then
        begin
          Check(Contains(LRequired, 'query'), 'search requires an explicit query');
          LEnum := LProperties.GetValue<TJSONObject>('visibility').GetValue<TJSONArray>('enum');
          for var LVisibility in TArray<string>.Create('all', 'private', 'protected', 'public', 'published') do
            Check(Contains(LEnum, LVisibility), 'visibility schema includes ' + LVisibility);
        end
        else
        begin
          Check(Contains(LRequired, 'sql'), 'SQL tool requires an explicit SQL statement');
          Check(LProperties.GetValue<TJSONObject>('parameters').GetValue<string>('type') = 'object', 'SQL parameters are an object');
        end;
      end;
    end;
  finally
    LTools.Free;
  end;
end;

procedure Run;
begin
  GContext.ThreadId := 'index-dispatch-thread';
  GContext.TransportSessionId := 'index-dispatch-session';
  GContext.ClientName := 'index-dispatch-client';
  GContext.ProjectKey := 'C:\UnrelatedIncomingContext\Active.dproj';
  for var LTool := 2 to High(CNames) do
  begin
    for var LScope in CScopes do
    begin
      CheckAllowed(LTool, LScope);
      if (LScope = 'group') or (LScope = 'project') then
        CheckDenied(LTool, LScope, False, True)
      else
        CheckAllowed(LTool, LScope, False, False);
      if LTool in [2, 3] then
        CheckDenied(LTool, LScope, True, False);
    end;
    CheckAllowed(LTool, 'group', True);
    for var LMember in TArray<Integer>.Create(0, 39, 79) do
    begin
      CheckGroupDenial(LTool, LMember, pcProjectRead);
      if LTool in [2, 3] then
        CheckGroupDenial(LTool, LMember, pcProjectWrite);
    end;
    ExpectInvalid(LTool, 'scope', TJSONNumber.Create(42));
    ExpectInvalid(LTool, 'scope', TJSONString.Create('unknown'));
  end;
  for var LAllowed := False to True do
  begin
    TestStatus(0, '', LAllowed);
    TestStatus(1, '', LAllowed);
    TestStatus(1, 'existing-job-id', LAllowed);
  end;
  TestReferenceJobDetails;
  TestArgumentsAndSnapshot;
  ExpectInvalid(1, 'request_id', TJSONNumber.Create(42));
  ExpectInvalid(4, 'query', nil);
  ExpectInvalid(4, 'query', TJSONString.Create('  '));
  ExpectInvalid(4, 'query', TJSONBool.Create(True));
  ExpectInvalid(4, 'visibility', TJSONArray.Create);
  ExpectInvalid(5, 'sql', nil);
  ExpectInvalid(5, 'sql', TJSONString.Create(''));
  ExpectInvalid(5, 'parameters', TJSONArray.Create);
  TestSchemas;
end;

begin
  try
    Run;
    Writeln('PASS SymbolDispatch: ', GChecks, ' assertions');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
