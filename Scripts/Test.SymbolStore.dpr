program TestSymbolStore;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.SysUtils,
  System.SyncObjs,
  Winapi.Windows,
  FireDAC.Comp.Client,
  FireDAC.Stan.Option,
  h5u.DAI.Symbols.Store in '..\Source\h5u.DAI.Symbols.Store.pas';

var
  CheckCount: Integer;

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

function Symbols(const AName: string): TJSONArray;
var
  LSymbol: TJSONObject;
begin
  Result := TJSONArray.Create;
  LSymbol := TJSONObject.Create;
  Result.AddElement(LSymbol);
  LSymbol.AddPair('name', AName);
  LSymbol.AddPair('qualified_name', 'Demo.' + AName);
  LSymbol.AddPair('kind', 'class');
  LSymbol.AddPair('signature', AName + ' = class(TObject)');
  LSymbol.AddPair('start_line', TJSONNumber.Create(12));
  LSymbol.AddPair('end_line', TJSONNumber.Create(30));
  LSymbol.AddPair('ancestor', 'TObject');
  LSymbol.AddPair('members_private', 'FSecret: string;');
  LSymbol.AddPair('members_protected', 'procedure Extend(const Value: string);');
  LSymbol.AddPair('members_public', 'procedure Run(const Value: string);');
  LSymbol.AddPair('members_published', 'property Name: string');
end;

procedure SeedSchemaVersion(const ADatabase, AVersion: string);
var
  LConnection: TFDConnection;
begin
  // Simulate a database produced by another DAI schema version without using the public read-only query API.
  LConnection := TFDConnection.Create(nil);
  try
    LConnection.LoginPrompt := False;
    LConnection.Params.Values['DriverID'] := 'SQLite';
    LConnection.Params.Values['Database'] := ADatabase;
    LConnection.Connected := True;
    LConnection.ExecSQL('UPDATE metadata SET value=:version WHERE key=''schema_version''', [AVersion]);
  finally
    LConnection.Free;
  end;
end;

procedure TestMetadataOnly;
var
  LRoot, LDatabase, LOwner: string;
  LStore: TDAISymbolStore;
  LConnection: TFDConnection;
  LResult: TJSONObject;
  LStarted: UInt64;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolStore-Metadata-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LDatabase := TPath.Combine(LRoot, 'index.sqlite');
    LOwner := TPath.Combine(LRoot, 'Owner.dproj');
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      ExpectFailure(procedure begin LStore.Metadata.Free end, 'Metadata never creates a missing database');
      Check(not TFile.Exists(LDatabase), 'Metadata lookup leaves a missing database absent');
      LStore.Initialize('project', LOwner);
      LStore.BeginErrorReport('membership', 'metadata-test');
      LStore.CompleteBuild('membership');
      LStore.FinishBuildState('error', 'private source details must not be loaded by metadata summaries');
    finally
      LStore.Free;
    end;
    LConnection := TFDConnection.Create(nil);
    try
      LConnection.LoginPrompt := False;
      LConnection.Params.Values['DriverID'] := 'SQLite';
      LConnection.Params.Values['Database'] := LDatabase;
      LConnection.Params.Values['SharedCache'] := 'False';
      LConnection.Params.Values['LockingMode'] := 'Exclusive';
      LConnection.Connected := True;
      LConnection.ExecSQL('UPDATE metadata SET value=value WHERE key=''schema_version''');
      LStore := TDAISymbolStore.Create(LDatabase, True);
      try
        LStarted := GetTickCount64;
        ExpectFailure(procedure begin LStore.Metadata.Free end, 'Advisory metadata reports an exclusive lock instead of waiting for it');
        Check(GetTickCount64 - LStarted < 1000, 'Advisory metadata does not consume the normal five-second SQLite busy timeout');
      finally
        LStore.Free;
      end;
    finally
      LConnection.Free;
    end;
    LConnection := TFDConnection.Create(nil);
    try
      LConnection.LoginPrompt := False;
      LConnection.Params.Values['DriverID'] := 'SQLite';
      LConnection.Params.Values['Database'] := LDatabase;
      LConnection.Connected := True;
      LConnection.ExecSQL('DROP TABLE symbols');
      LConnection.ExecSQL('DROP TABLE files');
      LConnection.ExecSQL('DROP TABLE index_errors');
    finally
      LConnection.Free;
    end;
    LStore := TDAISymbolStore.Create(LDatabase, True);
    try
      LResult := LStore.Metadata;
      try
        Check(LResult.GetValue<string>('scope') = 'project', 'Metadata preserves the index scope');
        Check(LResult.GetValue<string>('owner') = LOwner, 'Metadata supports validating index ownership');
        Check(LResult.GetValue<string>('completed_at') <> '', 'Metadata retains the last successful snapshot date');
        Check(LResult.GetValue<string>('last_build_state') = 'error', 'Metadata retains the build state without its error text');
        Check(LResult.GetValue('file_count') = nil, 'Metadata never counts files');
        Check(LResult.GetValue('symbol_count') = nil, 'Metadata never counts declarations');
        Check(LResult.GetValue('error_count') = nil, 'Metadata never counts file errors');
        Check(LResult.GetValue('last_build_error') = nil, 'Metadata does not fetch private error messages');
        Check(LResult.GetValue('database') = nil, 'Metadata does not append the database path');
      finally
        LResult.Free;
      end;
      ExpectFailure(procedure begin LStore.Status.Free end, 'Full status requires source tables that metadata intentionally never touches');
    finally
      LStore.Free;
    end;
    SeedSchemaVersion(LDatabase, '999');
    LStore := TDAISymbolStore.Create(LDatabase, True);
    try
      ExpectFailure(procedure begin LStore.Metadata.Free end, 'The metadata fast path still rejects unsupported schema versions');
    finally
      LStore.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TestReaderCommitWait;
var
  LRoot, LDatabase, LOwner, LReaderError: string;
  LStore: TDAISymbolStore;
  LReady, LRelease: TEvent;
  LReaderThread, LReleaseThread: TThread;
  LStarted: UInt64;
  LWriterFound: Boolean;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolStore-ReaderCommit-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LDatabase := TPath.Combine(LRoot, 'index.sqlite');
    LOwner := TPath.Combine(LRoot, 'Owner.dproj');
    LStore := TDAISymbolStore.Create(LDatabase);
    LReady := TEvent.Create(nil, True, False, '');
    LRelease := TEvent.Create(nil, True, False, '');
    try
      LStore.Initialize('project', LOwner);
      LStore.BeginErrorReport('membership', 'reader-writer-test');
      LWriterFound := False;
      for var LIndex := 0 to FDManager.ConnectionCount - 1 do
        if FDManager.Connections[LIndex].Connected and (FDManager.Connections[LIndex].Params.Database = LDatabase) then
        begin
          LWriterFound := True;
          Check(FDManager.Connections[LIndex].UpdateOptions.LockWait, 'The actual index writer explicitly enables FireDAC lock waiting');
          Check(Integer(FDManager.Connections[LIndex].ExecSQLScalar('PRAGMA busy_timeout')) = 5000,
            'The actual SQLite writer has an effective five-second busy timeout');
          Check(FDManager.Connections[LIndex].ResourceOptions.CmdExecTimeout = $FFFFFFFF,
            'The lock-wait fix leaves the existing internal writer command policy unchanged');
        end;
      Check(LWriterFound, 'The regression inspected the real store connection');
      LStore.BeginBatch;
      for var LIndex := 0 to 99 do
        LStore.RecordError(TPath.Combine(LRoot, Format('Source%.3d.pas', [LIndex])), 'seed');
      LStore.CommitBatch;
      LReaderError := '';
      LReaderThread := TThread.CreateAnonymousThread(
        procedure
        var
          LConnection: TFDConnection;
          LQuery: TFDQuery;
        begin
          LConnection := TFDConnection.Create(nil);
          LQuery := TFDQuery.Create(nil);
          try
            try
              LConnection.LoginPrompt := False;
              LConnection.Params.Values['DriverID'] := 'SQLite';
              LConnection.Params.Values['Database'] := LDatabase;
              LConnection.Params.Values['OpenMode'] := 'ReadOnly';
              LConnection.Params.Values['SharedCache'] := 'False';
              LConnection.Params.Values['LockingMode'] := 'Normal';
              LConnection.Params.Values['BusyTimeout'] := '5000';
              LConnection.UpdateOptions.LockWait := True;
              LConnection.ResourceOptions.CmdExecTimeout := 2000;
              LConnection.Connected := True;
              LQuery.Connection := LConnection;
              LQuery.FetchOptions.Mode := fmOnDemand;
              LQuery.FetchOptions.RowsetSize := 1;
              LQuery.Open('SELECT path,error FROM index_errors');
              LReady.SetEvent;
              if LRelease.WaitFor(10000) <> wrSignaled then
                raise EInvalidOperation.Create('The controlled reader was not released.');
            except
              on E: Exception do
              begin
                LReaderError := E.ClassName + ': ' + E.Message;
                LReady.SetEvent;
              end;
            end;
          finally
            LQuery.Free;
            LConnection.Free;
          end;
        end);
      LReaderThread.FreeOnTerminate := False;
      LReaderThread.Start;
      try
        Check(LReady.WaitFor(5000) = wrSignaled, 'The real SQLite reader reaches its open cursor');
        Check(LReaderError = '', 'The controlled read-only connection starts successfully');
        LStore.BeginBatch;
        LStore.ClearError(TPath.Combine(LRoot, 'Source000.pas'));
        LReleaseThread := TThread.CreateAnonymousThread(
          procedure
          begin
            TThread.Sleep(200);
            LRelease.SetEvent;
          end);
        LReleaseThread.FreeOnTerminate := False;
        LStarted := GetTickCount64;
        LReleaseThread.Start;
        try
          LStore.CommitBatch;
          Check(GetTickCount64 - LStarted < 5000, 'Commit succeeds after the brief reader releases its shared lock');
        finally
          LReleaseThread.WaitFor;
          LReleaseThread.Free;
        end;
      finally
        LRelease.SetEvent;
        LReaderThread.WaitFor;
        LReaderThread.Free;
      end;
      Check(LReaderError = '', 'The reader closes without a secondary failure');
      LStore.CompleteBuild('membership');
      LStore.FinishBuildState('completed', '');
    finally
      LRelease.Free;
      LReady.Free;
      LStore.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TestAtomicReportStart;
var
  LRoot, LDatabase, LOwner, LStarted: string;
  LStore: TDAISymbolStore;
  LConnection: TFDConnection;
  LStatus: TJSONObject;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolStore-ReportStart-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LDatabase := TPath.Combine(LRoot, 'index.sqlite');
    LOwner := TPath.Combine(LRoot, 'Owner.dproj');
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      LStore.Initialize('project', LOwner);
      LStore.BeginErrorReport('membership', 'completed-request');
      LStore.CompleteBuild('membership');
      LStore.FinishBuildState('completed', '');
      LStatus := LStore.Status;
      try
        LStarted := LStatus.GetValue<string>('build_started_at');
        Check(LStarted = LStatus.GetValue<string>('error_report_started_at'), 'An attempt and its error report share one published start time');
      finally
        LStatus.Free;
      end;
    finally
      LStore.Free;
    end;
    LConnection := TFDConnection.Create(nil);
    try
      LConnection.LoginPrompt := False;
      LConnection.Params.Values['DriverID'] := 'SQLite';
      LConnection.Params.Values['Database'] := LDatabase;
      LConnection.Connected := True;
      LConnection.ExecSQL('CREATE TRIGGER fail_report_start BEFORE INSERT ON metadata WHEN NEW.key=''error_request_id'' ' +
        'BEGIN SELECT RAISE(ABORT,''Controlled report-start failure.''); END');
      LConnection.Connected := False;
      LStore := TDAISymbolStore.Create(LDatabase);
      try
        LStore.Initialize('project', LOwner);
        LStatus := LStore.Status;
        try
          Check(LStatus.GetValue<string>('build_in_progress') = 'false', 'Opening an existing writer leaves the completed attempt unchanged');
          Check(LStatus.GetValue<string>('build_started_at') = LStarted, 'Opening an existing writer does not publish an unmatched newer start');
        finally
          LStatus.Free;
        end;
        ExpectFailure(procedure begin LStore.BeginErrorReport('membership', 'failed-request') end,
          'An injected SQLite report-start failure reaches the caller');
        LStatus := LStore.Status;
        try
          Check(LStatus.GetValue<string>('build_in_progress') = 'false', 'A report-start rollback never leaves a fictitious unfinished attempt');
          Check(LStatus.GetValue<string>('build_started_at') = LStarted, 'A report-start rollback preserves the previous attempt timestamp');
          Check(LStatus.GetValue<string>('error_report_started_at') = LStarted, 'A report-start rollback preserves its matched report timestamp');
          Check(LStatus.GetValue<string>('error_request_id') = 'completed-request', 'A report-start rollback preserves the previous request identity');
          Check(LStatus.GetValue<string>('last_build_state') = 'completed', 'A report-start rollback preserves the last durable result');
        finally
          LStatus.Free;
        end;
        LConnection.Connected := True;
        LConnection.ExecSQL('DROP TRIGGER fail_report_start');
        LConnection.Connected := False;
        LStore.BeginErrorReport('membership', 'successful-retry');
        LStore.CompleteBuild('membership');
        LStore.FinishBuildState('completed', '');
        LStatus := LStore.Status;
        try
          Check(LStatus.GetValue<string>('error_request_id') = 'successful-retry', 'A successful retry publishes the new request identity');
          Check(LStatus.GetValue<string>('build_started_at') = LStatus.GetValue<string>('error_report_started_at'),
            'A successful retry publishes both start markers atomically');
        finally
          LStatus.Free;
        end;
      finally
        LStore.Free;
      end;
    finally
      LConnection.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TestErrorReports;
var
  LRoot, LDatabase, LSource: string;
  LStore: TDAISymbolStore;
  LConnection: TFDConnection;
  LResult: TJSONObject;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolStore-Errors-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LDatabase := TPath.Combine(LRoot, 'errors.sqlite');
    LSource := TPath.Combine(LRoot, 'Owner.dproj');
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      LStore.Initialize('project', LSource);
      LStore.BeginErrorReport('owner-membership-1', 'build-1');
      LStore.BeginBatch;
      for var LIndex := 0 to 56 do
        LStore.RecordError(TPath.Combine(LRoot, Format('Missing%.3d.pas', [LIndex])), 'Lesefehler: Übung ' + IntToStr(LIndex));
      LStore.CommitBatch;
      LStore.FinishBuildState('completed_with_errors', '');
    finally
      LStore.Free;
    end;
    LStore := TDAISymbolStore.Create(LDatabase, True);
    try
      LResult := LStore.Status;
      try
        Check(LResult.GetValue<Integer>('error_count') = 57, 'All file errors survive closing and reopening the store');
        Check(LResult.GetValue<string>('last_build_state') = 'completed_with_errors', 'The final build state survives reopening');
        Check(LResult.GetValue<string>('last_build_finished_at') <> '', 'Build completion time survives reopening');
      finally
        LResult.Free;
      end;
      LResult := LStore.ReadErrors(0, 50);
      try
        Check(LResult.GetValue<Integer>('total_count') = 57, 'Error pagination reports the full count beyond fifty failures');
        Check(LResult.GetValue<TJSONArray>('errors').Count = 50, 'The first error page has the requested size');
        Check(LResult.GetValue<Boolean>('has_more'), 'Additional persisted errors are explicitly advertised');
        Check(LResult.GetValue<TJSONArray>('errors').Items[0].GetValue<string>('error') = 'Lesefehler: Übung 0', 'Error text preserves Unicode');
      finally
        LResult.Free;
      end;
      LResult := LStore.ReadErrors(50, 50);
      try
        Check(LResult.GetValue<TJSONArray>('errors').Count = 7, 'The last page exposes every remaining error');
        Check(not LResult.GetValue<Boolean>('has_more'), 'The last error page has no silent continuation');
      finally
        LResult.Free;
      end;
      ExpectFailure(procedure begin LStore.ReadErrors(-1, 50).Free end, 'Negative error-page offsets are rejected');
      ExpectFailure(procedure begin LStore.ReadErrors(0, 1001).Free end, 'Unbounded error pages are rejected');
      ExpectFailure(procedure begin LStore.RecordError(LSource, 'denied') end, 'Read-only stores cannot write file errors');
      ExpectFailure(procedure begin LStore.FinishBuildState('error', 'denied') end, 'Read-only stores cannot modify build outcomes');
    finally
      LStore.Free;
    end;
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      LStore.Initialize('project', LSource);
      LStore.BeginErrorReport('owner-membership-1', 'build-2');
      LStore.ClearError(TPath.Combine(LRoot, 'Missing000.pas'));
      LStore.RemoveErrorsExcept(TArray<string>.Create(TPath.Combine(LRoot, 'Missing000.pas'), TPath.Combine(LRoot, 'Missing001.pas')));
      LResult := LStore.ReadErrors;
      try
        Check(LResult.GetValue<Integer>('total_count') = 1, 'Successful files and removed sources clear their previous errors');
      finally
        LResult.Free;
      end;
      LStore.BeginErrorReport('changed-project-membership', 'build-3');
      LResult := LStore.ReadErrors;
      try
        Check(LResult.GetValue<Integer>('total_count') = 0, 'A changed ownership identity cannot retain old source-error details');
      finally
        LResult.Free;
      end;
      LStore.FinishBuildState('cancelled', 'Indexaufbau beim Beenden unterbrochen.');
    finally
      LStore.Free;
    end;
    LConnection := TFDConnection.Create(nil);
    try
      LConnection.LoginPrompt := False;
      LConnection.Params.Values['DriverID'] := 'SQLite';
      LConnection.Params.Values['Database'] := LDatabase;
      LConnection.Connected := True;
      LConnection.ExecSQL('DROP TABLE index_errors');
    finally
      LConnection.Free;
    end;
    LStore := TDAISymbolStore.Create(LDatabase, True);
    try
      LResult := LStore.ReadErrors;
      try
        Check(LResult.GetValue<Integer>('total_count') = 0, 'Original schema-one databases without the additive error table remain readable');
      finally
        LResult.Free;
      end;
      LResult := LStore.Status;
      try
        Check(LResult.GetValue<string>('last_build_state') = 'cancelled', 'Interruption state remains after reopening');
        Check(LResult.GetValue<string>('last_build_error').Contains('unterbrochen'), 'Interruption reason remains after reopening');
      finally
        LResult.Free;
      end;
    finally
      LStore.Free;
    end;
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      LStore.Initialize('project', LSource);
      LStore.BeginErrorReport('changed-project-membership', 'build-4');
      LStore.RecordError(LSource, 'Schema-one migration succeeded.');
    finally
      LStore.Free;
    end;
    SeedSchemaVersion(LDatabase, '999');
    LStore := TDAISymbolStore.Create(LDatabase, True);
    try
      ExpectFailure(procedure begin LStore.ReadErrors.Free end, 'Unknown schema versions cannot expose details through the added reader');
    finally
      LStore.Free;
    end;
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TestWriteBatches;
var
  LRoot, LDatabase, LSource, LSecond: string;
  LStore, LReader: TDAISymbolStore;
  LSymbols, LInvalidSymbols: TJSONArray;
  LResult: TJSONObject;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolStore-Batch-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LDatabase := TPath.Combine(LRoot, 'symbols.sqlite');
    LSource := TPath.Combine(LRoot, 'First.pas');
    LSecond := TPath.Combine(LRoot, 'Second.pas');
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      ExpectFailure(procedure begin LStore.BeginBatch end, 'An uninitialized writer cannot begin a batch');
      LStore.Initialize('project', LSource);
      ExpectFailure(procedure begin LStore.CommitBatch end, 'Commit without an active batch is rejected');
      ExpectFailure(procedure begin LStore.RollbackBatch end, 'Rollback without an active batch is rejected');
      LSymbols := Symbols('TOriginal');
      try
        LStore.ReplaceFile(LSource, StringOfChar('a', 64), 'disk', LSymbols);
      finally
        LSymbols.Free;
      end;
      LReader := TDAISymbolStore.Create(LDatabase, True);
      try
        Check(LReader.FileHash(LSource) = StringOfChar('a', 64), 'Standalone ReplaceFile still commits immediately');
        ExpectFailure(procedure begin LReader.BeginBatch end, 'A read-only store cannot begin a batch');
        ExpectFailure(procedure begin LReader.CommitBatch end, 'A read-only store cannot commit a batch');
        ExpectFailure(procedure begin LReader.RollbackBatch end, 'A read-only store cannot roll back a batch');
        LStore.BeginBatch;
        ExpectFailure(procedure begin LStore.BeginBatch end, 'Nested write batches are rejected');
        LSymbols := Symbols('TPending');
        try
          LStore.ReplaceFile(LSource, StringOfChar('b', 64), 'editor_buffer', LSymbols);
          LStore.ReplaceFile(LSecond, StringOfChar('c', 64), 'disk', LSymbols);
        finally
          LSymbols.Free;
        end;
        Check(LStore.FileHash(LSource) = StringOfChar('b', 64), 'Writer sees pending replacement inside its batch');
        Check(LStore.FileHash(LSecond) = StringOfChar('c', 64), 'Writer sees new files before batch commit');
        Check(LReader.FileHash(LSource) = StringOfChar('a', 64), 'External reader retains old file until batch commit');
        Check(LReader.FileHash(LSecond) = '', 'External reader cannot see new uncommitted files');
        LInvalidSymbols := Symbols('TBroken');
        try
          LInvalidSymbols.Add('invalid symbol after one successful row insert');
          ExpectFailure(procedure begin LStore.ReplaceFile(LSource, StringOfChar('d', 64), 'disk', LInvalidSymbols) end,
            'A partially inserted invalid file rolls back to its savepoint');
        finally
          LInvalidSymbols.Free;
        end;
        Check(LStore.FileHash(LSource) = StringOfChar('b', 64), 'File rollback restores its previous pending version');
        Check(LStore.FileHash(LSecond) = StringOfChar('c', 64), 'File rollback preserves earlier successful files in the batch');
        Check(LReader.FileHash(LSource) = StringOfChar('a', 64), 'File savepoint rollback does not publish other pending data');
        LStore.CommitBatch;
        Check(LReader.FileHash(LSource) = StringOfChar('b', 64), 'Batch commit publishes the replacement to other readers');
        Check(LReader.FileHash(LSecond) = StringOfChar('c', 64), 'Batch commit publishes all successfully updated files');
        LResult := LReader.Search('TBroken', 'all', 10);
        try
          Check(LResult.GetValue<Integer>('count') = 0, 'Failed file leaves no partially inserted declarations');
        finally
          LResult.Free;
        end;
        LStore.BeginBatch;
        LSymbols := Symbols('TRolledBack');
        try
          LStore.ReplaceFile(LSource, StringOfChar('e', 64), 'disk', LSymbols);
        finally
          LSymbols.Free;
        end;
        ExpectFailure(procedure begin LStore.RemoveFilesExcept([LSource]) end, 'Pruning cannot implicitly commit an active batch');
        ExpectFailure(procedure begin LStore.CompleteBuild end, 'Build completion cannot implicitly commit an active batch');
        LStore.RollbackBatch;
        Check(LStore.FileHash(LSource) = StringOfChar('b', 64), 'Explicit batch rollback restores committed file hash');
        Check(LReader.FileHash(LSource) = StringOfChar('b', 64), 'Explicit batch rollback never publishes pending data');
        LStore.BeginBatch;
        LSymbols := Symbols('TDestructorRollback');
        try
          LStore.ReplaceFile(LSource, StringOfChar('f', 64), 'disk', LSymbols);
          LStore.ReplaceFile(LSecond, StringOfChar('1', 64), 'disk', LSymbols);
        finally
          LSymbols.Free;
        end;
        FreeAndNil(LStore);
        Check(LReader.FileHash(LSource) = StringOfChar('b', 64), 'Destroying a store rolls back its active batch');
        Check(LReader.FileHash(LSecond) = StringOfChar('c', 64), 'Destructor rollback covers every file in its batch');
        LStore := TDAISymbolStore.Create(LDatabase);
        LStore.Initialize('project', LSource);
        LSymbols := Symbols('TImmediateAgain');
        try
          LStore.ReplaceFile(LSource, StringOfChar('2', 64), 'disk', LSymbols);
        finally
          LSymbols.Free;
        end;
        Check(LReader.FileHash(LSource) = StringOfChar('2', 64), 'Standalone updates still commit after a previous store rollback');
        LStore.CompleteBuild;
      finally
        LReader.Free;
      end;
    finally
      LStore.Free;
    end;
  finally
    // LRoot is one new GUID directory owned by this test under the temporary directory.
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure Run;
var
  LRoot: string;
  LDatabase: string;
  LSource: string;
  LSecond: string;
  LStore: TDAISymbolStore;
  LReadOnly: TDAISymbolStore;
  LSymbols: TJSONArray;
  LResult: TJSONObject;
  LParameters: TJSONObject;
  LQuery: string;
  LSidecar: string;
  LStarted: UInt64;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'DAI-SymbolStore-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LDatabase := TPath.Combine(LRoot, 'nested\symbols.sqlite');
    LSource := TPath.Combine(LRoot, 'Demo.pas');
    LSecond := TPath.Combine(LRoot, 'Second.pas');
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      Check(not TFile.Exists(LDatabase), 'Construction never creates the database');
      ExpectFailure(procedure begin LStore.Status.Free end, 'Status never creates a missing database');
      ExpectFailure(procedure begin LStore.Query('SELECT 1', nil, 10).Free end, 'Query never creates a missing database');
      Check(not TDirectory.Exists(TPath.GetDirectoryName(LDatabase)), 'Read operations do not create the parent directory');
      LStore.Initialize('project', LSource);
      Check(TFile.Exists(LDatabase), 'Explicit initialize creates SQLite database');
      LSymbols := Symbols('TWidget');
      try
        LStore.ReplaceFile(LSource, StringOfChar('a', 64), 'disk', LSymbols);
        LStore.ReplaceFile(UpperCase(LSource), StringOfChar('b', 64), 'editor', LSymbols);
      finally
        LSymbols.Free;
      end;
      LResult := LStore.Status;
      try
        Check(LResult.GetValue<Integer>('file_count') = 1, 'Case-insensitive source paths are deduplicated');
        Check(LResult.GetValue<Integer>('symbol_count') = 1, 'Replacing a source replaces its symbols');
        Check(LResult.GetValue<string>('scope') = 'project', 'Scope is persisted');
      finally
        LResult.Free;
      end;
      Check(LStore.FileHash(LSource) = StringOfChar('b', 64), 'Incremental hash uses normalized path');
      Check(LStore.FileHash(LSecond) = '', 'Unknown source has no stored hash');
      LSymbols := Symbols('TBroken');
      try
        LSymbols.Add('invalid symbol');
        ExpectFailure(procedure begin LStore.ReplaceFile(LSource, StringOfChar('c', 64), 'disk', LSymbols) end,
          'Invalid symbol batch is rejected');
      finally
        LSymbols.Free;
      end;
      Check(LStore.FileHash(LSource) = StringOfChar('b', 64), 'Failed replacement rolls back the source hash');
      LResult := LStore.Search('Widget', 'all', 10);
      try
        Check(LResult.GetValue<TJSONArray>('matches').Count = 1, 'Failed replacement preserves previous symbols');
        Check(LResult.GetValue<TJSONArray>('matches').Items[0].GetValue<Integer>('start_line') = 12, 'Declaration line survives round trip');
      finally
        LResult.Free;
      end;
      for LQuery in ['FSecret', 'Extend', 'Run', 'Name'] do
      begin
        LResult := LStore.Search(LQuery, 'all', 10);
        try
          Check(LResult.GetValue<Integer>('count') = 1, 'Member text is searchable: ' + LQuery);
        finally
          LResult.Free;
        end;
      end;
      LResult := LStore.Search('FSecret', 'public', 10);
      try
        Check(LResult.GetValue<Integer>('count') = 0, 'Visibility selection excludes private member text');
      finally
        LResult.Free;
      end;
      LResult := LStore.Search('%_', 'all', 10);
      try
        Check(LResult.GetValue<Integer>('count') = 0, 'Search wildcard characters are literal text');
      finally
        LResult.Free;
      end;
      LParameters := TJSONObject.Create;
      try
        LParameters.AddPair('needle', 'TWidget');
        LResult := LStore.Query('SELECT name FROM symbols WHERE name=:needle', LParameters, 10);
        try
          Check(LResult.GetValue<Integer>('count') = 1, 'Read SQL binds parameters');
        finally
          LResult.Free;
        end;
      finally
        LParameters.Free;
      end;
      ExpectFailure(procedure begin LStore.Query('SELECT :missing', nil, 10).Free end, 'Missing SQL parameters are rejected');
      LParameters := TJSONObject.Create;
      try
        LParameters.AddPair('value', TJSONNull.Create);
        LResult := LStore.Query('SELECT :value AS n', LParameters, 10);
        try
          Check(LResult.GetValue<TJSONArray>('rows').Items[0].GetValue<TJSONValue>('n') is TJSONNull, 'NULL parameter remains JSON null');
        finally
          LResult.Free;
        end;
      finally
        LParameters.Free;
      end;
      LResult := LStore.Query('WITH q(n) AS (SELECT 1 UNION ALL SELECT 2) SELECT n FROM q', nil, 1);
      try
        Check(LResult.GetValue<Integer>('count') = 1, 'Read query row limit is enforced');
        Check(LResult.GetValue<Boolean>('truncated'), 'Read query reports additional rows');
      finally
        LResult.Free;
      end;
      for LQuery in ['DELETE FROM symbols', 'WITH q AS (SELECT 1) DELETE FROM symbols',
        'SELECT 1; DELETE FROM symbols', 'SELECT 1; SELECT 2', 'PRAGMA query_only=OFF',
        'ATTACH DATABASE '':memory:'' AS other', 'CREATE TEMP TABLE a(n)', 'SELECT load_extension(''x'')',
        'SELECT "load_extension"(''x'')', 'SELECT writefile(''x'',''bad'')', '/* comment */ DELETE FROM files',
        'SELECT * FROM pragma_query_only'] do
        ExpectFailure(procedure begin LStore.Query(LQuery, nil, 10).Free end, 'Dangerous SQL is rejected: ' + LQuery);
      LStarted := GetTickCount64;
      ExpectFailure(
        procedure
        begin
          LStore.Query('WITH RECURSIVE q(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM q) SELECT sum(n) FROM q', nil, 10).Free;
        end, 'Unbounded recursive query is interrupted by SQLite progress callback');
      Check(GetTickCount64 - LStarted < 5000, 'Expensive query is interrupted within the bounded time budget');
      LResult := LStore.Query('SELECT count(*) AS n FROM symbols', nil, 10);
      try
        Check(LResult.GetValue<TJSONArray>('rows').Items[0].GetValue<Integer>('n') = 1, 'A query timeout does not change stored symbols');
      finally
        LResult.Free;
      end;
      LSymbols := Symbols('TOther');
      try
        LStore.ReplaceFile(LSecond, StringOfChar('d', 64), 'disk', LSymbols);
      finally
        LSymbols.Free;
      end;
      LStore.RemoveFilesExcept([LSource]);
      LResult := LStore.Status;
      try
        Check(LResult.GetValue<Integer>('file_count') = 1, 'Deleted files are removed');
        Check(LResult.GetValue<Integer>('symbol_count') = 1, 'File removal cascades to its symbols');
      finally
        LResult.Free;
      end;
      LStore.CompleteBuild;
    finally
      LStore.Free;
    end;
    SeedSchemaVersion(LDatabase, '999');
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      ExpectFailure(procedure begin LStore.Status.Free end, 'Unknown schema is rejected by status reads');
      ExpectFailure(procedure begin LStore.Query('SELECT 1', nil, 10).Free end, 'Unknown schema cannot be queried as a supported index');
      ExpectFailure(procedure begin LStore.Initialize('project', LSource) end, 'Unknown schema cannot be downgraded silently');
    finally
      LStore.Free;
    end;
    SeedSchemaVersion(LDatabase, '1');
    LReadOnly := TDAISymbolStore.Create(LDatabase, True);
    try
      LResult := LReadOnly.Status;
      try
        Check(LResult.GetValue<string>('build_in_progress') = 'false', 'Completed build status is persisted');
        Check(LResult.GetValue<string>('completed_at') <> '', 'Completed build has a UTC timestamp');
      finally
        LResult.Free;
      end;
      ExpectFailure(procedure begin LReadOnly.Initialize('project', LSource) end, 'Read-only store cannot initialize');
      ExpectFailure(procedure begin LReadOnly.CompleteBuild end, 'Read-only store cannot modify metadata');
      LResult := LReadOnly.Query('SELECT COUNT(*) AS n FROM symbols', nil, 10);
      try
        Check(LResult.GetValue<TJSONArray>('rows').Items[0].GetValue<Integer>('n') = 1, 'Persisted SQLite is readable after reopening');
      finally
        LResult.Free;
      end;
    finally
      LReadOnly.Free;
    end;
    LStore := TDAISymbolStore.Create(LDatabase);
    try
      ExpectFailure(procedure begin LStore.Initialize('references', LSource) end, 'Existing scope cannot be silently replaced');
      ExpectFailure(procedure begin LStore.Initialize('project', LSecond) end, 'Existing owner cannot be silently replaced');
      LStore.Initialize('project', LSource);
      Check(LStore.FileHash(LSource) = StringOfChar('b', 64), 'Reopening a writer preserves indexed hashes');
      LStore.CompleteBuild;
    finally
      LStore.Free;
    end;
    for LSidecar in ['-wal', '-shm', '-journal'] do
      TFile.WriteAllText(LDatabase + LSidecar, 'owned test sidecar');
    TFile.WriteAllText(LDatabase + '.unrelated', 'keep');
    TDAISymbolStore.Delete(LDatabase);
    Check(not TFile.Exists(LDatabase), 'Delete removes the selected database');
    for LSidecar in ['-wal', '-shm', '-journal'] do
      Check(not TFile.Exists(LDatabase + LSidecar), 'Delete removes the SQLite sidecar ' + LSidecar);
    Check(TFile.Exists(LDatabase + '.unrelated'), 'Delete preserves unrelated adjacent files');
    Check(not TFile.Exists(LSource), 'Index operations never create or write project source files');
  finally
    // LRoot is a single GUID directory created by this test under the system temporary directory.
    TDirectory.Delete(LRoot, True);
  end;
end;

begin
  try
    TestWriteBatches;
    TestMetadataOnly;
    TestReaderCommitWait;
    TestAtomicReportStart;
    TestErrorReports;
    Run;
    Writeln('Symbol store checks passed: ', CheckCount);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
