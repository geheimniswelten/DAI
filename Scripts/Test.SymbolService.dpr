program TestSymbolService;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  FireDAC.Comp.Client,
  System.Generics.Collections,
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.SyncObjs,
  System.SysUtils,
  System.StrUtils,
  Winapi.Windows,
  ToolsAPI in 'SymbolsServiceTests\ToolsAPI.pas',
  h5u.DAI.OTA.Helpers in 'SymbolsServiceTests\h5u.DAI.OTA.Helpers.pas',
  h5u.DAI.OTA.Files in 'SymbolsServiceTests\h5u.DAI.OTA.Files.pas',
  h5u.DAI.OTA.AI in 'SymbolsServiceTests\h5u.DAI.OTA.AI.pas',
  h5u.DAI.Settings in 'SymbolsServiceTests\h5u.DAI.Settings.pas',
  h5u.DAI.Consts,
  h5u.DAI.Symbols.Parser in '..\Source\h5u.DAI.Symbols.Parser.pas',
  h5u.DAI.Symbols.Store in '..\Source\h5u.DAI.Symbols.Store.pas',
  h5u.DAI.Symbols.Service in '..\Source\h5u.DAI.Symbols.Service.pas';

type
  TTestProject = class(TInterfacedObject, IOTAProject, IOTAProjectGroup)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    function GetFileName: string;
  end;

var
  CheckCount: Integer;

constructor TTestProject.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

function TTestProject.GetFileName: string;
begin
  Result := FFileName;
end;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure ExpectFailure(const AAction: TProc; const ADescription: string);
var
  LFailed: Boolean;
begin
  LFailed := False;
  try
    AAction();
  except
    on E: Exception do
      LFailed := True;
  end;
  Check(LFailed, ADescription);
end;

procedure WriteText(const AFileName, AContent: string);
begin
  ForceDirectories(TPath.GetDirectoryName(AFileName));
  TFile.WriteAllText(AFileName, AContent, TEncoding.UTF8);
end;

procedure ExecuteTestSQL(const ADatabase, ASQL: string);
var
  LConnection: TFDConnection;
begin
  LConnection := TFDConnection.Create(nil);
  try
    LConnection.DriverName := 'SQLite';
    LConnection.Params.Values['Database'] := ADatabase;
    LConnection.Connected := True;
    LConnection.ExecSQL(ASQL);
  finally
    LConnection.Free;
  end;
end;

function UnitText(const AUnitName, AClassName: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + sLineBreak + 'interface' + sLineBreak + 'type' + sLineBreak +
    '  ' + AClassName + ' = class' + sLineBreak + '  public' + sLineBreak + '    procedure Execute(const Value: string);' +
    sLineBreak + '  end;' + sLineBreak + 'implementation' + sLineBreak + 'end.';
end;

function IndexFor(const AScope: string): TJSONObject;
var
  LResult: TJSONObject;
  LValue: TJSONValue;
begin
  LResult := TDAISymbolService.ListIndexes;
  try
    for LValue in LResult.GetValue<TJSONArray>('indexes') do
      if LValue.GetValue<string>('scope') = AScope then
        Exit(LValue.Clone as TJSONObject);
  finally
    LResult.Free;
  end;
  raise Exception.Create('Missing index descriptor for ' + AScope);
end;

function StartBuild(const AScope: string): string;
var
  LResult: TJSONObject;
begin
  LResult := TDAISymbolService.Build(AScope);
  try
    Result := LResult.GetValue<string>('request_id');
    Check(Result <> '', 'Explicit build returns an asynchronous request id');
  finally
    LResult.Free;
  end;
end;

function WaitForJob(const ARequestId: string): TJSONObject;
var
  LStart: UInt64;
begin
  LStart := GetTickCount64;
  while GetTickCount64 - LStart < 15000 do
  begin
    Result := TDAISymbolService.JobStatus(ARequestId);
    if not Result.GetValue<Boolean>('running') then
    begin
      TThread.Sleep(20);
      Exit;
    end;
    Result.Free;
    CheckSynchronize(1);
    TThread.Sleep(5);
  end;
  raise Exception.Create('Timed out waiting for isolated symbol indexing job.');
end;

procedure CheckBuild(const AScope: string; const AUpdated, ASkipped: Integer);
var
  LResult: TJSONObject;
begin
  LResult := WaitForJob(StartBuild(AScope));
  try
    Check(LResult.GetValue<string>('state') = 'completed', 'Index job completes: ' + LResult.ToJSON);
    Check(LResult.GetValue<Integer>('updated_files') = AUpdated, 'Only changed files are reparsed');
    Check(LResult.GetValue<Integer>('skipped_files') = ASkipped, 'Unchanged file hashes are reused');
  finally
    LResult.Free;
  end;
end;

procedure CheckCompactSummary(const ASummary: TJSONObject);
begin
  Check(ASummary.GetValue<string>('state') <> '', 'A compact index summary always supplies a state');
  Check(ASummary.GetValue<string>('freshness') = 'unknown', 'A compact summary never claims that source contents were checked');
  Check(Assigned(ASummary.GetValue('exists')), 'A compact summary always supplies availability');
  Check(Assigned(ASummary.GetValue('indexed_at')), 'A compact summary always supplies the last completed date or an empty string');
  for var LPair in ASummary do
    Check(MatchText(LPair.JsonString.Value, ['exists', 'state', 'indexed_at', 'freshness', 'requires_update']),
      'Compact summaries never expose paths, counters, job identifiers or source/error details');
end;

procedure Run;
var
  LRoot, LPreviousLocalAppData: string;
  LProjectA, LProjectB, LGroup, LFileA, LFileB, LShared, LNewSDKFile: string;
  LDatabase, LOldSDKDatabase, LIdentity, LRequestId, LInactiveDatabase, LLegacyInactiveDatabase: string;
  LBatchFiles: TArray<string>;
  LFileIndex: Integer;
  LA, LB: IOTAProject;
  LResult, LParameters: TJSONObject;
  LReleaseThread: TThread;
  LReportStore: TDAISymbolStore;
  LMetadataLock: TFDConnection;
  LSizeHandle: THandle;
  LExpectedSize, LOriginalSize: Int64;
  LStarted: UInt64;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolService-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  LPreviousLocalAppData := GetEnvironmentVariable('LOCALAPPDATA');
  SetEnvironmentVariable('LOCALAPPDATA', PChar(TPath.Combine(LRoot, 'LocalAppData')));
  try
    LProjectA := TPath.Combine(LRoot, 'ProjectA\A.dproj');
    LProjectB := TPath.Combine(LRoot, 'ProjectB\B.With.Dot.dproj');
    LGroup := TPath.Combine(LRoot, 'Group.With.Dot.groupproj');
    LFileA := TPath.Combine(LRoot, 'ProjectA\A.pas');
    LFileB := TPath.Combine(LRoot, 'ProjectB\B.pas');
    LShared := TPath.Combine(LRoot, 'Shared\Shared.pas');
    WriteText(LProjectA, '<Project/>');
    WriteText(LProjectB, '<Project/>');
    WriteText(LGroup, '<ProjectGroup/>');
    WriteText(LFileA, UnitText('A', 'TAlpha'));
    WriteText(LFileB, UnitText('B', 'TBeta'));
    WriteText(LShared, UnitText('Shared', 'TShared'));
    LA := TTestProject.Create(LProjectA);
    LB := TTestProject.Create(LProjectB);
    TDAIOTA.TestActiveProject := LA;
    TDAIOTA.TestGroup := TTestProject.Create(LGroup);
    TDAIOTA.TestProjects := TArray<IOTAProject>.Create(LA, LB);
    TDAIFileService.ProjectSources.Add(LowerCase(LProjectA), TArray<string>.Create(LFileA, LShared));
    TDAIFileService.ProjectSources.Add(LowerCase(LProjectB), TArray<string>.Create(LFileB, UpperCase(LShared)));
    TDAISettings.Instance.DelphiSourceDirectory := TPath.Combine(LRoot, 'SDK1');
    TDAISettings.Instance.ToolsAPIDirectory := TPath.Combine(LRoot, 'SDK1\ToolsAPI');
    TDAISettings.Instance.CatalogRepositoryDirectory := TPath.Combine(LRoot, 'GetItUser');
    TDAISettings.Instance.CatalogRepositoryAllUsersDirectory := TPath.Combine(LRoot, 'GetItPublic');
    WriteText(TPath.Combine(LRoot, 'SDK1\System.Fixture.pas'), UnitText('System.Fixture', 'TSDKOne'));
    WriteText(TPath.Combine(LRoot, 'SDK1\ToolsAPI\ToolsAPI.Fixture.pas'), UnitText('ToolsAPI.Fixture', 'TOTA'));
    WriteText(TPath.Combine(LRoot, 'GetItUser\Package\ThirdParty.pas'), UnitText('ThirdParty', 'TThirdParty'));
    LResult := TDAISymbolService.ContextSummary;
    try
      Check(LResult.Count = 4, 'Discovery supplies the Delphi, GetIt, group and active-project scopes together');
      for var LScope in TArray<string>.Create('delphi', 'getit', 'group', 'project') do
      begin
        CheckCompactSummary(LResult.GetValue<TJSONObject>(LScope));
        Check(not LResult.GetValue<TJSONObject>(LScope).GetValue<Boolean>('exists'), 'Discovery does not create missing indexes');
      end;
    finally
      LResult.Free;
    end;
    TDAIOTA.TestActiveProject := nil;
    LResult := TDAISymbolService.IndexSummary('project');
    try
      CheckCompactSummary(LResult);
      Check(not LResult.GetValue<Boolean>('exists'), 'An absent active project has no available index');
      Check(LResult.GetValue<string>('state') = 'unavailable', 'No saved project target is distinguishable from a missing database');
    finally
      LResult.Free;
    end;
    TDAIOTA.TestActiveProject := LA;
    LLegacyInactiveDatabase := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(LProjectB), '.dai'),
      'project-B.With.Dot-' + Copy(THashSHA2.GetHashString(LowerCase(LProjectB)), 1, 16) + '.sqlite');
    WriteText(LLegacyInactiveDatabase, 'Legacy filename fixture remains untouched.');
    LResult := TDAISymbolService.IndexSummary('project', LProjectB);
    try
      Check(not LResult.GetValue<Boolean>('exists'), 'Legacy index filenames are ignored rather than migrated or reused');
      Check(TFile.Exists(LLegacyInactiveDatabase), 'Looking up the new filename preserves an existing legacy file');
    finally
      LResult.Free;
    end;
    LInactiveDatabase := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(LProjectB), '.dai'),
      'B.With.Dot.projectindex.' + Copy(THashSHA2.GetHashString(LowerCase(LProjectB)), 1, 16) + '.sqlite');
    LReportStore := TDAISymbolStore.Create(LInactiveDatabase);
    try
      LReportStore.Initialize('project', LProjectB);
      LReportStore.BeginErrorReport('older-inactive-membership', 'inactive-summary-test');
      LReportStore.CompleteBuild('older-inactive-membership');
      LReportStore.FinishBuildState('completed', '');
    finally
      LReportStore.Free;
    end;
    LResult := TDAISymbolService.IndexSummary('project', LProjectB);
    try
      CheckCompactSummary(LResult);
      Check(LResult.GetValue<Boolean>('exists'), 'An inactive project row resolves its own existing index');
      Check(LResult.GetValue<string>('state') = 'outdated', 'Inactive-project ownership is checked against that project rather than the active project');
      Check(LResult.GetValue<Boolean>('requires_update'), 'An inactive index with a different captured identity requests an update');
      Check(TDAIOTA.TestActiveProject = LA, 'Looking up an inactive project never changes the active project');
      Check(TFile.Exists(LLegacyInactiveDatabase), 'Creating the newly named project index leaves legacy files untouched');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexSummary('project', LProjectA);
    try
      Check(not LResult.GetValue<Boolean>('exists'), 'An active project without an index does not reuse the inactive project index');
      Check(LResult.GetValue<string>('state') = 'missing', 'A saved project with no database is marked missing');
    finally
      LResult.Free;
    end;
    LMetadataLock := TFDConnection.Create(nil);
    try
      LMetadataLock.LoginPrompt := False;
      LMetadataLock.Params.Values['DriverID'] := 'SQLite';
      LMetadataLock.Params.Values['Database'] := LInactiveDatabase;
      LMetadataLock.Params.Values['SharedCache'] := 'False';
      LMetadataLock.Params.Values['LockingMode'] := 'Exclusive';
      LMetadataLock.Connected := True;
      LMetadataLock.ExecSQL('UPDATE metadata SET value=value WHERE key=''schema_version''');
      LStarted := GetTickCount64;
      LResult := TDAISymbolService.IndexSummary('project', LProjectB);
      try
        CheckCompactSummary(LResult);
        Check(GetTickCount64 - LStarted < 1000, 'A locked optional index hint never stalls discovery for five seconds');
        Check(LResult.GetValue<Boolean>('exists'), 'An inaccessible but known index file remains distinguishable from a missing file');
        Check(LResult.GetValue<string>('state') = 'error', 'A locked index yields an advisory error state without throwing');
        Check(TDAIOTA.TestActiveProject = LA, 'Locked inactive-index discovery preserves the active project');
      finally
        LResult.Free;
      end;
    finally
      LMetadataLock.Free;
    end;
    LResult := TDAISymbolService.IndexSummary('not-a-scope');
    try
      CheckCompactSummary(LResult);
      Check(LResult.GetValue('exists') is TJSONNull, 'A failed descriptor leaves availability unknown');
      Check(LResult.GetValue<string>('state') = 'error', 'Malformed summary targets cannot fail the surrounding discovery call');
    finally
      LResult.Free;
    end;
    LResult := IndexFor('group');
    try
      Check(not LResult.GetValue<Boolean>('exists'), 'Opening index list does not create a project group index');
      Check(LResult.GetValue('size_bytes') is TJSONNull, 'A missing index has an unknown size rather than a fictitious zero');
      LDatabase := LResult.GetValue<string>('database');
      Check(TPath.GetFileName(LDatabase) = 'Group.With.Dot.groupindex.' + Copy(THashSHA2.GetHashString(LowerCase(LGroup)), 1, 16) + '.sqlite',
        'Group index filenames preserve dots in the basename and retain the existing owner-path identifier');
      Check(not TDirectory.Exists(TPath.GetDirectoryName(LDatabase)), 'Listing never creates .dai');
    finally
      LResult.Free;
    end;
    LResult := IndexFor('project');
    try
      Check(TPath.GetFileName(LResult.GetValue<string>('database')) =
        'A.projectindex.' + Copy(THashSHA2.GetHashString(LowerCase(LProjectA)), 1, 16) + '.sqlite',
        'Active project descriptors use the same basename-first filename pattern as inactive-project summaries');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.Search('group', 'Shared', 'all', 10);
    try
      Check(LResult.GetValue<string>('status') = 'index_missing', 'Search reports a missing index');
      Check(LResult.GetValue<TJSONObject>('next_action').GetValue<string>('tool') = 'project_index_build', 'Missing index suggests explicit build');
      Check(not TFile.Exists(LDatabase), 'Search never implicitly starts index creation');
    finally
      LResult.Free;
    end;
    CheckBuild('group', 3, 0);
    LResult := TDAISymbolService.IndexSummary('group');
    try
      CheckCompactSummary(LResult);
      Check(LResult.GetValue<Boolean>('exists'), 'A completed group index is available in compact discovery');
      Check(LResult.GetValue<string>('state') = 'ready', 'Compact metadata recognizes a completed index');
      Check(LResult.GetValue<string>('indexed_at') <> '', 'Compact metadata retains the successful index date');
    finally
      LResult.Free;
    end;
    LSizeHandle := CreateFileW(PWideChar(LDatabase), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    Check(LSizeHandle <> INVALID_HANDLE_VALUE, 'The isolated completed index can remain open while its size is queried');
    try
      Check(GetFileSizeEx(LSizeHandle, LExpectedSize), 'The expected SQLite size comes from its live file handle');
      LResult := IndexFor('group');
      try
        Check(LResult.GetValue('size_bytes') is TJSONNumber, 'Existing index sizes are JSON numbers');
        Check(LResult.GetValue<Int64>('size_bytes') = LExpectedSize, 'Index metadata reports the exact Int64 size while another handle is open');
        Check(LExpectedSize > 0, 'The created SQLite index has a positive size');
        Check(LResult.GetValue<string>('state') = 'ready', 'Measuring file size leaves the normal index state unchanged');
      finally
        LResult.Free;
      end;
      LOriginalSize := LExpectedSize;
      LReportStore := TDAISymbolStore.Create(LDatabase);
      try
        LReportStore.Initialize('group', LGroup);
        LReportStore.BeginErrorReport(TDAISymbolService.Identity('group'), 'isolated-size-growth-probe');
        LReportStore.RecordError(LFileA, StringOfChar('x', 131072));
        Check(GetFileSizeEx(LSizeHandle, LExpectedSize), 'A held file handle observes SQLite growth without being reopened');
        Check(LExpectedSize > LOriginalSize, 'The isolated SQLite writer grows its file while a separate shared handle remains open');
        LResult := IndexFor('group');
        try
          Check(LResult.GetValue<Int64>('size_bytes') = LExpectedSize, 'Index size follows current SQLite growth while its writer stays open');
          Check(LResult.GetValue<string>('state') <> 'error', 'Measuring an actively open SQLite file adds no spurious index error');
        finally
          LResult.Free;
        end;
        LReportStore.ClearError(LFileA);
        LReportStore.CompleteBuild(TDAISymbolService.Identity('group'));
        LReportStore.FinishBuildState('completed', '');
      finally
        LReportStore.Free;
      end;
    finally
      CloseHandle(LSizeHandle);
    end;
    TDAIOTA.TestProjects := TArray<IOTAProject>.Create(LA);
    LResult := IndexFor('group');
    try
      Check(LResult.GetValue<string>('state') = 'outdated', 'Changed group membership is visible in index metadata');
      Check(LResult.GetValue<Boolean>('requires_update'), 'Index metadata explicitly requests an update for changed membership');
    finally
      LResult.Free;
    end;
    ExpectFailure(procedure begin TDAISymbolService.Search('group', 'TBeta', 'all', 10).Free end,
      'Removed group members cannot be read through an older cached index');
    ExpectFailure(procedure begin TDAISymbolService.Query('group', 'SELECT name FROM symbols', nil, 10).Free end,
      'SQL cannot bypass changed group membership');
    ExpectFailure(procedure begin TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group')).Free end,
      'Error details cannot expose a previous group membership after it changed');
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := TArray<string>.Create(LFileA, LShared, TPath.Combine(LRoot, 'Missing.pas'));
    LResult := WaitForJob(StartBuild('group'));
    try
      Check(LResult.GetValue<string>('state') = 'completed_with_errors', 'Changed membership fixture includes an unreadable source');
      Check(LResult.GetValue<Integer>('error_count') = 1, 'One failed batch entry is reported without losing other readable files');
      Check(LResult.GetValue<TJSONArray>('errors').Items[0].GetValue<string>('file') = TPath.Combine(LRoot, 'Missing.pas'),
        'Batch errors retain the exact failing source filename');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<Integer>('total_count') = 1, 'File errors remain readable after their worker has closed SQLite');
      Check(LResult.GetValue<string>('state') = 'completed_with_errors', 'Error details explain the completed partial build');
      Check(LResult.GetValue<string>('finished_at') <> '', 'Error details persist their build finish timestamp');
      Check(LResult.GetValue<TJSONArray>('errors').Items[0].GetValue<string>('file') = TPath.Combine(LRoot, 'Missing.pas'),
        'The separate report identity allows details from a first failed build before a complete symbol snapshot exists');
    finally
      LResult.Free;
    end;
    ExpectFailure(procedure begin TDAISymbolService.Search('group', 'TBeta', 'all', 10).Free end,
      'A partial rebuild never approves cached symbols from the previous group membership');
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := TArray<string>.Create(LFileA, LShared);
    CheckBuild('group', 0, 2);
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<Integer>('total_count') = 0, 'A successful explicit update removes obsolete error details');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.Search('group', 'TBeta', 'all', 10);
    try
      Check(LResult.GetValue<Integer>('count') = 0, 'Successful explicit rebuild prunes symbols belonging to removed projects');
    finally
      LResult.Free;
    end;
    TDAIOTA.TestProjects := TArray<IOTAProject>.Create(LA, LB);
    ExpectFailure(procedure begin TDAISymbolService.Search('group', 'TAlpha', 'all', 10).Free end,
      'Added group members require an explicit rebuild of the previous membership snapshot');
    CheckBuild('group', 1, 2);
    TDAIOTA.TestProjects := TArray<IOTAProject>.Create(LB, LA);
    LResult := TDAISymbolService.Search('group', 'TBeta', 'all', 10);
    try
      Check(LResult.GetValue<Integer>('count') = 1, 'Reordering the same group members preserves the completed index identity');
    finally
      LResult.Free;
    end;
    TDAIOTA.TestProjects := TArray<IOTAProject>.Create(LA, LB);
    LResult := IndexFor('group');
    try
      Check(LResult.GetValue<Integer>('file_count') = 3, 'Shared sources across projects are indexed once');
      Check(LResult.GetValue<string>('indexed_at') <> '', 'Index list reports completion date');
      Check(LResult.GetValue<string>('freshness') = 'unknown', 'Listing does not claim live source freshness');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.Search('group', 'TShared', 'public', 10);
    try
      Check(LResult.GetValue<Integer>('count') = 1, 'Group search deduplicates shared source');
      Check(LResult.GetValue<string>('warning') <> '', 'Index searches warn about stale and unsaved text');
      Check(LResult.GetValue<string>('freshness') = 'unknown', 'Search does not claim index is current');
    finally
      LResult.Free;
    end;
    CheckBuild('group', 0, 3);
    TDAIFileService.EditorBuffers.Add(LowerCase(LFileA), UnitText('A', 'TUnsavedAlpha'));
    LResult := TDAISymbolService.Search('group', 'TUnsavedAlpha', 'all', 10);
    try
      Check(LResult.GetValue<Integer>('count') = 0, 'An existing index remains a snapshot until explicit update');
    finally
      LResult.Free;
    end;
    CheckBuild('group', 1, 2);
    LResult := TDAISymbolService.Search('group', 'TUnsavedAlpha', 'all', 10);
    try
      Check(LResult.GetValue<Integer>('count') = 1, 'Explicit update uses the current editor buffer');
      Check(LResult.GetValue<TJSONArray>('matches').Items[0].GetValue<string>('source_kind') = 'editor_buffer', 'Editor snapshot origin is retained');
    finally
      LResult.Free;
    end;
    Check(TFile.ReadAllText(LFileA).Contains('TAlpha'), 'Indexing leaves unsaved editor contents off disk');
    TFile.Delete(LFileA);
    CheckBuild('group', 0, 3);
    Check(not TFile.Exists(LFileA), 'An existing editor buffer remains indexable when its disk source is absent');
    WriteText(LFileA, UnitText('A', 'TAlpha'));
    TDAIFileService.ProjectSources[LowerCase(LProjectB)] := TArray<string>.Create(LFileB);
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := TArray<string>.Create(LFileA);
    TFile.Delete(LShared);
    CheckBuild('group', 0, 2);
    LResult := TDAISymbolService.Search('group', 'TShared', 'all', 10);
    try
      Check(LResult.GetValue<Integer>('count') = 0, 'Explicit update prunes removed source files and their symbols');
    finally
      LResult.Free;
    end;
    SetLength(LBatchFiles, 65);
    for LFileIndex := 0 to High(LBatchFiles) do
    begin
      LBatchFiles[LFileIndex] := TPath.Combine(LRoot, Format('ProjectA\Many\Batch%.3d.pas', [LFileIndex]));
      WriteText(LBatchFiles[LFileIndex], UnitText('Batch' + IntToStr(LFileIndex), 'TBatch' + IntToStr(LFileIndex)));
    end;
    TDAIFileService.IndexBatchCalls := 0;
    TDAIFileService.MaximumIndexBatchSize := 0;
    CheckBuild('group', 65, 2);
    Check(TDAIFileService.IndexBatchCalls = 3, 'Sixty-seven sources use three bounded reads instead of one IDE rendezvous per file');
    Check(TDAIFileService.MaximumIndexBatchSize = 32, 'The service bounds each editor snapshot to thirty-two source files');
    TDAIFileService.ReadPrefixLimit := 7;
    CheckBuild('group', 0, 67);
    TDAIFileService.ReadPrefixLimit := 0;
    for LFileIndex := 0 to High(LBatchFiles) do
      TFile.Delete(LBatchFiles[LFileIndex]);
    TDirectory.Delete(TPath.Combine(LRoot, 'ProjectA\Many'));
    CheckBuild('group', 0, 2);
    WriteText(TPath.Combine(LRoot, 'ProjectA\Large.pas'), StringOfChar(' ', 3 * 1024 * 1024) + UnitText('Large', 'TLarge'));
    CheckBuild('group', 1, 2);
    Check(TDAIFileService.LastMaximumBytes = CDAIMaxTextFileBytes, 'Index reads use the shared sixteen-MiB text safety limit');
    Check(TDAIFileService.LargeBatchViolations = 0, 'Source files over one MiB are read in their own bounded batch');
    TFile.Delete(TPath.Combine(LRoot, 'ProjectA\Large.pas'));
    CheckBuild('group', 0, 2);
    SetLength(LBatchFiles, 58);
    LBatchFiles[0] := LFileA;
    for LFileIndex := 1 to High(LBatchFiles) do
      LBatchFiles[LFileIndex] := TPath.Combine(LRoot, Format('MissingError%.3d.pas', [LFileIndex]));
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := LBatchFiles;
    LResult := WaitForJob(StartBuild('group'));
    try
      Check(LResult.GetValue<Integer>('error_count') = 57, 'Every failed source is counted beyond the in-memory summary limit');
      Check(LResult.GetValue<TJSONArray>('errors').Count = 50, 'The job response keeps its bounded error summary');
      Check(LResult.GetValue<Boolean>('errors_has_more'), 'The job explicitly advertises persistent additional errors');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'), 50, 50);
    try
      Check(LResult.GetValue<Integer>('total_count') = 57, 'The persisted report preserves all failures after the job finishes');
      Check(LResult.GetValue<TJSONArray>('errors').Count = 7, 'The details reader retrieves failures beyond the first fifty');
      Check(not LResult.GetValue<Boolean>('has_more'), 'The final details page is explicit about its end');
    finally
      LResult.Free;
    end;
    LResult := IndexFor('group');
    try
      Check(LResult.GetValue<Integer>('error_count') = 57, 'Reopened index metadata retains the file-error count');
      Check(LResult.GetValue<Boolean>('details_available'), 'Reopened metadata offers persistent file-error details');
      Check(LResult.GetValue('errors') = nil, 'Public index metadata does not leak source filenames or error messages');
    finally
      LResult.Free;
    end;
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := TArray<string>.Create(LFileA);
    CheckBuild('group', 0, 2);
    ExecuteTestSQL(LDatabase, 'CREATE TRIGGER controlled_report_start_failure BEFORE INSERT ON metadata ' +
      'WHEN NEW.key=''error_request_id'' BEGIN SELECT RAISE(ABORT,''Controlled BeginErrorReport failure.''); END');
    try
      LResult := WaitForJob(StartBuild('group'));
      try
        LRequestId := LResult.GetValue<string>('request_id');
        Check(LResult.GetValue<string>('state') = 'error', 'A report-start failure finishes its worker as an error');
        Check(LResult.GetValue<string>('error').Contains('Fehlerbericht beginnen'), 'A report-start failure names its exact phase');
        Check(LResult.GetValue<string>('error').Contains('Controlled BeginErrorReport failure.'), 'The original SQLite exception survives a failed report start');
      finally
        LResult.Free;
      end;
      LResult := IndexFor('group');
      try
        Check(LResult.GetValue<Boolean>('details_available'), 'A failed unpersisted job still offers details in the index manager');
        Check(LResult.GetValue<string>('request_id') = LRequestId, 'Metadata identifies the latest failed job rather than the previous successful report');
        Check(LResult.GetValue<string>('last_build_state') = 'error', 'Metadata exposes the latest terminal state');
        Check((LResult.GetValue('error') = nil) and (LResult.GetValue('errors') = nil), 'Public fallback metadata contains no private failure text or filenames');
      finally
        LResult.Free;
      end;
      LResult := TDAISymbolService.IndexSummary('group');
      try
        CheckCompactSummary(LResult);
        Check(LResult.GetValue<string>('state') = 'incomplete', 'Compact discovery preserves the current runtime failure fallback');
      finally
        LResult.Free;
      end;
      LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
      try
        Check(LResult.GetValue<string>('request_id') = LRequestId, 'Details select the failed new job instead of a stale successful report');
        Check(LResult.GetValue<string>('error').Contains('Controlled BeginErrorReport failure.'), 'Details retain the original failure before a report could be persisted');
        Check(LResult.GetValue<string>('report_source') = 'memory', 'Unpersisted diagnostics explicitly identify their in-memory origin');
        Check(LResult.GetValue<string>('storage_warning').Contains('aktuellen IDE-Lauf'), 'The lifetime limitation of unpersisted diagnostics is explicit');
        Check(LResult.GetValue<Integer>('total_count') = 0, 'A global start failure does not invent source-file errors');
      finally
        LResult.Free;
      end;
      ExpectFailure(procedure begin TDAISymbolService.IndexErrors('group', 'foreign-identity').Free end,
        'In-memory diagnostics retain the current project identity guard');
    finally
      ExecuteTestSQL(LDatabase, 'DROP TRIGGER controlled_report_start_failure');
    end;
    ExecuteTestSQL(LDatabase, 'UPDATE metadata SET value=''2099-01-01T00:00:00Z'' ' +
      'WHERE key IN (''build_started_at'',''error_report_started_at'')');
    ExecuteTestSQL(LDatabase, 'UPDATE metadata SET value=''newer-foreign-process-report'' WHERE key=''error_request_id''');
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<string>('request_id') = 'newer-foreign-process-report', 'A newer persisted IDE report takes precedence over an older local failure');
      Check(LResult.GetValue<string>('state') = 'completed', 'A newer successful report is not replaced by an old in-memory error');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexSummary('group');
    try
      CheckCompactSummary(LResult);
      Check(LResult.GetValue<string>('state') = 'ready', 'A newer durable success wins over old runtime failures in compact discovery too');
    finally
      LResult.Free;
    end;
    CheckBuild('group', 0, 2);
    LResult := IndexFor('group');
    try
      Check(not LResult.GetValue<Boolean>('details_available'), 'A subsequent successful build suppresses old in-memory failures');
    finally
      LResult.Free;
    end;
    ExecuteTestSQL(LDatabase, 'CREATE TRIGGER controlled_report_finish_failure BEFORE INSERT ON metadata ' +
      'WHEN NEW.key=''last_build_finished_at'' AND NEW.value<>'''' ' +
      'BEGIN SELECT RAISE(ABORT,''Controlled FinishBuildState failure.''); END');
    try
      TDAIFileService.FailNextIndexBatch := True;
      LResult := WaitForJob(StartBuild('group'));
      try
        Check(LResult.GetValue<string>('error').Contains('Controlled fatal index batch failure.'), 'A secondary storage failure retains the original batch cause');
        Check(LResult.GetValue<string>('error').Contains('Controlled FinishBuildState failure.'), 'The secondary storage failure is retained as additional context');
      finally
        LResult.Free;
      end;
      LResult := WaitForJob(StartBuild('group'));
      try
        Check(LResult.GetValue<string>('state') = 'error', 'An unpersisted completion report leaves a terminal diagnostic error');
        Check(LResult.GetValue<string>('error').Contains('Controlled FinishBuildState failure.'), 'The completion-storage failure retains its original SQLite cause');
      finally
        LResult.Free;
      end;
      LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
      try
        Check(LResult.GetValue<string>('state') = 'error', 'A matching request id still receives the terminal in-memory completion error');
        Check(LResult.GetValue<string>('error').Contains('Controlled FinishBuildState failure.'), 'The mixed report contains the actual completion failure');
        Check(LResult.GetValue<string>('storage_warning').Contains('aktuellen IDE-Lauf'), 'An unpersisted completion reason advertises its lifetime limitation');
        Check(LResult.GetValue<string>('report_source') = 'mixed', 'Persisted file errors can coexist with an in-memory terminal reason');
        Check(LResult.GetValue<string>('finished_at') <> '', 'An unpersisted completion reason still exposes the actual job finish time');
      finally
        LResult.Free;
      end;
    finally
      ExecuteTestSQL(LDatabase, 'DROP TRIGGER controlled_report_finish_failure');
    end;
    ExecuteTestSQL(LDatabase, 'UPDATE metadata SET value=''2099-01-01T00:00:00Z'' ' +
      'WHERE key IN (''build_started_at'',''error_report_started_at'')');
    ExecuteTestSQL(LDatabase, 'UPDATE metadata SET value=''newer-unfinished-report'' WHERE key=''error_request_id''');
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<string>('state') = 'incomplete', 'An unfinished persisted report is not mistaken for an active worker after its main data commit');
      Check(LResult.GetValue<string>('error').Contains('nicht gespeichert'), 'The unavailable completion reason is explained after an interrupted report');
    finally
      LResult.Free;
    end;
    CheckBuild('group', 0, 2);
    TDAIFileService.FailNextIndexBatch := True;
    LResult := WaitForJob(StartBuild('group'));
    try
      Check(LResult.GetValue<string>('state') = 'error', 'Fatal batch errors finish the job as an error');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<string>('state') = 'error', 'A reopened report retains a fatal build state even without file errors');
      Check(LResult.GetValue<string>('error') = 'Quelldateien lesen: EInvalidOperation: Controlled fatal index batch failure.',
        'A reopened report retains the concrete fatal cause');
      Check(LResult.GetValue<Integer>('total_count') = 0, 'A fatal build reason does not invent individual file errors');
    finally
      LResult.Free;
    end;
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := TArray<string>.Create(LRoot + '\Invalid|Path.pas');
    LResult := WaitForJob(StartBuild('group'));
    try
      Check(LResult.GetValue<string>('state') = 'error', 'A source-enumeration exception stops the build before reading files');
      Check(LResult.GetValue<Integer>('processed_files') = 0, 'An enumeration failure does not invent processed source files');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<string>('state') = 'error', 'A source-enumeration failure is persisted before the file list is complete');
      Check(LResult.GetValue<string>('error') <> '', 'A source-enumeration failure retains its concrete exception message');
      Check(LResult.GetValue<string>('finished_at') <> '', 'A source-enumeration failure retains its completion time');
    finally
      LResult.Free;
    end;
    TDAIFileService.ProjectSources[LowerCase(LProjectA)] := TArray<string>.Create(LFileA);
    LReportStore := TDAISymbolStore.Create(LDatabase);
    try
      LReportStore.Initialize('group', LGroup);
      LReportStore.BeginErrorReport(TDAISymbolService.Identity('group'), 'simulated-prior-process');
    finally
      LReportStore.Free;
    end;
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<string>('state') = 'incomplete', 'A prior unfinished process remains distinguishable from an active worker');
      Check(LResult.GetValue<string>('error').Contains('nicht gespeichert'), 'An unknown interruption does not claim an invented crash cause');
    finally
      LResult.Free;
    end;
    CheckBuild('group', 0, 2);
    LIdentity := TDAISymbolService.Identity('project');
    TDAIOTA.TestActiveProject := LB;
    ExpectFailure(procedure begin TDAISymbolService.Build('project', LIdentity).Free end,
      'Project switch invalidates a captured permission identity');
    TDAIOTA.TestActiveProject := LA;
    CheckBuild('project', 1, 0);
    LResult := TDAISymbolService.PermissionSnapshot('group');
    try
      Check(LResult.GetValue<TJSONArray>('projects').Count = 2, 'Permission snapshot covers every grouped project');
      Check(LResult.GetValue<string>('identity') <> '', 'Permission snapshot supplies stable target identity');
    finally
      LResult.Free;
    end;
    CheckBuild('delphi', 2, 0);
    LResult := IndexFor('delphi');
    try
      LOldSDKDatabase := LResult.GetValue<string>('database');
      Check(TPath.GetFullPath(LOldSDKDatabase).StartsWith(TPath.Combine(LRoot, 'LocalAppData')), 'Reference cache stays under isolated local application data');
    finally
      LResult.Free;
    end;
    TDAISettings.Instance.DelphiSourceDirectory := TPath.Combine(LRoot, 'SDK2');
    TDAISettings.Instance.ToolsAPIDirectory := TPath.Combine(LRoot, 'SDK2\ToolsAPI');
    LNewSDKFile := TPath.Combine(LRoot, 'SDK2\System.Other.pas');
    WriteText(LNewSDKFile, UnitText('System.Other', 'TSDKTwo'));
    LResult := IndexFor('delphi');
    try
      Check(not LResult.GetValue<Boolean>('exists'), 'Changing SDK roots selects a missing new index');
      Check(not SameText(LResult.GetValue<string>('database'), LOldSDKDatabase), 'SDK roots contribute to index identity');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.Search('delphi', 'TSDKOne', 'all', 10);
    try
      Check(LResult.GetValue<string>('status') = 'index_missing', 'Old SDK symbols are not reused for a different SDK');
    finally
      LResult.Free;
    end;
    CheckBuild('delphi', 1, 0);
    CheckBuild('getit', 1, 0);
    LParameters := TJSONObject.Create;
    try
      LParameters.AddPair('kind', 'class');
      LResult := TDAISymbolService.Query('group', 'SELECT name FROM symbols WHERE kind=:kind', LParameters, 10);
      try
        Check(LResult.GetValue<Integer>('count') = 2, 'Service exposes parameterized read-only SQL against its selected index');
        Check(LResult.GetValue<string>('warning') <> '', 'SQL results carry snapshot warning');
      finally
        LResult.Free;
      end;
    finally
      LParameters.Free;
    end;
    TDAIFileService.AllowRead.ResetEvent;
    TDAIFileService.ReadEntered.ResetEvent;
    TDAIFileService.BlockReads := True;
    LRequestId := StartBuild('group');
    Check(TDAIFileService.ReadEntered.WaitFor(5000) = wrSignaled, 'Build runs asynchronously and reaches a controlled read gate');
    ExpectFailure(procedure begin TDAISymbolService.Delete('group').Free end, 'A running index cannot be deleted');
    ExpectFailure(procedure begin TDAISymbolService.Build('project').Free end, 'Concurrent index builds are serialized');
    TDAIFileService.AllowRead.SetEvent;
    LResult := WaitForJob(LRequestId);
    try
      Check(LResult.GetValue<string>('state') = 'completed', 'Blocked worker completes after read gate release');
    finally
      LResult.Free;
    end;
    TDAIFileService.BlockReads := False;
    TDAIFileService.FailNextIndexBatch := True;
    LResult := WaitForJob(StartBuild('group'));
    LResult.Free;
    LResult := TDAISymbolService.Delete('group');
    try
      Check(LResult.GetValue<Boolean>('deleted'), 'Explicit deletion removes the selected group index');
    finally
      LResult.Free;
    end;
    Check(not TFile.Exists(LDatabase), 'Group database is absent after delete');
    LResult := TDAISymbolService.IndexSummary('group');
    try
      CheckCompactSummary(LResult);
      Check(not LResult.GetValue<Boolean>('exists'), 'Compact discovery reports deletion without recreating the index');
      Check(LResult.GetValue<string>('state') = 'missing', 'Deleting an index suppresses stale runtime failure summaries');
    finally
      LResult.Free;
    end;
    Check(TFile.Exists(LFileA) and TFile.Exists(LFileB), 'Deleting an index preserves project sources');
    LResult := IndexFor('project');
    try
      Check(LResult.GetValue<Boolean>('exists'), 'Deleting group index preserves separate project index');
    finally
      LResult.Free;
    end;
    LResult := IndexFor('group');
    try
      Check(not LResult.GetValue<Boolean>('exists'), 'The deleted index remains missing after a previous failed job');
      Check(not LResult.GetValue<Boolean>('details_available'), 'Deletion suppresses stale in-memory error details');
    finally
      LResult.Free;
    end;
    TDAIFileService.AllowRead.ResetEvent;
    TDAIFileService.ReadEntered.ResetEvent;
    TDAIFileService.BlockReads := True;
    LRequestId := StartBuild('group');
    Check(TDAIFileService.ReadEntered.WaitFor(5000) = wrSignaled, 'Shutdown fixture has an active worker');
    LReleaseThread := TThread.CreateAnonymousThread(
      procedure
      begin
        TThread.Sleep(100);
        TDAIFileService.AllowRead.SetEvent;
      end);
    LReleaseThread.FreeOnTerminate := False;
    LReleaseThread.Start;
    LStarted := GetTickCount64;
    try
      TDAISymbolService.Shutdown;
      Check(GetTickCount64 - LStarted < 5000, 'Shutdown joins its worker without leaving background SQLite activity');
    finally
      LReleaseThread.WaitFor;
      LReleaseThread.Free;
    end;
    LResult := TDAISymbolService.JobStatus(LRequestId);
    try
      Check(not LResult.GetValue<Boolean>('running'), 'Shutdown leaves no running jobs');
      Check(LResult.GetValue<string>('state') = 'cancelled', 'Interrupted index build is reported as cancelled');
    finally
      LResult.Free;
    end;
    ExpectFailure(procedure begin TDAISymbolService.Build('group').Free end, 'Service rejects new jobs after shutdown');
    LResult := IndexFor('group');
    try
      Check(LResult.GetValue<string>('state') = 'incomplete', 'Cancelled index is never presented as a completed snapshot');
      Check(LResult.GetValue<Boolean>('details_available'), 'An interrupted build offers details even with no individual file errors');
    finally
      LResult.Free;
    end;
    LResult := TDAISymbolService.IndexErrors('group', TDAISymbolService.Identity('group'));
    try
      Check(LResult.GetValue<string>('state') = 'cancelled', 'Interrupted build details retain their explicit state');
      Check(LResult.GetValue<string>('error').Contains('unterbrochen'), 'Interrupted build details retain why the build stopped');
      Check(LResult.GetValue<string>('finished_at') <> '', 'Interrupted build details retain when the build stopped');
    finally
      LResult.Free;
    end;
  finally
    TDAIFileService.AllowRead.SetEvent;
    TDAISymbolService.Shutdown;
    SetEnvironmentVariable('LOCALAPPDATA', PChar(LPreviousLocalAppData));
    TDAIOTA.TestActiveProject := nil;
    TDAIOTA.TestGroup := nil;
    TDAIOTA.TestProjects := nil;
    // Only this single GUID test directory is recursively removed.
    TDirectory.Delete(LRoot, True);
  end;
end;

begin
  try
    Run;
    Writeln('Symbol service checks passed: ', CheckCount);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
