unit h5u.DAI.OTA.Search;

interface

uses
  System.JSON,
  ToolsAPI,
  h5u.DAI.Source.Search;

type
  TDAISourceSearchPlan = record
    Scope: string;
    Directory: string;
    Roots: TArray<string>;
    ExplicitFiles: TArray<string>;
    ReadOnlyRoots: TArray<string>;
    OpenFiles: TArray<string>;
    AffectedProjects: TArray<IOTAProject>;
    ProjectKeys: TArray<string>;
    PreparationMs: Int64;
    PreparationTruncated: Boolean;
  end;

  TDAISourceSearchService = class sealed
  public
    class function SelectedProjects(const AScope, AProject: string): TArray<IOTAProject>; static;
    class function ProjectsForPermission(const AScope, AProject, ADirectory: string): TArray<IOTAProject>; static;
    class function Prepare(const AScope, AProject, ADirectory: string; const ATimeoutMs: Integer): TDAISourceSearchPlan; static;
    class function SearchPrepared(const AQuery: string; const APlan: TDAISourceSearchPlan; const AOptions: TDAISourceSearchOptions): TJSONObject; static;
    class function Search(const AQuery, AScope, AProject, ADirectory: string; const AOptions: TDAISourceSearchOptions): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings;

procedure AddPath(const APaths: TList<string>; const APath: string);
var
  LPath: string;
  LExisting: string;
begin
  if Trim(APath) = '' then
    Exit;
  LPath := TDAIOTA.NormalizeFileName(APath);
  for LExisting in APaths do
    if SameText(LExisting, LPath) then
      Exit;
  APaths.Add(LPath);
end;

function InsideRoots(const APath: string; const ARoots: TList<string>): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in ARoots do
    if TDAIOTA.SameFile(APath, LRoot) or TDAIOTA.IsPathWithin(APath, LRoot) then
      Exit(True);
end;

class function TDAISourceSearchService.SelectedProjects(const AScope, AProject: string): TArray<IOTAProject>;
var
  LProject: IOTAProject;
  LScope: string;
begin
  LScope := LowerCase(Trim(AScope));
  if LScope = '' then
    LScope := 'all';
  if (LScope <> 'project') and (LScope <> 'group') and (LScope <> 'references') and (LScope <> 'all') then
    raise EArgumentException.Create('scope muss project, group, references oder all sein.');
  Result := [];
  if LScope = 'references' then
    Exit;
  if (AProject <> '') or (LScope = 'project') then
  begin
    LProject := TDAIOTA.ProjectByNameOrPath(AProject);
    if not Assigned(LProject) then
      raise EArgumentException.Create('Das ausgewählte Projekt ist nicht geöffnet.');
    Result := [LProject];
    Exit;
  end;
  Result := TDAIOTA.Projects;
end;

class function TDAISourceSearchService.Prepare(const AScope, AProject, ADirectory: string; const ATimeoutMs: Integer): TDAISourceSearchPlan;
var
  LAllProjects: TArray<IOTAProject>;
  LCache: TDictionary<string, TArray<string>>;
  LClock: TStopwatch;
  LExplicit: TDictionary<string, Boolean>;
  LFiles: TArray<string>;
  LFile: string;
  LGroup: IOTAProjectGroup;
  LGroupFile: string;
  LJSONArray: TJSONArray;
  LKey: string;
  LKeys: TList<string>;
  LMatches: Boolean;
  LProject: IOTAProject;
  LProjects: TList<IOTAProject>;
  LRoots: TList<string>;
  LSelected: TArray<IOTAProject>;
  LSelectedKeys: TDictionary<string, Boolean>;
  LTimeout: Integer;
begin
  Result := Default(TDAISourceSearchPlan);
  Result.Scope := LowerCase(Trim(AScope));
  if Result.Scope = '' then
    Result.Scope := 'all';
  LTimeout := ATimeoutMs;
  if LTimeout = 0 then
    LTimeout := 5000;
  if not InRange(LTimeout, 1, 30000) then
    raise EArgumentOutOfRangeException.Create('timeout_ms muss zwischen 1 und 30000 liegen.');
  LClock := TStopwatch.StartNew;
  LRoots := TList<string>.Create;
  LKeys := TList<string>.Create;
  LProjects := TList<IOTAProject>.Create;
  LExplicit := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  LSelectedKeys := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  LCache := TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
  try
    LSelected := SelectedProjects(Result.Scope, AProject);
    LAllProjects := TDAIOTA.Projects;
    for LProject in LSelected do
    begin
      LKey := TDAIOTA.ProjectFileName(LProject);
      AddPath(LRoots, TPath.GetDirectoryName(LKey));
      LSelectedKeys.AddOrSetValue(LKey, True);
    end;
    if ((Result.Scope = 'group') or (Result.Scope = 'all')) and (AProject = '') then
    begin
      LGroup := TDAIOTA.MainProjectGroup;
      LGroupFile := '';
      TDAIOTA.RunOnMainThread(
        procedure
        begin
          if Assigned(LGroup) then
            LGroupFile := LGroup.FileName;
        end);
      if LGroupFile <> '' then
      begin
        AddPath(LRoots, TPath.GetDirectoryName(LGroupFile));
        LExplicit.AddOrSetValue(TDAIOTA.NormalizeFileName(LGroupFile), True);
      end;
    end;
    Result.ReadOnlyRoots := TDAISettings.Instance.ReadOnlyRootDirectories;
    if (Result.Scope = 'references') or (Result.Scope = 'all') then
      for LKey in Result.ReadOnlyRoots do
        AddPath(LRoots, LKey);
    if Trim(ADirectory) <> '' then
    begin
      Result.Directory := TDAISettings.Instance.ExpandPath(ADirectory);
      if not InsideRoots(Result.Directory, LRoots) then
        raise EArgumentException.Create('directory liegt nicht innerhalb der ausgewählten Projekt- oder Referenzpfade.');
      LRoots.Clear;
      AddPath(LRoots, Result.Directory);
    end;
    Result.Roots := LRoots.ToArray;
    // Collect only module paths before authorization, never editor or disk content.
    for LProject in LAllProjects do
    begin
      if LClock.ElapsedMilliseconds >= LTimeout then
      begin
        Result.PreparationTruncated := True;
        Break;
      end;
      LKey := TDAIOTA.ProjectFileName(LProject);
      if not LCache.TryGetValue(LKey, LFiles) then
      begin
        LJSONArray := TDAIFileService.ProjectFiles(LKey);
        try
          SetLength(LFiles, LJSONArray.Count);
          for var LIndex := 0 to LJSONArray.Count - 1 do
            LFiles[LIndex] := TDAIOTA.NormalizeFileName(LJSONArray.Items[LIndex].Value);
        finally
          LJSONArray.Free;
        end;
        LCache.Add(LKey, LFiles);
      end;
      if LSelectedKeys.ContainsKey(LKey) then
        for LFile in LFiles do
          if (Result.Directory = '') or TDAIOTA.IsPathWithin(LFile, Result.Directory) then
            LExplicit.AddOrSetValue(LFile, True);
    end;
    if (Result.Directory <> '') and (LGroupFile <> '') then
      if not TDAIOTA.IsPathWithin(LGroupFile, Result.Directory) then
        LExplicit.Remove(TDAIOTA.NormalizeFileName(LGroupFile));
    Result.ExplicitFiles := LExplicit.Keys.ToArray;
    for LProject in LAllProjects do
    begin
      if LClock.ElapsedMilliseconds >= LTimeout then
      begin
        Result.PreparationTruncated := True;
        Break;
      end;
      LKey := TDAIOTA.ProjectFileName(LProject);
      LMatches := LSelectedKeys.ContainsKey(LKey);
      if LCache.TryGetValue(LKey, LFiles) then
        for LFile in LFiles do
          if InsideRoots(LFile, LRoots) or LExplicit.ContainsKey(LFile) then
          begin
            LMatches := True;
            Break;
          end;
      if LMatches and not LKeys.Contains(LKey) then
      begin
        LKeys.Add(LKey);
        LProjects.Add(LProject);
      end;
    end;
    Result.AffectedProjects := LProjects.ToArray;
    Result.ProjectKeys := LKeys.ToArray;
    if LClock.ElapsedMilliseconds < LTimeout then
    begin
      LJSONArray := TDAIFileService.OpenFiles;
      try
        SetLength(Result.OpenFiles, LJSONArray.Count);
        for var LIndex := 0 to LJSONArray.Count - 1 do
          Result.OpenFiles[LIndex] := LJSONArray.Items[LIndex].Value;
      finally
        LJSONArray.Free;
      end;
    end;
    Result.PreparationMs := LClock.ElapsedMilliseconds;
    Result.PreparationTruncated := Result.PreparationTruncated or (Result.PreparationMs >= LTimeout);
  finally
    LCache.Free;
    LSelectedKeys.Free;
    LExplicit.Free;
    LProjects.Free;
    LKeys.Free;
    LRoots.Free;
  end;
end;

class function TDAISourceSearchService.ProjectsForPermission(const AScope, AProject, ADirectory: string): TArray<IOTAProject>;
var
  LPlan: TDAISourceSearchPlan;
begin
  LPlan := Prepare(AScope, AProject, ADirectory, 30000);
  Result := LPlan.AffectedProjects;
end;

class function TDAISourceSearchService.Search(const AQuery, AScope, AProject, ADirectory: string; const AOptions: TDAISourceSearchOptions): TJSONObject;
var
  LPlan: TDAISourceSearchPlan;
begin
  LPlan := Prepare(AScope, AProject, ADirectory, AOptions.TimeoutMs);
  Result := SearchPrepared(AQuery, LPlan, AOptions);
end;

class function TDAISourceSearchService.SearchPrepared(const AQuery: string; const APlan: TDAISourceSearchPlan; const AOptions: TDAISourceSearchOptions): TJSONObject;
const
  CMaximumSnapshotCharacters = 2 * 1024 * 1024;
  CMaximumSnapshotTotalCharacters = 16 * 1024 * 1024;
var
  LDirectory: string;
  LFile: string;
  LFileObject: TJSONObject;
  LFiles: TList<string>;
  LFileSet: TDictionary<string, Boolean>;
  LJSONArray: TJSONArray;
  LItem: TJSONValue;
  LOptions: TDAISourceSearchOptions;
  LProject: IOTAProject;
  LProjectKey: string;
  LKnownProject: Boolean;
  LProjectFiles: TJSONArray;
  LPreparationMs: Int64;
  LPreparationTruncated: Boolean;
  LReferenceRoots: TArray<string>;
  LRoot: string;
  LRootArray: TJSONArray;
  LRoots: TList<string>;
  LScope: string;
  LSnapshot: TDAISourceSnapshot;
  LSnapshots: TDictionary<string, TDAISourceSnapshot>;
  LSkippedSnapshots: Integer;
  LSnapshotCharacters: Integer;
  LStopwatch: TStopwatch;
  LTimeout: Integer;
begin
  if (AQuery = '') or (Length(AQuery) > 256) or (Pos(#0, AQuery) > 0) or (Pos(#10, AQuery) > 0) or (Pos(#13, AQuery) > 0) then
    raise EArgumentException.Create('query muss 1 bis 256 Zeichen enthalten, ohne NUL oder Zeilenumbruch.');
  LScope := APlan.Scope;
  LStopwatch := TStopwatch.StartNew;
  LTimeout := AOptions.TimeoutMs;
  if LTimeout = 0 then
    LTimeout := 5000;
  if not InRange(LTimeout, 1, 30000) then
    raise EArgumentOutOfRangeException.Create('timeout_ms muss zwischen 1 und 30000 liegen.');
  LOptions := AOptions;
  LPreparationTruncated := APlan.PreparationTruncated;
  LSnapshotCharacters := 0;
  LSkippedSnapshots := 0;
  LFiles := TList<string>.Create;
  LRoots := TList<string>.Create;
  LFileSet := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  LSnapshots := TDictionary<string, TDAISourceSnapshot>.Create(TIStringComparer.Ordinal);
  try
    for LRoot in APlan.Roots do
      AddPath(LRoots, LRoot);
    for LFile in APlan.ExplicitFiles do
      LFiles.Add(LFile);
    LReferenceRoots := APlan.ReadOnlyRoots;
    LDirectory := APlan.Directory;
    for LFile in LFiles do
      LFileSet.AddOrSetValue(LFile, True);

    // Recheck ownership without broadening the authorized roots or explicit file set.
    // Newly opened buffers are current; a newly affected project requires a fresh authorization.
    if not LPreparationTruncated then
      for LProject in TDAIOTA.Projects do
      begin
        if (LStopwatch.ElapsedMilliseconds + APlan.PreparationMs) >= LTimeout then
        begin
          LPreparationTruncated := True;
          Break;
        end;
        LKnownProject := False;
        LProjectKey := TDAIOTA.ProjectFileName(LProject);
        for var LKey in APlan.ProjectKeys do
          if SameText(LKey, LProjectKey) then
          begin
            LKnownProject := True;
            Break;
          end;
        if LKnownProject then
          Continue;
        LProjectFiles := TDAIFileService.ProjectFiles(LProjectKey);
        try
          for LItem in LProjectFiles do
          begin
            if (LStopwatch.ElapsedMilliseconds + APlan.PreparationMs) >= LTimeout then
            begin
              LPreparationTruncated := True;
              Break;
            end;
            LFile := TDAIOTA.NormalizeFileName(LItem.Value);
            if InsideRoots(LFile, LRoots) or LFileSet.ContainsKey(LFile) then
              raise EInvalidOperation.Create('Ein weiteres Projekt betrifft die Suchpfade. Wiederholen Sie die Anfrage für dessen Berechtigungsprüfung.');
          end;
        finally
          LProjectFiles.Free;
        end;
        if LPreparationTruncated then
          Break;
      end;
    if LPreparationTruncated then
      LJSONArray := TJSONArray.Create
    else
      LJSONArray := TDAIFileService.OpenFiles;
    try
      for LItem in LJSONArray do
      begin
        if (LStopwatch.ElapsedMilliseconds + APlan.PreparationMs) >= LTimeout then
        begin
          Inc(LSkippedSnapshots);
          LPreparationTruncated := True;
          Break;
        end;
        LFile := TDAIOTA.NormalizeFileName(LItem.Value);
        if not InsideRoots(LFile, LRoots) and not LFileSet.ContainsKey(LFile) then
          Continue;
        if not TDAISourceSearch.MatchesFilePatterns(LFile, AOptions.FilePatterns) then
          Continue;
        if not Assigned(TDAIOTA.FindSourceEditor(LFile)) and not TDAIOTA.IsFormLoadedForFile(LFile) then
          Continue;
        LSnapshot.Content := #0;
        LSnapshot.Source := 'unavailable';
        if LSnapshotCharacters >= CMaximumSnapshotTotalCharacters then
        begin
          Inc(LSkippedSnapshots);
          LSnapshots.AddOrSetValue(LFile, LSnapshot);
          Continue;
        end;
        LFileObject := nil;
        try
          try
            LFileObject := TDAIFileService.ReadFile(LFile, CMaximumSnapshotCharacters + 1);
            if LFileObject.GetValue<Boolean>('truncated', False) then
              Inc(LSkippedSnapshots)
            else
            begin
              LSnapshot.Content := LFileObject.GetValue<string>('content', '');
              LSnapshot.Source := LFileObject.GetValue<string>('source', '');
              Inc(LSnapshotCharacters, Length(LSnapshot.Content));
              if LSnapshotCharacters > CMaximumSnapshotTotalCharacters then
              begin
                LSnapshot.Content := #0;
                LSnapshot.Source := 'unavailable';
                Inc(LSkippedSnapshots);
              end;
            end;
          except
            Inc(LSkippedSnapshots);
          end;
        finally
          LFileObject.Free;
        end;
        LSnapshots.AddOrSetValue(LFile, LSnapshot);
      end;
    finally
      LJSONArray.Free;
    end;
    LOptions.TimeoutMs := Max(1, LTimeout - Integer(Min((LStopwatch.ElapsedMilliseconds + APlan.PreparationMs), Int64(LTimeout))));
    LPreparationMs := (LStopwatch.ElapsedMilliseconds + APlan.PreparationMs);
    LPreparationTruncated := LPreparationTruncated or (LPreparationMs >= LTimeout);
    if LPreparationTruncated then
    begin
      LFiles.Clear;
      LSnapshots.Clear;
      Result := TDAISourceSearch.Search(AQuery, [], [], LReferenceRoots, LSnapshots, LOptions);
      Result.RemovePair('truncated').Free;
      Result.AddPair('truncated', TJSONBool.Create(True));
      Result.RemovePair('limit_reason').Free;
      Result.AddPair('limit_reason', 'timeout');
    end
    else
      Result := TDAISourceSearch.Search(AQuery, LRoots.ToArray, LFiles.ToArray, LReferenceRoots, LSnapshots, LOptions);
    Result.AddPair('scope', LScope);
    Result.AddPair('directory', LDirectory);
    Result.RemovePair('elapsed_ms').Free;
    Result.AddPair('elapsed_ms', TJSONNumber.Create((LStopwatch.ElapsedMilliseconds + APlan.PreparationMs)));
    Result.AddPair('preparation_ms', TJSONNumber.Create(LPreparationMs));
    Result.AddPair('preparation_truncated', TJSONBool.Create(LPreparationTruncated));
    Result.AddPair('snapshot_files_skipped', TJSONNumber.Create(LSkippedSnapshots));
    LRootArray := TJSONArray.Create;
    for LRoot in LRoots do
      LRootArray.Add(LRoot);
    Result.AddPair('roots', LRootArray);
  finally
    LSnapshots.Free;
    LFileSet.Free;
    LRoots.Free;
    LFiles.Free;
  end;
end;

end.
