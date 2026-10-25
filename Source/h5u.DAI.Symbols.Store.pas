unit h5u.DAI.Symbols.Store;

interface

uses
  System.JSON,
  FireDAC.Comp.Client;

type
  TDAISymbolStore = class sealed
  private
    FDatabasePath: string;
    FReadOnly: Boolean;
    FConnection: TFDConnection;
    FBatchActive: Boolean;
    FErrorRequestId: string;
    function OpenConnection(const AWrite: Boolean; const AMetadataOnly: Boolean = False): TFDConnection;
    procedure RequireWriter;
    procedure SetMetadata(const AName, AValue: string);
    procedure RemoveRowsExcept(const ATableName: string; const AFiles: TArray<string>);
  public
    constructor Create(const ADatabasePath: string; const AReadOnly: Boolean = False);
    destructor Destroy; override;
    procedure Initialize(const AScope, AOwner: string);
    procedure BeginBatch;
    procedure CommitBatch;
    procedure RollbackBatch;
    function Status: TJSONObject;
    function Metadata: TJSONObject;
    procedure BeginErrorReport(const ATargetIdentity, ARequestId: string);
    procedure FinishBuildState(const AState, AError: string);
    procedure RecordError(const AFileName, AError: string);
    procedure ClearError(const AFileName: string);
    procedure RemoveErrorsExcept(const AFiles: TArray<string>);
    function ReadErrors(const AOffset: Integer = 0; const AMaximumRows: Integer = 500): TJSONObject;
    function FileHash(const AFileName: string): string;
    procedure ReplaceFile(const AFileName, ASha256, ASourceKind: string; const ASymbols: TJSONArray);
    procedure RemoveFilesExcept(const AFiles: TArray<string>);
    procedure CompleteBuild(const ATargetIdentity: string = '');
    function Search(const AQuery, AVisibility: string; const AMaximumResults: Integer): TJSONObject;
    function Query(const ASQL: string; const AParameters: TJSONObject; const AMaximumRows: Integer): TJSONObject;
    class procedure Delete(const ADatabasePath: string); static;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteCli,
  FireDAC.Phys.SQLiteWrapper,
  Winapi.Windows,
  FireDAC.Phys.SQLiteWrapper.Stat;

const
  CSchemaVersion = 1;
  CMaximumQueryRows = 1000;
  CMaximumCellCharacters = 65536;

type
  TReadQueryGuard = class
  private
    FDatabase: TSQLiteDatabase;
    FStarted: UInt64;
    procedure Authorize(ADB: TSQLiteDatabase; ACode: Integer; const AArg1, AArg2, AArg3, AArg4: string; var AResult: Integer);
    procedure Progress(ADB: TSQLiteDatabase; var ACancel: Boolean);
  public
    constructor Create(const AConnection: TFDConnection);
    destructor Destroy; override;
  end;

constructor TReadQueryGuard.Create(const AConnection: TFDConnection);
begin
  inherited Create;
  FStarted := GetTickCount64;
  FDatabase := TSQLiteDatabase(AConnection.CliObj);
  FDatabase.OnAutorize := Authorize;
  FDatabase.OnProgress := Progress;
  FDatabase.ProgressNOpers := 1000;
end;

destructor TReadQueryGuard.Destroy;
begin
  FDatabase.OnProgress := nil;
  FDatabase.OnAutorize := nil;
  inherited;
end;

procedure TReadQueryGuard.Authorize(ADB: TSQLiteDatabase; ACode: Integer; const AArg1, AArg2, AArg3, AArg4: string; var AResult: Integer);
begin
  AResult := SQLITE_DENY;
  if (ACode = SQLITE_SELECT) or (ACode = SQLITE_READ) or (ACode = SQLITE_RECURSIVE) then
    AResult := SQLITE_OK
  else if (ACode = SQLITE_FUNCTION) and not MatchText(AArg2, ['load_extension', 'readfile', 'writefile']) then
    AResult := SQLITE_OK;
end;

procedure TReadQueryGuard.Progress(ADB: TSQLiteDatabase; var ACancel: Boolean);
begin
  ACancel := (GetTickCount64 - FStarted) >= 2000;
end;

function UTCNow: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

function FileKey(const AFileName: string): string;
begin
  if (AFileName = '') or not TPath.IsPathRooted(AFileName) then
    raise EArgumentException.Create('An absolute index source path is required.');
  Result := TPath.GetFullPath(AFileName).ToLowerInvariant;
end;

function JSONText(const AObject: TJSONObject; const AName: string): string;
var
  LValue: TJSONValue;
begin
  LValue := AObject.GetValue(AName);
  if (LValue = nil) or (LValue is TJSONNull) then
    Exit('');
  if not (LValue is TJSONString) then
    raise EArgumentException.CreateFmt('Symbol field %s must be a string.', [AName]);
  Result := LValue.Value;
end;

function JSONLine(const AObject: TJSONObject; const AName: string): Integer;
var
  LValue: TJSONValue;
begin
  LValue := AObject.GetValue(AName);
  if (LValue = nil) or (LValue is TJSONNull) then
    Exit(0);
  if not (LValue is TJSONNumber) or not TryStrToInt(LValue.Value, Result) or (Result < 0) then
    raise EArgumentException.CreateFmt('Symbol field %s must be a non-negative line number.', [AName]);
end;

procedure RequireKnownSchema(const AConnection: TFDConnection);
var
  LQuery: TFDQuery;
  LVersion, LScope, LOwner: string;
begin
  LVersion := '';
  LScope := '';
  LOwner := '';
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := AConnection;
    LQuery.Open('SELECT key,value FROM metadata WHERE key IN(''schema_version'',''scope'',''owner'')');
    while not LQuery.Eof do
    begin
      if LQuery.Fields[0].AsString = 'schema_version' then
        LVersion := LQuery.Fields[1].AsString
      else if LQuery.Fields[0].AsString = 'scope' then
        LScope := LQuery.Fields[1].AsString
      else if LQuery.Fields[0].AsString = 'owner' then
        LOwner := LQuery.Fields[1].AsString;
      LQuery.Next;
    end;
    if LVersion <> IntToStr(CSchemaVersion) then
      raise EInvalidOperation.Create('The symbol index uses an unsupported schema version. Recreate it explicitly.');
    if (Trim(LScope) = '') or (Trim(LOwner) = '') then
      raise EInvalidOperation.Create('The symbol index scope and owner metadata are incomplete.');
  finally
    LQuery.Free;
  end;
end;

constructor TDAISymbolStore.Create(const ADatabasePath: string; const AReadOnly: Boolean);
begin
  inherited Create;
  if (ADatabasePath = '') or not TPath.IsPathRooted(ADatabasePath) then
    raise EArgumentException.Create('An absolute index database path is required.');
  FDatabasePath := TPath.GetFullPath(ADatabasePath);
  FReadOnly := AReadOnly;
end;

destructor TDAISymbolStore.Destroy;
begin
  try
    if FBatchActive and (FConnection <> nil) and FConnection.InTransaction then
      FConnection.Rollback;
  finally
    FConnection.Free;
    inherited;
  end;
end;

function TDAISymbolStore.OpenConnection(const AWrite, AMetadataOnly: Boolean): TFDConnection;
begin
  if AWrite and FReadOnly then
    raise EInvalidOperation.Create('The index was opened read-only.');
  if not AWrite and not TFile.Exists(FDatabasePath) then
    raise EInOutError.Create('The requested symbol index does not exist.');
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.Params.Values['DriverID'] := 'SQLite';
    Result.Params.Values['Database'] := FDatabasePath;
    Result.Params.Values['OpenMode'] := IfThen(AWrite, 'CreateUTF8', 'ReadOnly');
    // Separate readers retain the last committed snapshot while a bounded write batch is pending.
    Result.Params.Values['SharedCache'] := 'False';
    Result.Params.Values['LockingMode'] := 'Normal';
    // Optional discovery hints must not wait on locks; normal reads and index writes retain their configured wait.
    Result.Params.Values['BusyTimeout'] := IfThen(AMetadataOnly, '0', '5000');
    // FireDAC otherwise leaves SQLite's busy handler disabled despite the BusyTimeout parameter.
    Result.UpdateOptions.LockWait := True;
    // FireDAC emulates finite timeouts with a worker thread when SQLite has no native command timeout.
    // Trusted index writes must not pay that handoff for every inserted declaration. Public SQL keeps its read guard.
    if AWrite or AMetadataOnly then
      Result.ResourceOptions.CmdExecTimeout := $FFFFFFFF
    else
      Result.ResourceOptions.CmdExecTimeout := 2000;
    Result.Connected := True;
    if AWrite then
      Result.ExecSQL('PRAGMA foreign_keys=ON')
    else
    begin
      Result.ExecSQL('PRAGMA query_only=ON');
      if not AMetadataOnly then
        RequireKnownSchema(Result);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TDAISymbolStore.RequireWriter;
begin
  if FReadOnly or (FConnection = nil) then
    raise EInvalidOperation.Create('Initialize a writable index before modifying it.');
end;

procedure TDAISymbolStore.SetMetadata(const AName, AValue: string);
begin
  RequireWriter;
  FConnection.ExecSQL('INSERT OR REPLACE INTO metadata(key,value) VALUES(:key,:value)', [AName, AValue]);
end;

procedure TDAISymbolStore.BeginBatch;
begin
  RequireWriter;
  if FBatchActive then
    raise EInvalidOperation.Create('An index write batch is already active.');
  FConnection.StartTransaction;
  FBatchActive := True;
end;

procedure TDAISymbolStore.CommitBatch;
begin
  RequireWriter;
  if not FBatchActive then
    raise EInvalidOperation.Create('No index write batch is active.');
  FConnection.Commit;
  FBatchActive := False;
end;

procedure TDAISymbolStore.RollbackBatch;
begin
  RequireWriter;
  if not FBatchActive then
    raise EInvalidOperation.Create('No index write batch is active.');
  try
    FConnection.Rollback;
  finally
    FBatchActive := False;
  end;
end;

procedure TDAISymbolStore.Initialize(const AScope, AOwner: string);
var
  LStatus: TJSONObject;
begin
  if FReadOnly then
    raise EInvalidOperation.Create('The index was opened read-only.');
  if FConnection <> nil then
    raise EInvalidOperation.Create('The index is already initialized.');
  if (Trim(AScope) = '') or (Trim(AOwner) = '') then
    raise EArgumentException.Create('Index scope and owner are required.');
  if TFile.Exists(FDatabasePath) then
  begin
    LStatus := Status;
    try
      if LStatus.GetValue<string>('schema_version', '') <> IntToStr(CSchemaVersion) then
        raise EInvalidOperation.Create('The symbol index uses an unsupported schema version. Recreate it explicitly.');
      if not SameText(LStatus.GetValue<string>('scope', ''), AScope) or not SameText(LStatus.GetValue<string>('owner', ''), AOwner) then
        raise EInvalidOperation.Create('The existing symbol index belongs to a different scope or owner.');
    finally
      LStatus.Free;
    end;
  end;
  ForceDirectories(TPath.GetDirectoryName(FDatabasePath));
  FConnection := OpenConnection(True);
  FConnection.StartTransaction;
  try
    FConnection.ExecSQL('CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL)');
    FConnection.ExecSQL('CREATE TABLE IF NOT EXISTS files(file_key TEXT PRIMARY KEY,path TEXT NOT NULL,' +
      'sha256 TEXT NOT NULL,source_kind TEXT NOT NULL,indexed_at TEXT NOT NULL)');
    FConnection.ExecSQL('CREATE TABLE IF NOT EXISTS symbols(id INTEGER PRIMARY KEY,file_key TEXT NOT NULL ' +
      'REFERENCES files(file_key) ON DELETE CASCADE,name TEXT NOT NULL,qualified_name TEXT NOT NULL,kind TEXT NOT NULL,' +
      'signature TEXT NOT NULL,start_line INTEGER NOT NULL,end_line INTEGER NOT NULL,ancestor TEXT NOT NULL,' +
      'members_private TEXT NOT NULL,members_protected TEXT NOT NULL,members_public TEXT NOT NULL,members_published TEXT NOT NULL)');
    FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS symbols_name ON symbols(name COLLATE NOCASE)');
    FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS symbols_file ON symbols(file_key)');
    FConnection.ExecSQL('CREATE TABLE IF NOT EXISTS index_errors(file_key TEXT PRIMARY KEY,path TEXT NOT NULL,' +
      'error TEXT NOT NULL,recorded_at TEXT NOT NULL,request_id TEXT NOT NULL)');
    SetMetadata('schema_version', IntToStr(CSchemaVersion));
    SetMetadata('scope', AScope);
    SetMetadata('owner', AOwner);
    FConnection.Commit;
  except
    FConnection.Rollback;
    FreeAndNil(FConnection);
    raise;
  end;
end;

function HasErrorTable(const AConnection: TFDConnection): Boolean;
begin
  Result := Integer(AConnection.ExecSQLScalar('SELECT COUNT(*) FROM sqlite_master WHERE type=''table'' AND name=''index_errors''')) <> 0;
end;

procedure TDAISymbolStore.BeginErrorReport(const ATargetIdentity, ARequestId: string);
var
  LPreviousIdentity, LStartedAt: string;
begin
  RequireWriter;
  if FBatchActive then
    raise EInvalidOperation.Create('An active index batch cannot start a new error report.');
  FConnection.StartTransaction;
  try
    LPreviousIdentity := VarToStr(FConnection.ExecSQLScalar('SELECT value FROM metadata WHERE key=''error_target_identity'''));
    if LPreviousIdentity <> ATargetIdentity then
      FConnection.ExecSQL('DELETE FROM index_errors');
    SetMetadata('error_target_identity', ATargetIdentity);
    SetMetadata('error_request_id', ARequestId);
    LStartedAt := UTCNow;
    // Publish the attempt and its report together. A failed report start must not leave a newer, unexplained build marker.
    SetMetadata('build_started_at', LStartedAt);
    SetMetadata('build_in_progress', 'true');
    SetMetadata('error_report_started_at', LStartedAt);
    SetMetadata('last_build_state', 'building');
    SetMetadata('last_build_error', '');
    SetMetadata('last_build_finished_at', '');
    FConnection.Commit;
    FErrorRequestId := ARequestId;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TDAISymbolStore.RecordError(const AFileName, AError: string);
begin
  RequireWriter;
  FConnection.ExecSQL('INSERT OR REPLACE INTO index_errors(file_key,path,error,recorded_at,request_id) VALUES(:key,:path,:error,:at,:request)',
    [FileKey(AFileName), AFileName, AError, UTCNow, FErrorRequestId]);
end;

procedure TDAISymbolStore.FinishBuildState(const AState, AError: string);
begin
  RequireWriter;
  if FBatchActive then
    raise EInvalidOperation.Create('Commit or roll back the active batch before finishing its build report.');
  FConnection.StartTransaction;
  try
    SetMetadata('last_build_state', AState);
    SetMetadata('last_build_error', AError);
    SetMetadata('last_build_finished_at', UTCNow);
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TDAISymbolStore.ClearError(const AFileName: string);
begin
  RequireWriter;
  FConnection.ExecSQL('DELETE FROM index_errors WHERE file_key=:key', [FileKey(AFileName)]);
end;

function TDAISymbolStore.ReadErrors(const AOffset, AMaximumRows: Integer): TJSONObject;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LErrors: TJSONArray;
  LTotal: Integer;
begin
  if (AOffset < 0) or (AMaximumRows < 1) or (AMaximumRows > 1000) then
    raise EArgumentOutOfRangeException.Create('Error pages require a non-negative offset and 1..1000 rows.');
  LConnection := OpenConnection(False);
  try
    LErrors := TJSONArray.Create;
    Result := TJSONObject.Create.AddPair('errors', LErrors);
    try
      LTotal := 0;
      if HasErrorTable(LConnection) then
      begin
        LTotal := LConnection.ExecSQLScalar('SELECT COUNT(*) FROM index_errors');
        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := LConnection;
          LQuery.SQL.Text := 'SELECT path,error,recorded_at,request_id FROM index_errors ORDER BY file_key LIMIT :limit OFFSET :offset';
          LQuery.ParamByName('limit').AsInteger := AMaximumRows;
          LQuery.ParamByName('offset').AsInteger := AOffset;
          LQuery.Open;
          while not LQuery.Eof do
          begin
            LErrors.AddElement(TJSONObject.Create.AddPair('file', LQuery.Fields[0].AsString).AddPair('error', LQuery.Fields[1].AsString)
              .AddPair('recorded_at', LQuery.Fields[2].AsString).AddPair('request_id', LQuery.Fields[3].AsString));
            LQuery.Next;
          end;
        finally
          LQuery.Free;
        end;
      end;
      Result.AddPair('total_count', TJSONNumber.Create(LTotal)).AddPair('count', TJSONNumber.Create(LErrors.Count))
        .AddPair('offset', TJSONNumber.Create(AOffset)).AddPair('limit', TJSONNumber.Create(AMaximumRows))
        .AddPair('has_more', TJSONBool.Create(Int64(AOffset) + LErrors.Count < LTotal));
    except
      Result.Free;
      raise;
    end;
  finally
    LConnection.Free;
  end;
end;

function TDAISymbolStore.Metadata: TJSONObject;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LGuard: TReadQueryGuard;
begin
  LConnection := OpenConnection(False, True);
  LGuard := nil;
  try
    // A fixed, bounded metadata query needs no FireDAC timeout worker; SQLite's native read guard still applies.
    LGuard := TReadQueryGuard.Create(LConnection);
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      LQuery.Open('SELECT key,value FROM metadata WHERE key IN(''schema_version'',''scope'',''owner'',''completed_at'',''target_identity'',' +
        '''build_in_progress'',''last_build_state'',''error_request_id'',''build_started_at'',''error_report_started_at'') LIMIT 16');
      Result := TJSONObject.Create;
      try
        while not LQuery.Eof do
        begin
          Result.AddPair(LQuery.Fields[0].AsString, LQuery.Fields[1].AsString);
          LQuery.Next;
        end;
        if Result.GetValue<string>('schema_version', '') <> IntToStr(CSchemaVersion) then
          raise EInvalidOperation.Create('The symbol index uses an unsupported schema version.');
        if (Trim(Result.GetValue<string>('scope', '')) = '') or (Trim(Result.GetValue<string>('owner', '')) = '') then
          raise EInvalidOperation.Create('The symbol index scope and owner metadata are incomplete.');
      except
        Result.Free;
        raise;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LGuard.Free;
    LConnection.Free;
  end;
end;

function TDAISymbolStore.Status: TJSONObject;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
begin
  LConnection := OpenConnection(False);
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      Result := TJSONObject.Create;
      try
        Result.AddPair('database', FDatabasePath);
        LQuery.Open('SELECT key,value FROM metadata ORDER BY key');
        while not LQuery.Eof do
        begin
          Result.AddPair(LQuery.Fields[0].AsString, LQuery.Fields[1].AsString);
          LQuery.Next;
        end;
        LQuery.Close;
        LQuery.Open('SELECT (SELECT COUNT(*) FROM files) AS file_count,(SELECT COUNT(*) FROM symbols) AS symbol_count');
        Result.AddPair('file_count', TJSONNumber.Create(LQuery.Fields[0].AsLargeInt));
        Result.AddPair('symbol_count', TJSONNumber.Create(LQuery.Fields[1].AsLargeInt));
        LQuery.Close;
        if HasErrorTable(LConnection) then
          Result.AddPair('error_count', TJSONNumber.Create(Int64(LConnection.ExecSQLScalar('SELECT COUNT(*) FROM index_errors'))))
        else
          Result.AddPair('error_count', TJSONNumber.Create(0));
      except
        Result.Free;
        raise;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LConnection.Free;
  end;
end;

function TDAISymbolStore.FileHash(const AFileName: string): string;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LOwnConnection: Boolean;
begin
  LOwnConnection := FConnection = nil;
  if LOwnConnection then
    LConnection := OpenConnection(False)
  else
    LConnection := FConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      LQuery.SQL.Text := 'SELECT sha256 FROM files WHERE file_key=:key';
      LQuery.ParamByName('key').AsString := FileKey(AFileName);
      LQuery.Open;
      if LQuery.Eof then
        Result := ''
      else
        Result := LQuery.Fields[0].AsString;
    finally
      LQuery.Free;
    end;
  finally
    if LOwnConnection then
      LConnection.Free;
  end;
end;

procedure TDAISymbolStore.ReplaceFile(const AFileName, ASha256, ASourceKind: string; const ASymbols: TJSONArray);
const
  CTextFields: array[0..8] of string = ('name', 'qualified_name', 'kind', 'signature', 'ancestor',
    'members_private', 'members_protected', 'members_public', 'members_published');
var
  LKey: string;
  LItem: TJSONValue;
  LSymbol: TJSONObject;
  LQuery: TFDQuery;
  LName: string;
  LStartLine: Integer;
  LEndLine: Integer;
  LCharacter: Char;
  LOwnTransaction: Boolean;
begin
  RequireWriter;
  LKey := FileKey(AFileName);
  if (ASymbols = nil) or (Length(ASha256) <> 64) then
    raise EArgumentException.Create('A SHA-256 hash and symbol array are required.');
  for LCharacter in ASha256 do
    if not CharInSet(LCharacter, ['0'..'9', 'a'..'f', 'A'..'F']) then
      raise EArgumentException.Create('The source hash must contain hexadecimal SHA-256 digits.');
  LOwnTransaction := not FBatchActive;
  if LOwnTransaction then
    FConnection.StartTransaction
  else
    FConnection.ExecSQL('SAVEPOINT dai_replace_file');
  try
    FConnection.ExecSQL('DELETE FROM files WHERE file_key=:key', [LKey]);
    FConnection.ExecSQL('INSERT INTO files(file_key,path,sha256,source_kind,indexed_at) VALUES(:key,:path,:hash,:kind,:at)',
      [LKey, TPath.GetFullPath(AFileName), LowerCase(ASha256), ASourceKind, UTCNow]);
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := FConnection;
      LQuery.SQL.Text := 'INSERT INTO symbols(file_key,name,qualified_name,kind,signature,start_line,end_line,ancestor,' +
        'members_private,members_protected,members_public,members_published) VALUES(:key,:name,:qualified_name,:kind,:signature,' +
        ':start_line,:end_line,:ancestor,:members_private,:members_protected,:members_public,:members_published)';
      for LItem in ASymbols do
      begin
        if not (LItem is TJSONObject) then
          raise EArgumentException.Create('Each indexed symbol must be an object.');
        LSymbol := TJSONObject(LItem);
        if (JSONText(LSymbol, 'name') = '') or (JSONText(LSymbol, 'kind') = '') then
          raise EArgumentException.Create('Indexed symbols require a name and kind.');
        LStartLine := JSONLine(LSymbol, 'start_line');
        LEndLine := JSONLine(LSymbol, 'end_line');
        if (LEndLine > 0) and (LEndLine < LStartLine) then
          raise EArgumentException.Create('An indexed declaration must end at or after its start line.');
        LQuery.ParamByName('key').AsString := LKey;
        for LName in CTextFields do
          LQuery.ParamByName(LName).AsWideString := JSONText(LSymbol, LName);
        LQuery.ParamByName('start_line').AsInteger := LStartLine;
        LQuery.ParamByName('end_line').AsInteger := LEndLine;
        LQuery.ExecSQL;
      end;
    finally
      LQuery.Free;
    end;
    if LOwnTransaction then
      FConnection.Commit
    else
      FConnection.ExecSQL('RELEASE SAVEPOINT dai_replace_file');
  except
    if LOwnTransaction then
      FConnection.Rollback
    else
    begin
      FConnection.ExecSQL('ROLLBACK TO SAVEPOINT dai_replace_file');
      FConnection.ExecSQL('RELEASE SAVEPOINT dai_replace_file');
    end;
    raise;
  end;
end;

procedure TDAISymbolStore.RemoveRowsExcept(const ATableName: string; const AFiles: TArray<string>);
var
  LFiles: TDictionary<string, Boolean>;
  LDelete: TList<string>;
  LFile: string;
  LQuery: TFDQuery;
begin
  RequireWriter;
  if FBatchActive then
    raise EInvalidOperation.Create('Commit or roll back the active index batch before pruning files.');
  LFiles := TDictionary<string, Boolean>.Create;
  try
    for LFile in AFiles do
      LFiles.AddOrSetValue(FileKey(LFile), True);
    LDelete := TList<string>.Create;
    try
      LQuery := TFDQuery.Create(nil);
      try
        LQuery.Connection := FConnection;
        LQuery.Open('SELECT file_key FROM ' + ATableName);
        while not LQuery.Eof do
        begin
          LFile := LQuery.Fields[0].AsString;
          if not LFiles.ContainsKey(LFile) then
            LDelete.Add(LFile);
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
      FConnection.StartTransaction;
      try
        for LFile in LDelete do
          FConnection.ExecSQL('DELETE FROM ' + ATableName + ' WHERE file_key=:key', [LFile]);
        FConnection.Commit;
      except
        FConnection.Rollback;
        raise;
      end;
    finally
      LDelete.Free;
    end;
  finally
    LFiles.Free;
  end;
end;

procedure TDAISymbolStore.RemoveFilesExcept(const AFiles: TArray<string>);
begin
  RemoveRowsExcept('files', AFiles);
end;

procedure TDAISymbolStore.RemoveErrorsExcept(const AFiles: TArray<string>);
begin
  RemoveRowsExcept('index_errors', AFiles);
end;

procedure TDAISymbolStore.CompleteBuild(const ATargetIdentity: string);
begin
  RequireWriter;
  if FBatchActive then
    raise EInvalidOperation.Create('Commit or roll back the active index batch before completing the build.');
  FConnection.StartTransaction;
  try
    SetMetadata('completed_at', UTCNow);
    SetMetadata('build_in_progress', 'false');
    // Publish changed project membership only after the service has pruned obsolete source files.
    if ATargetIdentity <> '' then
      SetMetadata('target_identity', ATargetIdentity);
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure ValidateReadSQL(const ASQL: string);
var
  LIndex: Integer;
  LStart: Integer;
  LToken: string;
  LFirst: Boolean;
  LQuote: Char;
begin
  if (Length(ASQL) = 0) or (Length(ASQL) > 65536) or (Pos(#0, ASQL) <> 0) then
    raise EArgumentException.Create('A read query of at most 65536 characters is required.');
  if ContainsText(ASQL, 'load_extension') or ContainsText(ASQL, 'writefile') or ContainsText(ASQL, 'readfile') then
    raise EArgumentException.Create('SQLite extension and file functions are not allowed.');
  LIndex := 1;
  LFirst := True;
  while LIndex <= Length(ASQL) do
  begin
    if CharInSet(ASQL[LIndex], [#9, #10, #13, ' ']) then
      Inc(LIndex)
    else if (ASQL[LIndex] = '-') and (LIndex < Length(ASQL)) and (ASQL[LIndex + 1] = '-') then
    begin
      while (LIndex <= Length(ASQL)) and not CharInSet(ASQL[LIndex], [#10, #13]) do
        Inc(LIndex);
    end
    else if (ASQL[LIndex] = '/') and (LIndex < Length(ASQL)) and (ASQL[LIndex + 1] = '*') then
    begin
      Inc(LIndex, 2);
      while (LIndex < Length(ASQL)) and not ((ASQL[LIndex] = '*') and (ASQL[LIndex + 1] = '/')) do
        Inc(LIndex);
      if LIndex >= Length(ASQL) then
        raise EArgumentException.Create('Unterminated SQL comment.');
      Inc(LIndex, 2);
    end
    else if CharInSet(ASQL[LIndex], ['''', '"', '`', '[']) then
    begin
      if LFirst then
        raise EArgumentException.Create('Only SELECT and WITH queries are allowed.');
      LQuote := ASQL[LIndex];
      if LQuote = '[' then
        LQuote := ']';
      Inc(LIndex);
      while LIndex <= Length(ASQL) do
      begin
        if ASQL[LIndex] = LQuote then
        begin
          Inc(LIndex);
          if (LIndex <= Length(ASQL)) and (ASQL[LIndex] = LQuote) and (LQuote <> ']') then
            Inc(LIndex)
          else
            Break;
        end
        else
          Inc(LIndex);
      end;
    end
    else if CharInSet(ASQL[LIndex], ['a'..'z', 'A'..'Z', '_']) then
    begin
      LStart := LIndex;
      while (LIndex <= Length(ASQL)) and CharInSet(ASQL[LIndex], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
        Inc(LIndex);
      LToken := UpperCase(Copy(ASQL, LStart, LIndex - LStart));
      if LFirst and not MatchText(LToken, ['SELECT', 'WITH']) then
        raise EArgumentException.Create('Only SELECT and WITH queries are allowed.');
      LFirst := False;
      if MatchText(LToken, ['ATTACH', 'DETACH', 'PRAGMA', 'CREATE', 'ALTER', 'DROP', 'INSERT', 'UPDATE', 'DELETE',
        'REPLACE', 'VACUUM', 'REINDEX', 'ANALYZE', 'BEGIN', 'COMMIT', 'ROLLBACK', 'SAVEPOINT', 'RELEASE']) then
        raise EArgumentException.Create('Only read-only SQL queries are allowed.');
    end
    else
    begin
      if LFirst or (ASQL[LIndex] = ';') then
        raise EArgumentException.Create('Exactly one SELECT or WITH query without a semicolon is required.');
      Inc(LIndex);
    end;
  end;
  if LFirst then
    raise EArgumentException.Create('An SQL query is required.');
end;

function JSONField(const AField: TField; out ATruncated: Boolean): TJSONValue;
var
  LText: string;
  LFloat: Double;
begin
  ATruncated := False;
  if AField.IsNull then
    Exit(TJSONNull.Create);
  case AField.DataType of
    ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint, ftLongWord, ftShortint, ftByte:
      Result := TJSONNumber.Create(AField.AsLargeInt);
    ftBoolean:
      Result := TJSONBool.Create(AField.AsBoolean);
    ftFloat, ftCurrency, ftBCD, ftFMTBcd, ftExtended, ftSingle:
      begin
        LFloat := AField.AsFloat;
        if IsNan(LFloat) or IsInfinite(LFloat) then
          Result := TJSONNull.Create
        else
          Result := TJSONNumber.Create(LFloat);
      end;
  else
    LText := AField.AsString;
    ATruncated := Length(LText) > CMaximumCellCharacters;
    if ATruncated then
      SetLength(LText, CMaximumCellCharacters);
    Result := TJSONString.Create(LText);
  end;
end;

function TDAISymbolStore.Query(const ASQL: string; const AParameters: TJSONObject; const AMaximumRows: Integer): TJSONObject;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LPair: TJSONPair;
  LParameter: TFDParam;
  LColumns: TJSONArray;
  LRows: TJSONArray;
  LRow: TJSONObject;
  LField: TField;
  LValue: TJSONValue;
  LInteger: Int64;
  LNumber: Double;
  LTruncated: Boolean;
  LCellTruncated: Boolean;
  LIndex: Integer;
  LGuard: TReadQueryGuard;
begin
  ValidateReadSQL(ASQL);
  if (AMaximumRows < 1) or (AMaximumRows > CMaximumQueryRows) then
    raise EArgumentOutOfRangeException.Create('maximum_rows must be between 1 and 1000.');
  LConnection := OpenConnection(False);
  LGuard := nil;
  try
    LGuard := TReadQueryGuard.Create(LConnection);
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      // Validate exactly the SQL that SQLite receives; FireDAC macro/escape rewriting is not part of this API.
      LQuery.ResourceOptions.MacroCreate := False;
      LQuery.ResourceOptions.MacroExpand := False;
      LQuery.ResourceOptions.EscapeExpand := False;
      LQuery.SQL.Text := 'SELECT * FROM (' + ASQL + ') LIMIT ' + IntToStr(AMaximumRows + 1);
      if AParameters <> nil then
        for LPair in AParameters do
        begin
          LParameter := LQuery.Params.FindParam(LPair.JsonString.Value);
          if LParameter = nil then
            raise EArgumentException.CreateFmt('Unknown SQL parameter: %s', [LPair.JsonString.Value]);
          LValue := LPair.JsonValue;
          if LValue is TJSONNull then
          begin
            LParameter.DataType := ftWideString;
            LParameter.Clear;
            LParameter.Bound := True;
          end
          else if LValue is TJSONString then
            LParameter.AsWideString := LValue.Value
          else if LValue is TJSONBool then
            LParameter.AsBoolean := TJSONBool(LValue).AsBoolean
          else if LValue is TJSONNumber then
          begin
            if TryStrToInt64(LValue.Value, LInteger) then
              LParameter.AsLargeInt := LInteger
            else if TryStrToFloat(LValue.Value, LNumber, TFormatSettings.Invariant) and not IsInfinite(LNumber) and not IsNan(LNumber) then
              LParameter.AsFloat := LNumber
            else
              raise EArgumentException.Create('SQL numeric parameters must be finite.');
          end
          else
            raise EArgumentException.Create('SQL parameters must be JSON scalar values.');
        end;
      for LIndex := 0 to LQuery.Params.Count - 1 do
      begin
        LParameter := LQuery.Params[LIndex];
        if not LParameter.Bound then
          raise EArgumentException.CreateFmt('Missing SQL parameter: %s', [LParameter.Name]);
      end;
      LQuery.Open;
      Result := TJSONObject.Create;
      try
        LColumns := TJSONArray.Create;
        Result.AddPair('columns', LColumns);
        for LField in LQuery.Fields do
          LColumns.Add(LField.FieldName);
        LRows := TJSONArray.Create;
        Result.AddPair('rows', LRows);
        LTruncated := False;
        while not LQuery.Eof and (LRows.Count < AMaximumRows) do
        begin
          LRow := TJSONObject.Create;
          LRows.AddElement(LRow);
          for LField in LQuery.Fields do
          begin
            LRow.AddPair(LField.FieldName, JSONField(LField, LCellTruncated));
            LTruncated := LTruncated or LCellTruncated;
          end;
          LQuery.Next;
        end;
        LTruncated := LTruncated or not LQuery.Eof;
        Result.AddPair('count', TJSONNumber.Create(LRows.Count));
        Result.AddPair('truncated', TJSONBool.Create(LTruncated));
      except
        Result.Free;
        raise;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LGuard.Free;
    LConnection.Free;
  end;
end;

function TDAISymbolStore.Search(const AQuery, AVisibility: string; const AMaximumResults: Integer): TJSONObject;
var
  LColumns: string;
  LVisibility: string;
  LParameters: TJSONObject;
  LSQL: string;
  LPair: TJSONPair;
begin
  if Length(AQuery) > 1024 then
    raise EArgumentException.Create('The symbol query must contain at most 1024 characters.');
  LVisibility := LowerCase(Trim(AVisibility));
  LColumns := 's.name,s.qualified_name,s.signature';
  if (LVisibility = '') or (LVisibility = 'all') then
    LColumns := LColumns + ',s.members_private,s.members_protected,s.members_public,s.members_published'
  else if MatchText(LVisibility, ['private', 'protected', 'public', 'published']) then
    LColumns := LColumns + ',s.members_' + LVisibility
  else
    raise EArgumentException.Create('visibility must be all, private, protected, public or published.');
  LSQL := 'SELECT f.path AS file,f.sha256,f.source_kind,f.indexed_at,s.name,s.qualified_name,s.kind,s.signature,' +
    's.start_line,s.end_line,s.ancestor,s.members_private,s.members_protected,s.members_public,s.members_published ' +
    'FROM symbols s JOIN files f ON f.file_key=s.file_key WHERE instr(lower(' +
    StringReplace(LColumns, ',', ' || char(10) || ', [rfReplaceAll]) + '),lower(:query))>0 ORDER BY s.name,f.path,s.start_line';
  LParameters := TJSONObject.Create;
  try
    LParameters.AddPair('query', AQuery);
    Result := Query(LSQL, LParameters, AMaximumResults);
    LPair := Result.RemovePair('rows');
    try
      Result.AddPair('matches', LPair.JsonValue.Clone as TJSONValue);
    finally
      LPair.Free;
    end;
  finally
    LParameters.Free;
  end;
end;

class procedure TDAISymbolStore.Delete(const ADatabasePath: string);
var
  LPath: string;
  LSuffix: string;
begin
  if (ADatabasePath = '') or not TPath.IsPathRooted(ADatabasePath) then
    raise EArgumentException.Create('An absolute index database path is required.');
  LPath := TPath.GetFullPath(ADatabasePath);
  // The facade supplies an owned index path and closes stores before deleting it.
  for LSuffix in ['', '-wal', '-shm', '-journal'] do
    if TFile.Exists(LPath + LSuffix) then
      TFile.Delete(LPath + LSuffix);
end;

end.
