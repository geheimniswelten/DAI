program TestSearchService;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Search,
  h5u.DAI.Settings,
  h5u.DAI.Source.Search;

var
  CheckCount: Integer;
  FixtureDirectory: string;
  MainFile, UnsavedFile, ReferenceFile, SharedFile, SubSharedFile: string;
  ProjectA, ProjectB, ProjectC, ProjectD, ProjectE, ProjectF: IOTAProject;
  Options: TDAISourceSearchOptions;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function Path(const ARelative: string): string;
begin
  Result := TPath.Combine(FixtureDirectory, ARelative);
end;

procedure WriteFixture(const ARelative, AContent: string);
var
  LFileName: string;
begin
  LFileName := Path(ARelative);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(LFileName));
  TFile.WriteAllText(LFileName, AContent, TEncoding.UTF8);
end;

procedure SetBuffer(const AFile, AContent: string; const AReadFails: Boolean = False; const ATruncated: Boolean = False);
var
  LBuffer: TTestBuffer;
begin
  LBuffer.Content := AContent;
  LBuffer.Source := 'editor_buffer';
  LBuffer.ReadFails := AReadFails;
  LBuffer.Truncated := ATruncated;
  TDAIOTA.TestBuffers.AddOrSetValue(TDAIOTA.NormalizeFileName(AFile), LBuffer);
end;

function Matches(const AResult: TJSONObject): TJSONArray;
begin
  Result := AResult.GetValue<TJSONArray>('matches');
  Check(Assigned(Result), 'search result contains matches array');
end;

procedure CheckSearch(const AQuery, AScope, AProject, ADirectory: string; const AExpectedMatches: Integer);
var
  LResult: TJSONObject;
begin
  LResult := TDAISourceSearchService.Search(AQuery, AScope, AProject, ADirectory, Options);
  try
    Check(Matches(LResult).Count = AExpectedMatches,
      AScope + ' / ' + AQuery + ' returns ' + AExpectedMatches.ToString + ' matches; actual ' + Matches(LResult).Count.ToString);
    Check(not LResult.GetValue<Boolean>('preparation_truncated'), 'fixture preparation finishes within budget');
  finally
    LResult.Free;
  end;
end;

function ContainsProject(const AProjects: TArray<IOTAProject>; const AProject: IOTAProject): Boolean;
var
  LProject: IOTAProject;
begin
  for LProject in AProjects do
    if LProject = AProject then
      Exit(True);
  Result := False;
end;

procedure CheckPermissions;
var
  LProjects: TArray<IOTAProject>;
  LSeen: TDictionary<string, Boolean>;
  LProject: IOTAProject;
begin
  LProjects := TDAISourceSearchService.ProjectsForPermission('project', 'A', '');
  Check(ContainsProject(LProjects, ProjectA), 'selected project is authorized');
  Check(ContainsProject(LProjects, ProjectB), 'nested project below recursive selected root is authorized');
  Check(ContainsProject(LProjects, ProjectC), 'owner of explicit shared external unit is authorized');
  Check(ContainsProject(LProjects, ProjectF), 'distant owner of recursively included unit is authorized');
  Check(not ContainsProject(LProjects, ProjectE), 'uncovered external project is excluded');

  LProjects := TDAISourceSearchService.ProjectsForPermission('project', 'A', Path('A\Sub'));
  Check(ContainsProject(LProjects, ProjectC), 'directory filter retains distant owner of shared unit inside the directory');
  Check(not ContainsProject(LProjects, ProjectB), 'directory filter excludes unrelated nested project');

  LProjects := TDAISourceSearchService.ProjectsForPermission('references', '', '');
  Check(ContainsProject(LProjects, ProjectD), 'project physically below reference root is authorized');
  Check(ContainsProject(LProjects, ProjectC), 'distant project owning a reference-root unit is authorized');
  Check(not ContainsProject(LProjects, ProjectE), 'references excludes unrelated external project');

  LProjects := TDAISourceSearchService.ProjectsForPermission('all', 'A', '');
  Check(ContainsProject(LProjects, ProjectA) and ContainsProject(LProjects, ProjectB) and
    ContainsProject(LProjects, ProjectC) and ContainsProject(LProjects, ProjectD) and ContainsProject(LProjects, ProjectF),
    'all with explicit project covers references and nested/shared owners');
  Check(not ContainsProject(LProjects, ProjectE), 'all with explicit project excludes other external project');
  LSeen := TDictionary<string, Boolean>.Create;
  try
    for LProject in LProjects do
    begin
      Check(not LSeen.ContainsKey(LProject.FileName), 'permission project keys are deduplicated');
      LSeen.Add(LProject.FileName, True);
    end;
  finally
    LSeen.Free;
  end;

  LProjects := TDAISourceSearchService.ProjectsForPermission('group', '', '');
  Check(Length(LProjects) = 6, 'group covers all opened projects once');
  LProjects := TDAISourceSearchService.SelectedProjects(' project ', '');
  Check((Length(LProjects) = 1) and (LProjects[0] = ProjectA), 'empty project argument selects active project');
  Check(Length(TDAISourceSearchService.SelectedProjects('references', '')) = 0, 'references selects no workspace project directly');
  Check(Length(TDAISourceSearchService.SelectedProjects('all', 'A')) = 1, 'explicit project restricts workspace projects under all');
end;

procedure CheckSearches;
var
  LResult: TJSONObject;
  LMatch: TJSONObject;
  LRejected: Boolean;
  LTimeoutOptions: TDAISourceSearchOptions;
begin
  CheckSearch('MARK_SCOPE_B', 'project', 'A', '', 1);
  CheckSearch('MARK_RECURSIVE_OWNER', 'project', 'A', '', 1);
  CheckSearch('MARK_REF', 'project', 'A', '', 0);
  CheckSearch('MARK_REF', 'references', '', '', 2);
  CheckSearch('MARK_EDITOR', 'references', '', '', 0);
  CheckSearch('MARK_GROUP_ONLY', 'group', '', '', 1);
  CheckSearch('MARK_GROUP_ONLY', 'project', 'A', '', 0);
  CheckSearch('MARK_REF', 'all', 'A', '', 2);
  CheckSearch('MARK_SHARED', 'project', 'A', '', 1);
  CheckSearch('MARK_SUB_SHARED', 'project', 'A', Path('A\Sub'), 1);
  CheckSearch('MARK_SHARED', 'project', 'A', Path('A\Sub'), 0);
  CheckSearch('disk-stale', 'project', 'A', '', 0);
  CheckSearch('MARK_EDITOR', 'project', 'A', '', 1);

  LResult := TDAISourceSearchService.Search('MARK_UNSAVED', 'project', 'A', '', Options);
  try
    Check(Matches(LResult).Count = 1, 'unsaved editor-only file is searched');
    LMatch := TJSONObject(Matches(LResult)[0]);
    Check(TDAIOTA.SameFile(LMatch.GetValue<string>('file'), UnsavedFile), 'unsaved hit returns full editor file name');
    Check(LMatch.GetValue<string>('source') = 'editor_buffer', 'unsaved hit identifies editor content');
    Check(not TFile.Exists(UnsavedFile), 'search does not save unsaved source');
    Check(not LMatch.GetValue<Boolean>('read_only_reference'), 'workspace hit is writable by classification');
  finally
    LResult.Free;
  end;
  LResult := TDAISourceSearchService.Search('MARK_REF_ONLY', 'references', '', '', Options);
  try
    Check(Matches(LResult).Count = 1, 'reference-only match exists');
    LMatch := TJSONObject(Matches(LResult)[0]);
    Check(LMatch.GetValue<Boolean>('read_only_reference'), 'reference hit is marked read-only');
    Check(LMatch.GetValue<string>('source') = 'disk', 'closed reference hit identifies disk content');
  finally
    LResult.Free;
  end;

  SetBuffer(MainFile, '', True);
  LResult := TDAISourceSearchService.Search('disk-stale', 'project', 'A', '', Options);
  try
    Check(Matches(LResult).Count = 0, 'unavailable editor buffer never falls back to stale disk');
    Check(LResult.GetValue<Integer>('snapshot_files_skipped') = 1, 'unavailable editor snapshot is reported');
  finally
    LResult.Free;
  end;
  SetBuffer(MainFile, 'MARK_EDITOR', False, True);
  LResult := TDAISourceSearchService.Search('disk-stale', 'project', 'A', '', Options);
  try
    Check(Matches(LResult).Count = 0, 'truncated editor buffer never falls back to stale disk');
    Check(LResult.GetValue<Integer>('snapshot_files_skipped') = 1, 'truncated editor snapshot is reported');
  finally
    LResult.Free;
  end;
  SetBuffer(MainFile, 'MARK_EDITOR');

  LRejected := False;
  try
    LResult := TDAISourceSearchService.Search('MARK_REF', 'project', 'A', Path('References'), Options);
    LResult.Free;
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'directory outside selected roots is rejected');
  LRejected := False;
  try
    TDAISourceSearchService.SelectedProjects('invalid', '');
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'invalid scope is rejected');

  LTimeoutOptions := Options;
  LTimeoutOptions.TimeoutMs := 1;
  TDAIOTA.TestProjectReadDelayMs := 20;
  try
    LResult := TDAISourceSearchService.Search('disk-stale', 'project', 'A', '', LTimeoutOptions);
    try
      Check(Matches(LResult).Count = 0, 'expired preparation cannot produce stale disk matches');
      Check(LResult.GetValue<Boolean>('preparation_truncated'), 'expired preparation is reported');
      Check(LResult.GetValue<Boolean>('truncated') and (LResult.GetValue<string>('limit_reason') = 'timeout'), 'expired preparation carries timeout limit reason');
    finally
      LResult.Free;
    end;
  finally
    TDAIOTA.TestProjectReadDelayMs := 0;
  end;
end;

procedure CheckPreparedPlan;
var
  LActiveProject: IOTAProject;
  LGroup: IOTAProjectGroup;
  LPlan: TDAISourceSearchPlan;
  LProjects: TArray<IOTAProject>;
  LReadRoots: TArray<string>;
  LResult: TJSONObject;
  LReadCount: Integer;
  LNewFile: string;
  LNewProject: IOTAProject;
  LRejected: Boolean;
  LTimeoutOptions: TDAISourceSearchOptions;
  LProjectReadCount: Integer;
begin
  LProjects := TDAIOTA.TestProjects;
  LActiveProject := TDAIOTA.TestActiveProject;
  LGroup := TDAIOTA.TestGroup;
  LReadRoots := TDAISettings.TestReadRoots;
  LReadCount := TDAIOTA.TestReadCount;
  TDAIOTA.TestProjectReadCount := 0;
  TDAIOTA.TestProjectReadKeys := nil;
  LPlan := TDAISourceSearchService.Prepare('all', 'A', '', Options.TimeoutMs);
  Check(TDAIOTA.TestReadCount = LReadCount, 'Prepare reads no editor contents before authorization');
  Check(TDAIOTA.TestProjectReadCount = Length(LProjects), 'Prepare reads each opened project file list once');
  try
    TDAIOTA.TestProjects := [ProjectE];
    TDAIOTA.TestActiveProject := ProjectE;
    TDAIOTA.TestGroup := nil;
    TDAISettings.TestReadRoots := [Path('External')];
    LResult := TDAISourceSearchService.SearchPrepared('MARK_REF_ONLY', LPlan, Options);
    try
      Check(Matches(LResult).Count = 1, 'prepared references remain covered after settings change');
      Check(TJSONObject(Matches(LResult)[0]).GetValue<Boolean>('read_only_reference'), 'prepared readonly classification remains fixed');
    finally
      LResult.Free;
    end;
    LResult := TDAISourceSearchService.SearchPrepared('MARK_E_ONLY', LPlan, Options);
    try
      Check(Matches(LResult).Count = 0, 'new active project and reference roots are not added after authorization');
    finally
      LResult.Free;
    end;
    LResult := TDAISourceSearchService.SearchPrepared('MARK_EDITOR', LPlan, Options);
    try
      Check(Matches(LResult).Count = 1, 'prepared explicit files remain covered after project group change');
    finally
      LResult.Free;
    end;
    for var LIndex := Length(LProjects) to Length(TDAIOTA.TestProjectReadKeys) - 1 do
      Check(TDAIOTA.SameFile(TDAIOTA.TestProjectReadKeys[LIndex], ProjectE.FileName),
        'SearchPrepared only rechecks ownership for current projects absent from authorized keys');
  finally
    TDAIOTA.TestProjects := LProjects;
    TDAIOTA.TestActiveProject := LActiveProject;
    TDAIOTA.TestGroup := LGroup;
    TDAISettings.TestReadRoots := LReadRoots;
  end;

  LNewFile := Path('A\OpenedDuringPermission.pas');
  WriteFixture('A\OpenedDuringPermission.pas', 'MARK_OLD_DISK');
  LPlan := TDAISourceSearchService.Prepare('project', 'A', '', Options.TimeoutMs);
  SetBuffer(LNewFile, 'MARK_NEW_EDITOR');
  try
    LResult := TDAISourceSearchService.SearchPrepared('MARK_NEW_EDITOR', LPlan, Options);
    try
      Check(Matches(LResult).Count = 1, 'buffer opened during authorization overrides scoped disk file');
      Check(TJSONObject(Matches(LResult)[0]).GetValue<string>('source') = 'editor_buffer', 'newly opened buffer hit is labeled editor_buffer');
    finally
      LResult.Free;
    end;
    LResult := TDAISourceSearchService.SearchPrepared('MARK_OLD_DISK', LPlan, Options);
    try
      Check(Matches(LResult).Count = 0, 'newly opened dirty buffer never produces stale disk matches');
    finally
      LResult.Free;
    end;
  finally
    TDAIOTA.TestBuffers.Remove(TDAIOTA.NormalizeFileName(LNewFile));
  end;
  Check(TFile.ReadAllText(MainFile, TEncoding.UTF8) = 'disk-stale', 'all search operations preserve source disk contents');

  WriteFixture('A\OwnedByNewProject.pas', 'MARK_NEW_PROJECT_OWNER');
  LPlan := TDAISourceSearchService.Prepare('project', 'A', '', Options.TimeoutMs);
  LNewProject := TTestProject.Create(Path('NewOutside\G.dpr'), [Path('A\OwnedByNewProject.pas')]);
  TDAIOTA.TestProjects := LProjects + [LNewProject];
  LReadCount := TDAIOTA.TestReadCount;
  LRejected := False;
  try
    try
      LResult := TDAISourceSearchService.SearchPrepared('MARK_NEW_PROJECT_OWNER', LPlan, Options);
      LResult.Free;
    except
      on E: EInvalidOperation do
        LRejected := True;
    end;
    Check(LRejected, 'newly affected project requires a fresh authorization plan');
    Check(TDAIOTA.TestReadCount = LReadCount, 'new affected project is rejected before editor contents are read');
  finally
    TDAIOTA.TestProjects := LProjects;
  end;

  LPlan := TDAISourceSearchService.Prepare('project', 'A', '', Options.TimeoutMs);
  LTimeoutOptions := Options;
  LTimeoutOptions.TimeoutMs := Integer(LPlan.PreparationMs) + 1;
  TDAIOTA.TestProjects := [
    TTestProject.Create(Path('Unrelated1\X.dpr'), []),
    TTestProject.Create(Path('Unrelated2\Y.dpr'), []),
    TTestProject.Create(Path('Unrelated3\Z.dpr'), [])
  ];
  TDAIOTA.TestProjectReadDelayMs := 20;
  LProjectReadCount := TDAIOTA.TestProjectReadCount;
  try
    LResult := TDAISourceSearchService.SearchPrepared('MARK_EDITOR', LPlan, LTimeoutOptions);
    try
      Check(TDAIOTA.TestProjectReadCount - LProjectReadCount <= 1, 'ownership recheck stops making OTA calls once time budget is spent');
      Check(Matches(LResult).Count = 0, 'expired ownership recheck returns no content matches');
      Check(LResult.GetValue<Boolean>('preparation_truncated'), 'ownership recheck timeout is explicit');
    finally
      LResult.Free;
    end;
  finally
    TDAIOTA.TestProjects := LProjects;
    TDAIOTA.TestProjectReadDelayMs := 0;
  end;
end;

procedure CheckRegexSearches;
var
  LRegexOptions: TDAISourceSearchOptions;
  LResult: TJSONObject;
  LPlan: TDAISourceSearchPlan;
  LReadCount: Integer;
  LProjectReadCount: Integer;
  LRejected: Boolean;
begin
  LRegexOptions := Options;
  LRegexOptions.UseRegex := True;
  LResult := TDAISourceSearchService.Search('MARK_(?:EDITOR|UNSAVED)', 'project', 'A', '', LRegexOptions);
  try
    Check(Matches(LResult).Count = 2, 'content regex searches authoritative and unsaved editor buffers');
    Check(LResult.GetValue<Boolean>('use_regex'), 'regex query mode is returned');
  finally
    LResult.Free;
  end;
  LRegexOptions.FilenameRegex := '^unsaved\.pas$';
  LResult := TDAISourceSearchService.Search('MARK_(?:EDITOR|UNSAVED)', 'project', 'A', '', LRegexOptions);
  try
    Check(Matches(LResult).Count = 1, 'filename regex selects editor-only unsaved source');
    Check(TJSONObject(Matches(LResult)[0]).GetValue<string>('source') = 'editor_buffer', 'regex preserves current unsaved buffer source');
    Check(LResult.GetValue<string>('filename_regex') = LRegexOptions.FilenameRegex, 'filename regex is returned');
    Check(not TFile.Exists(UnsavedFile), 'regex search never saves editor-only source');
  finally
    LResult.Free;
  end;
  LRegexOptions.CaseSensitive := True;
  LReadCount := TDAIOTA.TestReadCount;
  LResult := TDAISourceSearchService.Search('MARK_UNSAVED', 'project', 'A', '', LRegexOptions);
  try
    Check(Matches(LResult).Count = 0, 'case-sensitive filename regex is applied to editor prefilter');
    Check(TDAIOTA.TestReadCount = LReadCount, 'excluded filename regex reads no editor contents');
  finally
    LResult.Free;
  end;
  LRegexOptions.CaseSensitive := False;
  LRegexOptions.FilePatterns := ['*.inc'];
  LResult := TDAISourceSearchService.Search('MARK_UNSAVED', 'project', 'A', '', LRegexOptions);
  try
    Check(Matches(LResult).Count = 0, 'editor prefilter combines filename regex and file patterns with AND');
    Check(TDAIOTA.TestReadCount = LReadCount, 'AND-excluded editor is not read');
  finally
    LResult.Free;
  end;

  LRegexOptions := Options;
  LRegexOptions.UseRegex := True;
  LRejected := False;
  LProjectReadCount := TDAIOTA.TestProjectReadCount;
  try
    LResult := TDAISourceSearchService.Search('(', 'project', 'A', '', LRegexOptions);
    LResult.Free;
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'invalid query regex rejected before preparing or reading any source');
  Check(TDAIOTA.TestProjectReadCount = LProjectReadCount, 'invalid query regex does not inspect project file lists');
  Check(TDAIOTA.TestReadCount = LReadCount, 'invalid query regex reads no editor content');

  LPlan := TDAISourceSearchService.Prepare('project', 'A', '', Options.TimeoutMs);
  LRegexOptions := Options;
  LRegexOptions.FilenameRegex := '[';
  LRejected := False;
  try
    LResult := TDAISourceSearchService.SearchPrepared('needle', LPlan, LRegexOptions);
    LResult.Free;
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'invalid filename regex rejected in an already authorized plan');
  Check(TDAIOTA.TestReadCount = LReadCount, 'invalid prepared filename regex reads no editor content');
end;

procedure CreateFixtures;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FixtureDirectory := TPath.Combine(TPath.GetTempPath, 'DAI-SearchService-Fixture-' + GUIDToString(LGuid));
  WriteFixture('A\A.dpr', 'program A; begin end.');
  WriteFixture('A\Main.pas', 'disk-stale');
  WriteFixture('A\Nested\B.dpr', 'program B; begin end.');
  WriteFixture('A\Nested\Nested.pas', 'MARK_SCOPE_B');
  WriteFixture('C\C.dpr', 'program C; begin end.');
  WriteFixture('References\D.dpr', 'program D; begin end.');
  WriteFixture('References\Reference.pas', 'MARK_REF_ONLY');
  WriteFixture('References\ExternallyOwned.pas', 'MARK_REF_OWNER');
  WriteFixture('External\E.dpr', 'program E; begin end.');
  WriteFixture('External\OnlyE.pas', 'MARK_E_ONLY');
  WriteFixture('Other\F.dpr', 'program F; begin end.');
  WriteFixture('A\OnlyF.pas', 'MARK_RECURSIVE_OWNER');
  WriteFixture('Shared\Outside.pas', 'MARK_SHARED');
  WriteFixture('A\Sub\Shared.pas', 'MARK_SUB_SHARED');
  WriteFixture('GroupOnly.pas', 'MARK_GROUP_ONLY');
  MainFile := Path('A\Main.pas');
  UnsavedFile := Path('A\Unsaved.pas');
  ReferenceFile := Path('References\Reference.pas');
  SharedFile := Path('Shared\Outside.pas');
  SubSharedFile := Path('A\Sub\Shared.pas');
  ProjectA := TTestProject.Create(Path('A\A.dpr'), [MainFile, SharedFile, SubSharedFile, MainFile]);
  ProjectB := TTestProject.Create(Path('A\Nested\B.dpr'), [Path('A\Nested\Nested.pas')]);
  ProjectC := TTestProject.Create(Path('C\C.dpr'), [SharedFile, SubSharedFile, Path('References\ExternallyOwned.pas')]);
  ProjectD := TTestProject.Create(Path('References\D.dpr'), [ReferenceFile]);
  ProjectE := TTestProject.Create(Path('External\E.dpr'), [Path('External\OnlyE.pas')]);
  ProjectF := TTestProject.Create(Path('Other\F.dpr'), [Path('A\OnlyF.pas')]);
  TDAIOTA.TestProjects := [ProjectA, ProjectB, ProjectC, ProjectD, ProjectE, ProjectF];
  TDAIOTA.TestActiveProject := ProjectA;
  TDAIOTA.TestGroup := TTestProjectGroup.Create(Path('Group.groupproj'));
  TDAISettings.TestReadRoots := [Path('References')];
  SetBuffer(MainFile, 'MARK_EDITOR');
  SetBuffer(UnsavedFile, 'MARK_UNSAVED');
  Options := Default(TDAISourceSearchOptions);
  Options.TimeoutMs := 5000;
end;

procedure CleanFixtures;
var
  LTemporaryDirectory: string;
begin
  TDAIOTA.TestBuffers.Clear;
  TDAIOTA.TestProjects := nil;
  TDAIOTA.TestActiveProject := nil;
  TDAIOTA.TestGroup := nil;
  LTemporaryDirectory := ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.GetTempPath));
  if (FixtureDirectory <> '') and SameText(TPath.GetDirectoryName(TPath.GetFullPath(FixtureDirectory)), LTemporaryDirectory) and
    TPath.GetFileName(FixtureDirectory).StartsWith('DAI-SearchService-Fixture-{') and TDirectory.Exists(FixtureDirectory) then
    TDirectory.Delete(FixtureDirectory, True);
end;

begin
  try
    try
      CreateFixtures;
      CheckPermissions;
      CheckSearches;
      CheckPreparedPlan;
      CheckRegexSearches;
      Writeln('PASS: ', CheckCount, ' isolated search service checks; real OTA adapter and engine, no live IDE or client settings.');
    finally
      CleanFixtures;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
