program Test.IndexHints;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  DAI.IndexHints.ProductionBranch,
  h5u.DAI.Consts,
  h5u.DAI.Lifecycle.Policy,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings,
  h5u.DAI.Symbols.Service,
  h5u.DAI.Types;

const
  CActive = 'C:\IndexHintsFixture\Active.dproj';
  CInactive = 'C:\IndexHintsFixture\Inactive.dproj';
  CThird = 'C:\IndexHintsFixture\Third.dproj';

var
  GChecks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise EInvalidOperation.Create(AMessage);
end;

function Context: TDAIRequestContext;
begin
  Result := Default(TDAIRequestContext);
  Result.ProjectKey := CActive;
  Result.ThreadId := 'fixture-chat';
  Result.TransportSessionId := 'fixture-transport';
  Result.ClientName := 'Fixture client';
end;

procedure Reset;
begin
  TDAISymbolService.Reset;
  TDAIPermissionManager.Instance.Reset;
  TDAIOTA.ActiveFileName := CActive;
  TDAIFileService.Calls := 0;
  FreeAndNil(TDAIFileService.Rows);
  TDAIFileService.Rows := TJSONArray.Create;
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Active').AddPair('file', CActive)
    .AddPair('active', TJSONBool.Create(True)).AddPair('configuration', 'Debug').AddPair('platform', 'Win32')
    .AddPair('framework_type', 'VCL').AddPair('output_type', 'EXE').AddPair('sentinel', 'original-active-metadata'));
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Inactive').AddPair('file', CInactive)
    .AddPair('active', TJSONBool.Create(False)).AddPair('configuration', 'Release').AddPair('platform', 'Win64')
    .AddPair('framework_type', 'FMX').AddPair('output_type', 'DLL').AddPair('sentinel', 'original-inactive-metadata'));
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Third').AddPair('file', CThird)
    .AddPair('active', TJSONBool.Create(False)).AddPair('configuration', 'Release').AddPair('platform', 'Win32')
    .AddPair('framework_type', TJSONNull.Create).AddPair('output_type', 'Package')
    .AddPair('package', TJSONObject.Create.AddPair('description', 'Preserve this package metadata')));
  TDAIRuntime.ServerActive := True;
  TDAIRuntime.ServerPort := 7344;
end;

function Dispatch(const AName: string): TJSONObject;
begin
  Result := DispatchMetadata(AName, nil, Context);
end;

procedure CheckReadMetadataPermission;
begin
  Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'A metadata tool asks for exactly its existing metadata permission');
  Check(TDAIPermissionManager.Instance.Requests[0] = pcReferenceRead, 'Index hints do not add project read/write or IDE-edit permissions');
end;

procedure CheckContextSummary(const AResult: TJSONObject);
var
  LIndexes: TJSONObject;
begin
  LIndexes := AResult.GetValue<TJSONObject>('indexes');
  Check(Assigned(LIndexes), 'Top-level metadata includes a context summary');
  Check(LIndexes.Count = 4, 'The compact context summary covers the four index scopes');
  for var LScope in TArray<string>.Create('delphi', 'getit', 'group', 'project') do
    Check(LIndexes.GetValue<TJSONObject>(LScope).GetValue<string>('scope') = LScope, 'Every keyed scope retains its own summary');
  Check(LIndexes.GetValue<TJSONObject>('getit').GetValue<string>('state') = 'missing', 'A missing index remains a valid status');
  Check(LIndexes.GetValue<TJSONObject>('project').GetValue<string>('project_file') = CActive, 'Context summary refers to the active project');
  Check(TDAIOTA.ActiveFileName = CActive, 'Metadata inspection never changes the active project');
end;

procedure CheckRowsPreserved(const AResult: TJSONObject);
var
  LRows: TJSONArray;
  LCopy: TJSONObject;
begin
  LRows := AResult.GetValue<TJSONArray>('projects');
  Check(LRows.Count = TDAIFileService.Rows.Count, 'All original project rows remain present');
  for var LIndex := 0 to LRows.Count - 1 do
  begin
    LCopy := LRows.Items[LIndex].Clone as TJSONObject;
    try
      LCopy.RemovePair('index').Free;
      Check(LCopy.ToJSON = TDAIFileService.Rows.Items[LIndex].ToJSON, 'Every original project field and nested package value is unchanged');
    finally
      LCopy.Free;
    end;
  end;
end;

procedure CheckProjects;
var
  LResult, LRow, LIndex: TJSONObject;
  LRows: TJSONArray;
begin
  Reset;
  LResult := Dispatch('projects_list');
  try
    CheckReadMetadataPermission;
    CheckContextSummary(LResult);
    CheckRowsPreserved(LResult);
    Check(TDAIFileService.Calls = 1, 'Project enumeration runs once');
    Check(TDAISymbolService.ContextCalls = 1, 'Project metadata obtains one top-level compact context');
    Check(TDAISymbolService.ProjectCalls = 3, 'Every project receives exactly one targeted index summary');
    LRows := LResult.GetValue<TJSONArray>('projects');
    for var LPosition := 0 to LRows.Count - 1 do
    begin
      LRow := LRows.Items[LPosition] as TJSONObject;
      LIndex := LRow.GetValue<TJSONObject>('index');
      Check(LIndex.GetValue<string>('project_file') = LRow.GetValue<string>('file'), 'A row uses its own project file, including inactive projects');
      Check(TDAISymbolService.Targets[LPosition] = LRow.GetValue<string>('file'), 'Service calls retain project enumeration order and targets');
    end;
    Check(LRows.Items[1].GetValue<Boolean>('active') = False, 'An inactive project stays inactive while its index is inspected');
    Check(Pos('PRIVATE', LResult.ToJSON) = 0, 'Normal metadata has no raw diagnostic content');
  finally
    LResult.Free;
  end;
end;

procedure CheckIDEStatus;
var
  LResult, LPermissions: TJSONObject;
begin
  Reset;
  LResult := Dispatch('ide_status');
  try
    CheckReadMetadataPermission;
    CheckContextSummary(LResult);
    Check(LResult.GetValue<string>('name') = 'DAI', 'Full production ToolStatus still returns its server identity');
    Check(LResult.GetValue<Boolean>('enabled') and LResult.GetValue<Boolean>('active'), 'Existing enablement and runtime state remain available');
    Check(LResult.GetValue<Integer>('port') = 7344, 'Actual runtime port remains distinct from configured port');
    Check(LResult.GetValue<Integer>('configured_port') = 7333, 'Configured port remains available');
    Check(LResult.GetValue<string>('active_project') = CActive, 'Existing active-project metadata is preserved');
    Check(LResult.GetValue<string>('thread_id') = 'fixture-chat', 'Chat metadata remains available');
    Check(LResult.GetValue<string>('transport_session_id') = 'fixture-transport', 'Transport metadata remains available');
    Check(LResult.GetValue<TJSONObject>('lifecycle_control').GetValue<Boolean>('allowed'), 'Lifecycle information remains available');
    LPermissions := LResult.GetValue<TJSONObject>('permissions');
    for var LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
      if LCategory = pcReferenceRead then
        Check(LPermissions.GetValue<string>(DAIPermissionCategoryKey(LCategory)) = 'always', 'Reference metadata remains readable')
      else
        Check(LPermissions.GetValue<string>(DAIPermissionCategoryKey(LCategory)) = 'never', 'Denied project/IDE/build/debug rights remain unchanged');
    Check(TDAISymbolService.ContextCalls = 1, 'IDE status performs one compact context query');
    Check(TDAISymbolService.ProjectCalls = 0, 'IDE status does not redundantly query individual projects');
  finally
    LResult.Free;
  end;
end;

procedure CheckSummaryFailures;
var
  LResult, LBaseline: TJSONObject;
  LRows: TJSONArray;
begin
  Reset;
  LBaseline := Dispatch('ide_status');
  try
    LBaseline.RemovePair('indexes').Free;
    TDAIPermissionManager.Instance.Reset;
    TDAISymbolService.FailContext := True;
    LResult := Dispatch('ide_status');
    try
      CheckReadMetadataPermission;
      Check(LResult.GetValue('indexes') is TJSONNull, 'A failed index summary becomes an unknown optional field');
      Check(Pos('PRIVATE', LResult.ToJSON) = 0, 'A failed status query never exposes exception/source text');
      LResult.RemovePair('indexes').Free;
      Check(LResult.ToJSON = LBaseline.ToJSON, 'A summary exception cannot change or suppress any original IDE status field');
    finally
      LResult.Free;
    end;
  finally
    LBaseline.Free;
  end;

  Reset;
  TDAISymbolService.FailContext := True;
  TDAISymbolService.FailProjectFile := CInactive;
  LResult := Dispatch('projects_list');
  try
    CheckReadMetadataPermission;
    CheckRowsPreserved(LResult);
    Check(LResult.GetValue('indexes') is TJSONNull, 'Top-level summary failure does not prevent project enumeration');
    LRows := LResult.GetValue<TJSONArray>('projects');
    Check(TJSONObject(LRows.Items[0]).GetValue('index') is TJSONObject, 'An earlier successful project keeps its index hint');
    Check(TJSONObject(LRows.Items[1]).GetValue('index') is TJSONNull, 'One failed per-project summary remains local to that row');
    Check(TJSONObject(LRows.Items[2]).GetValue('index') is TJSONObject, 'Later project hints survive an earlier row failure');
    Check(TDAISymbolService.ProjectCalls = 3, 'A failed row does not skip subsequent projects');
    Check(Pos('PRIVATE', LResult.ToJSON) = 0, 'Project metadata does not expose raw summary exceptions');
    Check(TDAIOTA.ActiveFileName = CActive, 'Failure handling never activates an inactive project');
  finally
    LResult.Free;
  end;
end;

procedure CheckUnavailableTargets;
var
  LResult, LRow: TJSONObject;
  LRows: TJSONArray;
begin
  Reset;
  TDAIFileService.Rows.Free;
  TDAIFileService.Rows := TJSONArray.Create;
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Untitled').AddPair('file', ''));
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Unknown').AddPair('file', TJSONNull.Create));
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Missing filename'));
  TDAIFileService.Rows.AddElement(TJSONObject.Create.AddPair('name', 'Invalid filename').AddPair('file', TJSONNumber.Create(123)));
  LResult := Dispatch('projects_list');
  try
    CheckRowsPreserved(LResult);
    LRows := LResult.GetValue<TJSONArray>('projects');
    for var LPosition := 0 to LRows.Count - 1 do
    begin
      LRow := LRows.Items[LPosition] as TJSONObject;
      Check(LRow.GetValue('index') is TJSONNull, 'Unavailable project file paths produce unknown index metadata');
    end;
    Check(TDAISymbolService.ProjectCalls = 0, 'Missing/invalid targets never accidentally query the active project');
  finally
    LResult.Free;
  end;

  Reset;
  TDAIOTA.ActiveFileName := '';
  FreeAndNil(TDAIFileService.Rows);
  TDAIFileService.Rows := TJSONArray.Create;
  LResult := Dispatch('projects_list');
  try
    Check(LResult.GetValue<TJSONArray>('projects').Count = 0, 'An IDE with no projects remains a valid metadata result');
    Check(LResult.GetValue('indexes') is TJSONObject, 'Reference index hints remain available without projects');
    Check(TDAISymbolService.ProjectCalls = 0, 'No per-project lookup occurs when the project list is empty');
  finally
    LResult.Free;
  end;
end;

begin
  try
    CheckIDEStatus;
    CheckProjects;
    CheckSummaryFailures;
    CheckUnavailableTargets;
    Writeln('DAI index hints: ', GChecks, ' checks passed; real ToolStatus/helpers/branches, in-memory services only.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
