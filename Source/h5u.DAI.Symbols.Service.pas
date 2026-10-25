unit h5u.DAI.Symbols.Service;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.JSON;

type
  TDAISymbolService = class sealed
  public
    class function ListIndexes: TJSONObject; static;
    class function IndexSummary(const AScope: string; const AProjectFile: string = ''): TJSONObject; static;
    class function ContextSummary: TJSONObject; static;
    class function Build(const AScope: string; const AExpectedIdentity: string = ''): TJSONObject; static;
    class function Identity(const AScope: string): string; static;
    class function PermissionSnapshot(const AScope: string): TJSONObject; static;
    class function IndexErrors(const AScope, AExpectedIdentity: string; const AOffset: Integer = 0; const AMaximumRows: Integer = 500): TJSONObject; static;
    class function Delete(const AScope: string; const AExpectedIdentity: string = ''): TJSONObject; static;
    class function JobStatus(const ARequestId: string): TJSONObject; static;
    class function Search(const AScope, AQuery, AVisibility: string; const AMaximumResults: Integer; const AExpectedIdentity: string = ''): TJSONObject; static;
    class function Query(const AScope, ASQL: string; const AParameters: TJSONObject; const AMaximumRows: Integer; const AExpectedIdentity: string = ''): TJSONObject; static;
    class function ProjectKeys(const AScope: string): TArray<string>; static;
    class function AIStatus: TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Hash,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  ToolsAPI,
  Winapi.Windows,
  h5u.DAI.OTA.AI,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Symbols.Parser,
  h5u.DAI.Symbols.Store;

const
  CIndexWarning = 'Deklarationsindex: seit der Erfassung geänderte und ungespeicherte Quellen können abweichen oder fehlen. ' +
    'Vor Verwendung den aktuellen Quelltext lesen. Bedingte Deklarationen sind nicht compilersemantisch aufgelöst.';
  CMaximumFiles = 250000;
  CIndexReadBatchSize = 32;
  CIndexReadBatchBytes = 2 * 1024 * 1024;
  CIndexLargeFileBytes = 1024 * 1024;

type
  TIndexThreadAccess = class(TThread);

  TIndexDescriptor = record
    Scope, Name, Owner, Database: string;
    Roots, Files, Projects: TArray<string>;
  end;

  TIndexJob = class
  public
    Id, Scope, Database, Identity, State, StartedAt, FinishedAt, ErrorText: string;
    Processed, Total, Updated, Skipped, ErrorCount: Integer;
    Errors: TJSONArray;
    Sequence: UInt64;
    Suppressed: Boolean;
    Worker: TThread;
    constructor Create;
    destructor Destroy; override;
  end;

var
  GJobs: TObjectDictionary<string, TIndexJob>;
  GJobLock: TObject;
  GStopping: Boolean;
  GJobSequence: UInt64;

function Timestamp: string;
begin
  Result := DateToISO8601(Now, False);
end;

constructor TIndexJob.Create;
begin
  inherited;
  Errors := TJSONArray.Create;
  State := 'queued';
  StartedAt := Timestamp;
end;

destructor TIndexJob.Destroy;
begin
  Worker.Free;
  Errors.Free;
  inherited;
end;

function IsRunning(const AJob: TIndexJob): Boolean;
begin
  Result := (AJob.State = 'queued') or (AJob.State = 'building');
end;

function JobJson(const AJob: TIndexJob): TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('request_id', AJob.Id).AddPair('scope', AJob.Scope).AddPair('database', AJob.Database)
    .AddPair('identity', AJob.Identity)
    .AddPair('state', AJob.State).AddPair('running', TJSONBool.Create(IsRunning(AJob)))
    .AddPair('started_at', AJob.StartedAt).AddPair('finished_at', AJob.FinishedAt)
    .AddPair('processed_files', TJSONNumber.Create(AJob.Processed)).AddPair('total_files', TJSONNumber.Create(AJob.Total))
    .AddPair('updated_files', TJSONNumber.Create(AJob.Updated)).AddPair('skipped_files', TJSONNumber.Create(AJob.Skipped))
    .AddPair('error_count', TJSONNumber.Create(AJob.ErrorCount)).AddPair('error', AJob.ErrorText)
    .AddPair('errors', AJob.Errors.Clone as TJSONValue).AddPair('errors_has_more', TJSONBool.Create(AJob.ErrorCount > AJob.Errors.Count))
    .AddPair('warning', CIndexWarning);
end;

function WorkspaceIndexDatabase(const AScope, AOwner: string): string;
var
  LBase, LIdentity: string;
begin
  LBase := TPath.GetFileNameWithoutExtension(AOwner);
  LIdentity := Copy(THashSHA2.GetHashString(LowerCase(AOwner)), 1, 16);
  Result := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(AOwner), '.dai'),
    LBase + '.' + AScope + 'index.' + LIdentity + '.sqlite');
end;

function Descriptor(const AScope: string; const AIncludeFiles: Boolean = False; const AProjectFile: string = ''): TIndexDescriptor;
var
  LResult: TIndexDescriptor;
begin
  LResult.Scope := LowerCase(Trim(AScope));
  if LResult.Scope = '' then
    LResult.Scope := 'group';
  if (LResult.Scope <> 'project') and (LResult.Scope <> 'group') and (LResult.Scope <> 'delphi') and (LResult.Scope <> 'getit') then
    raise EArgumentException.Create('scope muss project, group, delphi oder getit sein.');
  if Trim(AProjectFile) <> '' then
  begin
    if (LResult.Scope <> 'project') or AIncludeFiles then
      raise EArgumentException.Create('Eine ausdrückliche Projektdatei ist nur für Projektmetadaten zulässig.');
    // Project rows already supply their own filename; no active-project lookup or IDE activation is needed.
    LResult.Owner := TDAIOTA.NormalizeFileName(AProjectFile);
    LResult.Name := 'Projekt';
    LResult.Database := WorkspaceIndexDatabase('project', LResult.Owner);
    LResult.Projects := TArray<string>.Create(LResult.Owner);
    LResult.Roots := TArray<string>.Create(TPath.GetDirectoryName(LResult.Owner));
    Exit(LResult);
  end;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LGroup: IOTAProjectGroup;
      LProject: IOTAProject;
      LProjects: TArray<IOTAProject>;
      LFiles: TJSONArray;
      LValue: TJSONValue;
      LAllFiles, LRoots, LKeys: TList<string>;
      LRoot, LBase, LIdentity: string;
    begin
      LAllFiles := TList<string>.Create;
      LRoots := TList<string>.Create;
      LKeys := TList<string>.Create;
      try
        if (LResult.Scope = 'project') or (LResult.Scope = 'group') then
        begin
          LProject := TDAIOTA.ActiveProject;
          if LResult.Scope = 'group' then
          begin
            LGroup := TDAIOTA.MainProjectGroup;
            if Assigned(LGroup) then
              LResult.Owner := LGroup.FileName;
          end;
          if LResult.Owner = '' then
          begin
            if Assigned(LProject) then
              LResult.Owner := LProject.FileName;
          end;
          if LResult.Scope = 'group' then
            LResult.Name := 'Projektgruppe'
          else
            LResult.Name := 'Aktuelles Projekt';
          if LResult.Owner <> '' then
          begin
            LResult.Owner := TDAIOTA.NormalizeFileName(LResult.Owner);
            LResult.Database := WorkspaceIndexDatabase(LResult.Scope, LResult.Owner);
            begin
              if LResult.Scope = 'group' then
                LProjects := TDAIOTA.Projects
              else
                LProjects := TArray<IOTAProject>.Create(LProject);
              for LProject in LProjects do
              begin
                if not Assigned(LProject) then
                  Continue;
                LKeys.Add(LProject.FileName);
                LRoots.Add(TPath.GetDirectoryName(LProject.FileName));
                if AIncludeFiles then
                begin
                  LFiles := TDAIFileService.ProjectFiles(LProject.FileName);
                  try
                    for LValue in LFiles do
                      LAllFiles.Add(LValue.Value);
                  finally
                    LFiles.Free;
                  end;
                end;
              end;
            end;
          end;
        end
        else
        begin
          if LResult.Scope = 'delphi' then
          begin
            LResult.Name := 'Delphi / ToolsAPI';
            LRoots.Add(TDAISettings.Instance.DelphiSourceDirectory);
            LRoots.Add(TDAISettings.Instance.ToolsAPIDirectory);
          end
          else
          begin
            LResult.Name := 'GetIt';
            LRoots.Add(TDAISettings.Instance.CatalogRepositoryDirectory);
            LRoots.Add(TDAISettings.Instance.CatalogRepositoryAllUsersDirectory);
          end;
          LResult.Owner := '';
          for LRoot in LRoots do
            if LRoot <> '' then
              LResult.Owner := LResult.Owner + LowerCase(TDAIOTA.NormalizeFileName(LRoot)) + '|';
          LIdentity := Copy(THashSHA2.GetHashString(LResult.Owner), 1, 24);
          LBase := GetEnvironmentVariable('LOCALAPPDATA');
          if LBase = '' then
            raise EInvalidOperation.Create('LOCALAPPDATA ist nicht verfügbar.');
          LResult.Database := TPath.Combine(TPath.Combine(LBase, 'DelphiAI\DAI\Indexes'), LResult.Scope + '-' + LIdentity + '.sqlite');
        end;
        LResult.Roots := LRoots.ToArray;
        LResult.Files := LAllFiles.ToArray;
        LResult.Projects := LKeys.ToArray;
      finally
        LKeys.Free;
        LRoots.Free;
        LAllFiles.Free;
      end;
    end);
  Result := LResult;
end;

function DatabaseMutex(const ADatabase: string): THandle;
var
  LName: string;
  LWait: DWORD;
begin
  LName := 'Global\DelphiAI.DAI.SymbolIndex.' + THashSHA2.GetHashString(LowerCase(ADatabase));
  Result := CreateMutex(nil, False, PChar(LName));
  if Result = 0 then
    RaiseLastOSError;
  LWait := WaitForSingleObject(Result, 0);
  if (LWait <> WAIT_OBJECT_0) and (LWait <> WAIT_ABANDONED) then
  begin
    CloseHandle(Result);
    raise EInvalidOperation.Create('Dieser Index wird bereits in einer anderen IDE bearbeitet.');
  end;
end;

function SourceFile(const AName: string): Boolean;
var
  LExtension: string;
begin
  LExtension := LowerCase(TPath.GetExtension(AName));
  Result := (LExtension = '.pas') or (LExtension = '.inc') or (LExtension = '.dpr') or (LExtension = '.dpk');
end;

function CollectFiles(const ADescriptor: TIndexDescriptor; const AWorker: TThread): TArray<string>;
var
  LFound: TDictionary<string, Byte>;
  LDirectories: TDictionary<string, Byte>;
  LStack: TStack<string>;
  LDirectory, LFileName, LRoot, LKey: string;
  LSearch: TSearchRec;
  LFoundResult: Integer;

  procedure AddFile(const AFileName: string);
  begin
    if not SourceFile(AFileName) then
      Exit;
    LKey := TDAIOTA.NormalizeFileName(AFileName);
    LFound.AddOrSetValue(LKey, 0);
    if LFound.Count > CMaximumFiles then
      raise EInvalidOperation.Create('Der Index umfasst mehr als 250000 Quelldateien.');
  end;

begin
  LFound := TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  LDirectories := TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  LStack := TStack<string>.Create;
  try
    for LFileName in ADescriptor.Files do
      AddFile(LFileName);
    for LRoot in ADescriptor.Roots do
      if (LRoot <> '') and DirectoryExists(LRoot) then
        LStack.Push(TDAIOTA.NormalizeFileName(LRoot));
    while (LStack.Count > 0) and not TIndexThreadAccess(AWorker).Terminated do
    begin
      LDirectory := LStack.Pop;
      if LDirectories.ContainsKey(LDirectory) then
        Continue;
      LDirectories.Add(LDirectory, 0);
      if (GetFileAttributes(PChar(LDirectory)) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        Continue;
      LFoundResult := FindFirst(IncludeTrailingPathDelimiter(LDirectory) + '*', faAnyFile, LSearch);
      if LFoundResult <> 0 then
      begin
        if (LFoundResult <> ERROR_FILE_NOT_FOUND) and (LFoundResult <> ERROR_NO_MORE_FILES) then
          RaiseLastOSError(LFoundResult);
        Continue;
      end;
      try
        repeat
          if TIndexThreadAccess(AWorker).Terminated then
            Break;
          if (LSearch.Name <> '.') and (LSearch.Name <> '..') and ((LSearch.FindData.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0) then
          begin
            LFileName := TPath.Combine(LDirectory, LSearch.Name);
            if (LSearch.Attr and faDirectory) <> 0 then
            begin
              if not MatchText(LSearch.Name, ['.git', '.svn', '.hg', '.dai', 'Build', 'Work', '__history', '__recovery', 'node_modules']) then
                LStack.Push(LFileName);
            end
            else
              AddFile(LFileName);
          end;
          LFoundResult := System.SysUtils.FindNext(LSearch);
        until LFoundResult <> 0;
        if not TIndexThreadAccess(AWorker).Terminated and (LFoundResult <> ERROR_NO_MORE_FILES) then
          RaiseLastOSError(LFoundResult);
      finally
        System.SysUtils.FindClose(LSearch);
      end;
    end;
    Result := LFound.Keys.ToArray;
  finally
    LStack.Free;
    LDirectories.Free;
    LFound.Free;
  end;
end;

procedure SetJobState(const AJob: TIndexJob; const AState: string; const AError: string = '');
begin
  System.TMonitor.Enter(GJobLock);
  try
    AJob.State := AState;
    AJob.ErrorText := AError;
    if not IsRunning(AJob) then
      AJob.FinishedAt := Timestamp;
  finally
    System.TMonitor.Exit(GJobLock);
  end;
end;

function DescriptorIdentity(const ADescriptor: TIndexDescriptor): string; forward;

function IndexReadBatchLength(const AFiles: TArray<string>; const AStart: Integer): Integer;
var
  LBytes, LTotal: Int64;
begin
  Result := 0;
  LTotal := 0;
  while (Result < CIndexReadBatchSize) and (AStart + Result < Length(AFiles)) do
  begin
    LBytes := TFile.GetSize(AFiles[AStart + Result]);
    if LBytes < 0 then
      LBytes := CIndexLargeFileBytes;
    if (Result > 0) and ((LBytes > CIndexLargeFileBytes) or (LTotal + LBytes > CIndexReadBatchBytes)) then
      Break;
    Inc(Result);
    Inc(LTotal, LBytes);
    if LBytes > CIndexLargeFileBytes then
      Break;
  end;
end;

procedure RunBuild(const AJob: TIndexJob; const ADescriptor: TIndexDescriptor);
var
  LStore: TDAISymbolStore;
  LMutex: THandle;
  LFiles: TArray<string>;
  LBatch: TArray<TDAIIndexFileText>;
  LText: TDAIIndexFileText;
  LBatchOffset: Integer;
  LSymbols: TJSONArray;
  LChanged: Boolean;
  LFinalState, LFinalError, LPhase, LSecondaryError: string;
  LReportStarted: Boolean;
begin
  LMutex := 0;
  LStore := nil;
  LFinalState := 'error';
  LFinalError := '';
  LReportStarted := False;
  LPhase := 'Indexauftrag starten';
  try
    try
      SetJobState(AJob, 'building');
      LPhase := 'Index sperren';
      LMutex := DatabaseMutex(ADescriptor.Database);
      LPhase := 'Indexpfad prüfen';
      TDAIOTA.RequireNoReparseWritePath(ADescriptor.Database);
      ForceDirectories(TPath.GetDirectoryName(ADescriptor.Database));
      LStore := TDAISymbolStore.Create(ADescriptor.Database);
      LPhase := 'Indexdatenbank initialisieren';
      LStore.Initialize(ADescriptor.Scope, ADescriptor.Owner);
      LPhase := 'Fehlerbericht beginnen';
      LStore.BeginErrorReport(DescriptorIdentity(ADescriptor), AJob.Id);
      LReportStarted := True;
      LPhase := 'Quelldateien ermitteln';
      LFiles := CollectFiles(ADescriptor, AJob.Worker);
      if TIndexThreadAccess(AJob.Worker).Terminated then
      begin
        LFinalState := 'cancelled';
        LFinalError := 'Indexaufbau beim Beenden oder Entladen der IDE unterbrochen.';
        Exit;
      end;
      System.TMonitor.Enter(GJobLock);
      try
        AJob.Total := Length(LFiles);
      finally
        System.TMonitor.Exit(GJobLock);
      end;
      LBatchOffset := 0;
      while (LBatchOffset < Length(LFiles)) and not TIndexThreadAccess(AJob.Worker).Terminated do
      begin
        LPhase := 'Quelldateien lesen';
        LBatch := TDAIFileService.ReadIndexFiles(Copy(LFiles, LBatchOffset, IndexReadBatchLength(LFiles, LBatchOffset)), CDAIMaxTextFileBytes);
        if Length(LBatch) = 0 then
          raise EInvalidOperation.Create('Ein Index-Lesebatch lieferte trotz vorhandener Quelldateien keine Ergebnisse.');
        LPhase := 'Deklarationen speichern';
        LStore.BeginBatch;
        try
          for LText in LBatch do
          begin
            if TIndexThreadAccess(AJob.Worker).Terminated then
              Break;
            try
              if LText.ErrorText <> '' then
                raise EInvalidOperation.Create(LText.ErrorText);
              LChanged := LStore.FileHash(LText.FileName) <> LText.Sha256;
              if LChanged then
              begin
                LSymbols := TDAISymbolParser.Parse(LText.Content);
                try
                  if TIndexThreadAccess(AJob.Worker).Terminated then
                    Break;
                  LStore.ReplaceFile(LText.FileName, LText.Sha256, LText.Source, LSymbols);
                finally
                  LSymbols.Free;
                end;
              end;
              LStore.ClearError(LText.FileName);
              System.TMonitor.Enter(GJobLock);
              try
                Inc(AJob.Processed);
                if LChanged then
                  Inc(AJob.Updated)
                else
                  Inc(AJob.Skipped);
              finally
                System.TMonitor.Exit(GJobLock);
              end;
            except
              on E: Exception do
              begin
                System.TMonitor.Enter(GJobLock);
                try
                  Inc(AJob.Processed);
                  Inc(AJob.ErrorCount);
                  if AJob.Errors.Count < 50 then
                    AJob.Errors.AddElement(TJSONObject.Create.AddPair('file', LText.FileName).AddPair('error', E.Message));
                finally
                  System.TMonitor.Exit(GJobLock);
                end;
                LStore.RecordError(LText.FileName, E.Message);
              end;
            end;
          end;
          // Commit completed files before reporting cancellation; each failed file rolled back its own savepoint.
          LStore.CommitBatch;
        except
          LStore.RollbackBatch;
          raise;
        end;
        Inc(LBatchOffset, Length(LBatch));
      end;
      if TIndexThreadAccess(AJob.Worker).Terminated then
      begin
        LFinalState := 'cancelled';
        LFinalError := 'Indexaufbau beim Beenden oder Entladen der IDE unterbrochen.';
      end
      else
      begin
        LPhase := 'Alte Fehlerberichte bereinigen';
        LStore.RemoveErrorsExcept(LFiles);
        if AJob.ErrorCount <> 0 then
          LFinalState := 'completed_with_errors'
        else
        begin
          LPhase := 'Entfernte Quelldateien bereinigen';
          LStore.RemoveFilesExcept(LFiles);
          LPhase := 'Indexaktualisierung abschließen';
          LStore.CompleteBuild(DescriptorIdentity(ADescriptor));
          LFinalState := 'completed';
        end;
      end;
    except
      on E: Exception do
      begin
        LFinalState := 'error';
        LFinalError := LPhase + ': ' + E.ClassName + ': ' + E.Message;
      end;
    end;
  finally
    try
      try
        if LReportStarted then
          LStore.FinishBuildState(LFinalState, LFinalError);
      finally
        LStore.Free;
      end;
    except
      on E: Exception do
      begin
        LFinalState := 'error';
        LSecondaryError := 'Abschlussbericht speichern oder Datenbank schließen: ' + E.ClassName + ': ' + E.Message;
        if LFinalError = '' then
          LFinalError := LSecondaryError
        else
          LFinalError := LFinalError + sLineBreak + LSecondaryError;
      end;
    end;
    if LMutex <> 0 then
    begin
      ReleaseMutex(LMutex);
      CloseHandle(LMutex);
    end;
    // A terminal response guarantees that SQLite and its exclusive writer lease are closed.
    SetJobState(AJob, LFinalState, LFinalError);
  end;
end;

function DescriptorIdentity(const ADescriptor: TIndexDescriptor): string;
var
  LProjects: TStringList;
  LProject: string;
begin
  LProjects := TStringList.Create;
  try
    LProjects.Sorted := True;
    for LProject in ADescriptor.Projects do
      LProjects.Add(LowerCase(LProject));
    Result := THashSHA2.GetHashString(ADescriptor.Database + '|' + LProjects.Text);
  finally
    LProjects.Free;
  end;
end;

class function TDAISymbolService.Identity(const AScope: string): string;
begin
  Result := DescriptorIdentity(Descriptor(AScope));
end;

class function TDAISymbolService.PermissionSnapshot(const AScope: string): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LProjects: TJSONArray;
  LKey: string;
begin
  LDescriptor := Descriptor(AScope);
  LProjects := TJSONArray.Create;
  for LKey in LDescriptor.Projects do
    LProjects.Add(LKey);
  Result := TJSONObject.Create.AddPair('identity', DescriptorIdentity(LDescriptor)).AddPair('projects', LProjects);
end;

class function TDAISymbolService.Build(const AScope: string; const AExpectedIdentity: string): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LJob, LExisting: TIndexJob;
  LId: TGUID;
  LExpired: TList<string>;
  LPair: TPair<string, TIndexJob>;
  LKey: string;
begin
  LDescriptor := Descriptor(AScope, True);
  if (AExpectedIdentity <> '') and (AExpectedIdentity <> DescriptorIdentity(LDescriptor)) then
    raise EInvalidOperation.Create('Die Projektauswahl wurde während der Freigabe geändert. Bitte erneut anfordern.');
  if LDescriptor.Database = '' then
    raise EInvalidOperation.Create('Ein gespeichertes Projekt oder eine gespeicherte Projektgruppe muss geöffnet sein.');
  System.TMonitor.Enter(GJobLock);
  try
    if GStopping then
      raise EInvalidOperation.Create('Der Indexdienst wird beendet.');
    for LExisting in GJobs.Values do
      if IsRunning(LExisting) then
        raise EInvalidOperation.Create('Ein Index wird bereits erstellt. Bitte dessen Abschluss abwarten.');
    LExpired := TList<string>.Create;
    try
      for LPair in GJobs do
        if not IsRunning(LPair.Value) and LPair.Value.Worker.Finished then
          LExpired.Add(LPair.Key);
      for LKey in LExpired do
        if GJobs.Count >= 32 then
          GJobs.Remove(LKey);
    finally
      LExpired.Free;
    end;
    LJob := TIndexJob.Create;
    Inc(GJobSequence);
    LJob.Sequence := GJobSequence;
    CreateGUID(LId);
    LJob.Id := GUIDToString(LId);
    LJob.Scope := LDescriptor.Scope;
    LJob.Database := LDescriptor.Database;
    LJob.Identity := DescriptorIdentity(LDescriptor);
    LJob.Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        RunBuild(LJob, LDescriptor);
      end);
    LJob.Worker.FreeOnTerminate := False;
    GJobs.Add(LJob.Id, LJob);
    Result := JobJson(LJob);
    LJob.Worker.Start;
  finally
    System.TMonitor.Exit(GJobLock);
  end;
end;

class function TDAISymbolService.JobStatus(const ARequestId: string): TJSONObject;
var
  LJob: TIndexJob;
begin
  System.TMonitor.Enter(GJobLock);
  try
    if not GJobs.TryGetValue(ARequestId, LJob) then
      raise EArgumentException.Create('Der Indexauftrag ist unbekannt oder abgelaufen.');
    Result := JobJson(LJob);
  finally
    System.TMonitor.Exit(GJobLock);
  end;
end;

function HasCurrentProjectIdentity(const ADescriptor: TIndexDescriptor; const AStatus: TJSONObject): Boolean;
begin
  Result := ((ADescriptor.Scope <> 'project') and (ADescriptor.Scope <> 'group')) or
    (AStatus.GetValue<string>('target_identity', '') = DescriptorIdentity(ADescriptor));
end;

function OpenIndexReader(const ADescriptor: TIndexDescriptor; const ARequireCurrentIdentity: Boolean = True): TDAISymbolStore;
var
  LStatus: TJSONObject;
begin
  TDAIOTA.RequireNoReparseWritePath(ADescriptor.Database);
  Result := TDAISymbolStore.Create(ADescriptor.Database, True);
  try
    LStatus := Result.Status;
    try
      if not SameText(LStatus.GetValue<string>('scope', ''), ADescriptor.Scope) or
        not SameText(LStatus.GetValue<string>('owner', ''), ADescriptor.Owner) then
        raise EInvalidOperation.Create('Der gespeicherte Index gehört zu einem anderen Projekt oder Quellenbereich.');
      if ARequireCurrentIdentity and not HasCurrentProjectIdentity(ADescriptor, LStatus) then
        raise EInvalidOperation.Create('Die Projektzuordnung des Indexes hat sich geändert. Bitte den Index ausdrücklich aktualisieren.');
    finally
      LStatus.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function LatestJobSnapshot(const ADescriptor: TIndexDescriptor; const AIncludeErrors: Boolean): TJSONObject;
var
  LJob, LLatest: TIndexJob;
begin
  Result := nil;
  LLatest := nil;
  System.TMonitor.Enter(GJobLock);
  try
    for LJob in GJobs.Values do
      if not LJob.Suppressed and SameText(LJob.Database, ADescriptor.Database) and
        (LJob.Identity = DescriptorIdentity(ADescriptor)) then
        if (LLatest = nil) or (LJob.Sequence > LLatest.Sequence) then
          LLatest := LJob;
    if LLatest = nil then
      Exit;
    if AIncludeErrors then
      Result := JobJson(LLatest)
    else
      // Public metadata must never include exception text or source filenames.
      Result := TJSONObject.Create.AddPair('request_id', LLatest.Id).AddPair('state', LLatest.State)
        .AddPair('started_at', LLatest.StartedAt).AddPair('finished_at', LLatest.FinishedAt)
        .AddPair('error_count', TJSONNumber.Create(LLatest.ErrorCount));
  finally
    System.TMonitor.Exit(GJobLock);
  end;
end;

function RuntimeJobIsCurrent(const AJob: TJSONObject; const AReportId, ABuildStartedAt, AReportStartedAt: string): Boolean;
var
  LJobAt, LStoredAt, LOtherAt: TDateTime;
  LHasStoredTime: Boolean;
begin
  Result := False;
  if AJob = nil then
    Exit;
  if (AReportId <> '') and (AJob.GetValue<string>('request_id', '') = AReportId) then
    Exit(True);
  LStoredAt := 0;
  LHasStoredTime := TryISO8601ToDate(ABuildStartedAt, LStoredAt, True);
  if TryISO8601ToDate(AReportStartedAt, LOtherAt, True) and (not LHasStoredTime or (LOtherAt > LStoredAt)) then
  begin
    LStoredAt := LOtherAt;
    LHasStoredTime := True;
  end;
  if not LHasStoredTime then
    Exit(True);
  Result := TryISO8601ToDate(AJob.GetValue<string>('started_at', ''), LJobAt, True) and (LJobAt >= LStoredAt);
end;

function RuntimeFailure(const AJob: TJSONObject): Boolean;
var
  LState: string;
begin
  Result := False;
  if AJob = nil then
    Exit;
  LState := AJob.GetValue<string>('state', '');
  Result := (LState = 'error') or (LState = 'cancelled') or (LState = 'completed_with_errors');
end;

function RuntimeErrorPage(const AJob: TJSONObject; const AOffset, AMaximumRows: Integer): TJSONObject;
var
  LAll, LRows: TJSONArray;
  LIndex: Integer;
  LWarning: string;
begin
  LAll := AJob.GetValue<TJSONArray>('errors');
  LRows := TJSONArray.Create;
  Result := TJSONObject.Create.AddPair('errors', LRows);
  try
    LIndex := AOffset;
    while (LIndex < LAll.Count) and (LRows.Count < AMaximumRows) do
    begin
      LRows.AddElement(LAll.Items[LIndex].Clone as TJSONValue);
      Inc(LIndex);
    end;
    for var LName in TArray<string>.Create('request_id', 'scope', 'identity', 'database', 'state', 'error', 'started_at', 'finished_at') do
      Result.AddPair(LName, AJob.GetValue<string>(LName, ''));
    Result.AddPair('total_count', TJSONNumber.Create(LAll.Count)).AddPair('count', TJSONNumber.Create(LRows.Count))
      .AddPair('error_count', TJSONNumber.Create(AJob.GetValue<Integer>('error_count', 0)))
      .AddPair('offset', TJSONNumber.Create(AOffset)).AddPair('limit', TJSONNumber.Create(AMaximumRows))
      .AddPair('has_more', TJSONBool.Create(Int64(AOffset) + LRows.Count < LAll.Count))
      .AddPair('report_source', 'memory');
    LWarning := 'Dieser Fehlerbericht konnte nicht vollständig in der Indexdatei gespeichert werden und ist nur für den aktuellen IDE-Lauf verfügbar.';
    if AJob.GetValue<Integer>('error_count', 0) > LAll.Count then
      LWarning := LWarning + ' Es sind nur die ersten ' + IntToStr(LAll.Count) + ' einzelnen Dateifehler verfügbar.';
    Result.AddPair('storage_warning', LWarning);
  except
    Result.Free;
    raise;
  end;
end;

class function TDAISymbolService.IndexErrors(const AScope, AExpectedIdentity: string; const AOffset, AMaximumRows: Integer): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LStore: TDAISymbolStore;
  LStatus, LRuntime: TJSONObject;
  LIdentity, LReportIdentity, LState, LError: string;
  LCurrent, LRunning, LRuntimeOverride: Boolean;
begin
  if (AOffset < 0) or (AMaximumRows < 1) or (AMaximumRows > 1000) then
    raise EArgumentOutOfRangeException.Create('Fehlerdetails benötigen einen nichtnegativen Offset und 1..1000 Zeilen.');
  LDescriptor := Descriptor(AScope);
  LIdentity := DescriptorIdentity(LDescriptor);
  if AExpectedIdentity <> LIdentity then
    raise EInvalidOperation.Create('Die Projektauswahl wurde geändert. Bitte die Indexliste erneut laden.');
  LRuntime := LatestJobSnapshot(LDescriptor, True);
  LStore := nil;
  LStatus := nil;
  try
    try
      LStore := OpenIndexReader(LDescriptor, False);
      LStatus := LStore.Status;
    except
      if RuntimeFailure(LRuntime) then
        Exit(RuntimeErrorPage(LRuntime, AOffset, AMaximumRows));
      raise;
    end;
    LCurrent := RuntimeJobIsCurrent(LRuntime, LStatus.GetValue<string>('error_request_id', ''),
      LStatus.GetValue<string>('build_started_at', ''), LStatus.GetValue<string>('error_report_started_at', ''));
    if LCurrent and RuntimeFailure(LRuntime) and
      (LRuntime.GetValue<string>('request_id', '') <> LStatus.GetValue<string>('error_request_id', '')) then
      Exit(RuntimeErrorPage(LRuntime, AOffset, AMaximumRows));
    LReportIdentity := LStatus.GetValue<string>('error_target_identity', '');
    if (LReportIdentity <> '') and (LReportIdentity <> LIdentity) then
      raise EInvalidOperation.Create('Der Fehlerbericht gehört zu einer anderen Projektzuordnung. Bitte den Index erneut aktualisieren.');
    if LReportIdentity = LIdentity then
    begin
      try
        Result := LStore.ReadErrors(AOffset, AMaximumRows);
      except
        if LCurrent and RuntimeFailure(LRuntime) then
          Exit(RuntimeErrorPage(LRuntime, AOffset, AMaximumRows));
        raise;
      end;
    end
    else
      Result := TJSONObject.Create.AddPair('errors', TJSONArray.Create).AddPair('total_count', TJSONNumber.Create(0))
        .AddPair('count', TJSONNumber.Create(0)).AddPair('has_more', TJSONBool.Create(False))
        .AddPair('offset', TJSONNumber.Create(AOffset)).AddPair('limit', TJSONNumber.Create(AMaximumRows));
    try
      LState := LStatus.GetValue<string>('last_build_state', '');
      LError := LStatus.GetValue<string>('last_build_error', '');
      LRuntimeOverride := False;
      LRunning := LCurrent and (LRuntime <> nil) and LRuntime.GetValue<Boolean>('running', False);
      if LRunning then
        LState := 'building'
      else if LCurrent and RuntimeFailure(LRuntime) then
      begin
        LRuntimeOverride := (LState <> LRuntime.GetValue<string>('state', '')) or (LError <> LRuntime.GetValue<string>('error', ''));
        LState := LRuntime.GetValue<string>('state', '');
        LError := LRuntime.GetValue<string>('error', '');
      end
      else if (LState = 'building') or (((LState = '') or (LState = 'completed')) and
        (LStatus.GetValue<string>('build_in_progress', '') = 'true')) then
      begin
        LState := 'incomplete';
        LError := 'Der vorige Indexaufbau wurde nicht abgeschlossen oder unerwartet unterbrochen; eine genaue Ursache wurde nicht gespeichert.';
      end;
      Result.AddPair('scope', LDescriptor.Scope).AddPair('identity', LIdentity).AddPair('database', LDescriptor.Database)
        .AddPair('request_id', LStatus.GetValue<string>('error_request_id', ''))
        .AddPair('state', LState).AddPair('error', LError).AddPair('started_at', LStatus.GetValue<string>('build_started_at', ''))
        .AddPair('finished_at', LStatus.GetValue<string>('last_build_finished_at', ''));
      if LRuntimeOverride then
      begin
        Result.RemovePair('finished_at').Free;
        Result.AddPair('finished_at', LRuntime.GetValue<string>('finished_at', '')).AddPair('report_source', 'mixed')
          .AddPair('storage_warning', 'Der aktuelle Abschlussgrund konnte nicht in der Indexdatei gespeichert werden und ist nur für den aktuellen IDE-Lauf verfügbar.');
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    LStatus.Free;
    LStore.Free;
    LRuntime.Free;
  end;
end;

function IndexSizeJson(const ADatabase: string): TJSONValue;
var
  LFile: THandle;
  LSize: Int64;
begin
  Result := TJSONNull.Create;
  if ADatabase = '' then
    Exit;
  LFile := CreateFileW(PWideChar(ADatabase), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if LFile = INVALID_HANDLE_VALUE then
    Exit;
  try
    // Attribute sizes may lag while SQLite holds its database open. Query the live file object instead.
    if GetFileSizeEx(LFile, LSize) and (LSize >= 0) then
    begin
      Result.Free;
      Result := TJSONNumber.Create(LSize);
    end;
  finally
    CloseHandle(LFile);
  end;
end;

function IndexJson(const ADescriptor: TIndexDescriptor): TJSONObject;
var
  LStore: TDAISymbolStore;
  LStatus: TJSONObject;
  LRuntime: TJSONObject;
  LReportId, LBuildStartedAt, LReportStartedAt, LRuntimeState: string;
  LExists: Boolean;
  LErrorCount: Integer;
  LDetailsAvailable: Boolean;
begin
  LErrorCount := 0;
  LDetailsAvailable := False;
  LReportId := '';
  LBuildStartedAt := '';
  LReportStartedAt := '';
  LExists := (ADescriptor.Database <> '') and FileExists(ADescriptor.Database);
  Result := TJSONObject.Create.AddPair('scope', ADescriptor.Scope).AddPair('name', ADescriptor.Name)
    .AddPair('owner', ADescriptor.Owner).AddPair('database', ADescriptor.Database).AddPair('exists', TJSONBool.Create(LExists))
    .AddPair('identity', DescriptorIdentity(ADescriptor));
  LStatus := nil;
  if LExists then
  begin
    try
      LStore := OpenIndexReader(ADescriptor, False);
      try
        LStatus := LStore.Status;
        LReportId := LStatus.GetValue<string>('error_request_id', '');
        LBuildStartedAt := LStatus.GetValue<string>('build_started_at', '');
        LReportStartedAt := LStatus.GetValue<string>('error_report_started_at', '');
        if LStatus.GetValue<string>('error_target_identity', '') = DescriptorIdentity(ADescriptor) then
        begin
          LErrorCount := LStatus.GetValue<Integer>('error_count', 0);
          LDetailsAvailable := (LErrorCount > 0) or (LStatus.GetValue<string>('last_build_state', '') <> 'completed');
        end;
        if ((LStatus.GetValue<string>('error_target_identity', '') = '') or (LStatus.GetValue<string>('last_build_state', '') = 'completed')) and
          (LStatus.GetValue<string>('build_in_progress', '') = 'true') then
          LDetailsAvailable := True;
        Result.AddPair('last_build_state', LStatus.GetValue<string>('last_build_state', ''));
        Result.AddPair('indexed_at', LStatus.GetValue<string>('completed_at', ''));
        Result.AddPair('file_count', TJSONNumber.Create(LStatus.GetValue<Integer>('file_count', 0)));
        Result.AddPair('symbol_count', TJSONNumber.Create(LStatus.GetValue<Integer>('symbol_count', 0)));
        if (LStatus.GetValue<string>('build_in_progress', '') = 'true') or (LStatus.GetValue<string>('last_build_state', '') = 'building') then
          Result.AddPair('state', 'incomplete')
        else if not HasCurrentProjectIdentity(ADescriptor, LStatus) then
          Result.AddPair('state', 'outdated')
        else
          Result.AddPair('state', 'ready');
        Result.AddPair('requires_update', TJSONBool.Create(not HasCurrentProjectIdentity(ADescriptor, LStatus)));
      finally
        LStore.Free;
        LStatus.Free;
      end;
    except
      on E: Exception do
      begin
        Result.AddPair('state', 'error');
        Result.AddPair('error', E.Message);
      end;
    end;
  end
  else
  begin
    Result.AddPair('state', 'missing');
    Result.AddPair('indexed_at', '');
    Result.AddPair('file_count', TJSONNumber.Create(0));
    Result.AddPair('symbol_count', TJSONNumber.Create(0));
  end;
  LRuntime := LatestJobSnapshot(ADescriptor, False);
  try
    if RuntimeJobIsCurrent(LRuntime, LReportId, LBuildStartedAt, LReportStartedAt) then
    begin
      LRuntimeState := LRuntime.GetValue<string>('state', '');
      if (LRuntimeState = 'queued') or (LRuntimeState = 'building') or RuntimeFailure(LRuntime) then
      begin
        Result.RemovePair('state').Free;
        if (LRuntimeState = 'queued') or (LRuntimeState = 'building') then
          Result.AddPair('state', 'building')
        else
        begin
          Result.AddPair('state', 'incomplete');
          LDetailsAvailable := True;
          LErrorCount := LRuntime.GetValue<Integer>('error_count', 0);
        end;
        Result.RemovePair('last_build_state').Free;
        Result.AddPair('last_build_state', LRuntimeState);
        Result.AddPair('request_id', LRuntime.GetValue<string>('request_id', ''));
      end;
    end;
  finally
    LRuntime.Free;
  end;
  Result.AddPair('freshness', 'unknown');
  Result.AddPair('size_bytes', IndexSizeJson(ADescriptor.Database));
  Result.AddPair('error_count', TJSONNumber.Create(LErrorCount)).AddPair('details_available', TJSONBool.Create(LDetailsAvailable));
  Result.AddPair('warning', CIndexWarning);
end;

class function TDAISymbolService.IndexSummary(const AScope, AProjectFile: string): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LStore: TDAISymbolStore;
  LMetadata, LRuntime: TJSONObject;
  LState, LIndexedAt: string;
  LAttributes, LError: DWORD;
  LExists: TJSONValue;
  LNeedsUpdate: Boolean;
begin
  LState := 'error';
  LIndexedAt := '';
  LExists := TJSONNull.Create;
  LNeedsUpdate := False;
  LMetadata := nil;
  LRuntime := nil;
  try
    try
      LDescriptor := Descriptor(AScope, False, AProjectFile);
      if LDescriptor.Database = '' then
      begin
        LExists.Free;
        LExists := TJSONBool.Create(False);
        LState := 'unavailable';
      end
      else
      begin
        LAttributes := GetFileAttributesW(PWideChar(LDescriptor.Database));
        LError := GetLastError;
        if LAttributes = INVALID_FILE_ATTRIBUTES then
        begin
          if (LError = ERROR_FILE_NOT_FOUND) or (LError = ERROR_PATH_NOT_FOUND) then
          begin
            LExists.Free;
            LExists := TJSONBool.Create(False);
            LState := 'missing';
          end;
        end
        else if (LAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
        begin
          LExists.Free;
          LExists := TJSONBool.Create(True);
          TDAIOTA.RequireNoReparseWritePath(LDescriptor.Database);
          LStore := TDAISymbolStore.Create(LDescriptor.Database, True);
          try
            LMetadata := LStore.Metadata;
          finally
            LStore.Free;
          end;
          if not SameText(LMetadata.GetValue<string>('scope', ''), LDescriptor.Scope) or
            not SameText(LMetadata.GetValue<string>('owner', ''), LDescriptor.Owner) then
            raise EInvalidOperation.Create('Die Indexzuordnung stimmt nicht überein.');
          LIndexedAt := LMetadata.GetValue<string>('completed_at', '');
          LNeedsUpdate := not HasCurrentProjectIdentity(LDescriptor, LMetadata);
          if (LMetadata.GetValue<string>('build_in_progress', '') = 'true') or (LMetadata.GetValue<string>('last_build_state', '') = 'building') then
            LState := 'incomplete'
          else if LNeedsUpdate then
            LState := 'outdated'
          else
            LState := 'ready';
        end;
      end;
    except
      // Availability is advisory metadata. Invalid descriptors, inaccessible files and bad databases never break IDE/project discovery.
      LState := 'error';
    end;
    if LDescriptor.Database <> '' then
      try
        LRuntime := LatestJobSnapshot(LDescriptor, False);
        if Assigned(LMetadata) then
          if not RuntimeJobIsCurrent(LRuntime, LMetadata.GetValue<string>('error_request_id', ''),
            LMetadata.GetValue<string>('build_started_at', ''), LMetadata.GetValue<string>('error_report_started_at', '')) then
            FreeAndNil(LRuntime);
        if Assigned(LRuntime) then
          if SameText(LRuntime.GetValue<string>('state', ''), 'queued') or SameText(LRuntime.GetValue<string>('state', ''), 'building') then
            LState := 'building'
          else if RuntimeFailure(LRuntime) then
            LState := 'incomplete';
      except
        LState := 'error';
      end;
    Result := TJSONObject.Create.AddPair('exists', LExists);
    LExists := nil;
    try
      Result.AddPair('state', LState).AddPair('indexed_at', LIndexedAt).AddPair('freshness', 'unknown');
      if LNeedsUpdate then
        Result.AddPair('requires_update', TJSONBool.Create(True));
    except
      Result.Free;
      raise;
    end;
  finally
    LRuntime.Free;
    LMetadata.Free;
    LExists.Free;
  end;
end;

class function TDAISymbolService.ContextSummary: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    for var LScope in TArray<string>.Create('delphi', 'getit', 'group', 'project') do
      Result.AddPair(LScope, IndexSummary(LScope));
  except
    Result.Free;
    raise;
  end;
end;

class function TDAISymbolService.ListIndexes: TJSONObject;
var
  LIndexes: TJSONArray;
  LScope: string;
begin
  LIndexes := TJSONArray.Create;
  Result := TJSONObject.Create.AddPair('indexes', LIndexes).AddPair('warning', CIndexWarning);
  try
    for LScope in TArray<string>.Create('delphi', 'getit', 'group', 'project') do
      LIndexes.AddElement(IndexJson(Descriptor(LScope)));
  except
    Result.Free;
    raise;
  end;
end;

class function TDAISymbolService.Delete(const AScope: string; const AExpectedIdentity: string): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LJob: TIndexJob;
  LMutex: THandle;
  LExists: Boolean;
begin
  LDescriptor := Descriptor(AScope);
  if (AExpectedIdentity <> '') and (AExpectedIdentity <> DescriptorIdentity(LDescriptor)) then
    raise EInvalidOperation.Create('Die Projektauswahl wurde geändert. Bitte die Indexliste erneut laden.');
  if LDescriptor.Database = '' then
    raise EInvalidOperation.Create('Kein gespeichertes Projekt ist geöffnet.');
  System.TMonitor.Enter(GJobLock);
  try
    for LJob in GJobs.Values do
      if SameText(LJob.Database, LDescriptor.Database) and IsRunning(LJob) then
        raise EInvalidOperation.Create('Ein laufender Indexauftrag muss vor dem Löschen beendet werden.');
  finally
    System.TMonitor.Exit(GJobLock);
  end;
  LMutex := DatabaseMutex(LDescriptor.Database);
  try
    TDAIOTA.RequireNoReparseWritePath(LDescriptor.Database);
    LExists := FileExists(LDescriptor.Database);
    TDAISymbolStore.Delete(LDescriptor.Database);
    System.TMonitor.Enter(GJobLock);
    try
      for LJob in GJobs.Values do
        if SameText(LJob.Database, LDescriptor.Database) then
          LJob.Suppressed := True;
    finally
      System.TMonitor.Exit(GJobLock);
    end;
    Result := TJSONObject.Create.AddPair('deleted', TJSONBool.Create(LExists)).AddPair('database', LDescriptor.Database)
      .AddPair('scope', LDescriptor.Scope);
  finally
    ReleaseMutex(LMutex);
    CloseHandle(LMutex);
  end;
end;

function MissingIndex(const ADescriptor: TIndexDescriptor): TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('status', 'index_missing').AddPair('scope', ADescriptor.Scope)
    .AddPair('warning', CIndexWarning).AddPair('next_action', TJSONObject.Create.AddPair('tool', 'project_index_build')
      .AddPair('arguments', TJSONObject.Create.AddPair('scope', ADescriptor.Scope)));
end;

class function TDAISymbolService.Search(const AScope, AQuery, AVisibility: string; const AMaximumResults: Integer; const AExpectedIdentity: string): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LStore: TDAISymbolStore;
begin
  LDescriptor := Descriptor(AScope);
  if (AExpectedIdentity <> '') and (AExpectedIdentity <> DescriptorIdentity(LDescriptor)) then
    raise EInvalidOperation.Create('Die Projektauswahl wurde geändert. Bitte erneut anfordern.');
  if (LDescriptor.Database = '') or not FileExists(LDescriptor.Database) then
    Exit(MissingIndex(LDescriptor));
  LStore := OpenIndexReader(LDescriptor);
  try
    Result := LStore.Search(AQuery, AVisibility, AMaximumResults);
    Result.AddPair('index', LStore.Status).AddPair('freshness', 'unknown').AddPair('warning', CIndexWarning);
  finally
    LStore.Free;
  end;
end;

class function TDAISymbolService.Query(const AScope, ASQL: string; const AParameters: TJSONObject; const AMaximumRows: Integer; const AExpectedIdentity: string): TJSONObject;
var
  LDescriptor: TIndexDescriptor;
  LStore: TDAISymbolStore;
begin
  LDescriptor := Descriptor(AScope);
  if (AExpectedIdentity <> '') and (AExpectedIdentity <> DescriptorIdentity(LDescriptor)) then
    raise EInvalidOperation.Create('Die Projektauswahl wurde geändert. Bitte erneut anfordern.');
  if (LDescriptor.Database = '') or not FileExists(LDescriptor.Database) then
    Exit(MissingIndex(LDescriptor));
  LStore := OpenIndexReader(LDescriptor);
  try
    Result := LStore.Query(ASQL, AParameters, AMaximumRows);
    Result.AddPair('index', LStore.Status).AddPair('freshness', 'unknown').AddPair('warning', CIndexWarning);
  finally
    LStore.Free;
  end;
end;

class function TDAISymbolService.ProjectKeys(const AScope: string): TArray<string>;
begin
  Result := Descriptor(AScope).Projects;
end;

class function TDAISymbolService.AIStatus: TJSONObject;
begin
  Result := TDAIAIService.Status;
end;

class procedure TDAISymbolService.Shutdown;
var
  LWorkers: TList<TThread>;
  LWorker: TThread;
  LJob: TIndexJob;
begin
  LWorkers := TList<TThread>.Create;
  try
    System.TMonitor.Enter(GJobLock);
    try
      GStopping := True;
      for LJob in GJobs.Values do
        if Assigned(LJob.Worker) then
        begin
          LJob.Worker.Terminate;
          LWorkers.Add(LJob.Worker);
        end;
    finally
      System.TMonitor.Exit(GJobLock);
    end;
    for LWorker in LWorkers do
      LWorker.WaitFor;
  finally
    LWorkers.Free;
  end;
end;

initialization
  GJobLock := TObject.Create;
  GJobs := TObjectDictionary<string, TIndexJob>.Create([doOwnsValues]);

finalization
  TDAISymbolService.Shutdown;
  GJobs.Free;
  GJobLock.Free;

end.
