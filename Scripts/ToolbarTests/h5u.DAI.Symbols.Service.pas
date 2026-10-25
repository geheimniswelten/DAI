unit h5u.DAI.Symbols.Service;

interface

uses System.JSON;

type
  TDAISymbolService = class sealed
  public
    class var ListCount: Integer;
    class var BuildCount: Integer;
    class var DeleteCount: Integer;
    class var PollCount: Integer;
    class var ProviderCount: Integer;
    class var ProjectAvailable: Boolean;
    class var GroupAvailable: Boolean;
    class var ProviderAvailable: Boolean;
    class var FailListing: Boolean;
    class var Existing: array[0..3] of Boolean;
    class var LastScope: string;
    class var LastIdentity: string;
    class var CompletionState: string;
    class var ErrorCounts: array[0..3] of Integer;
    class var ErrorReason: string;
    class var ErrorFilePrefix: string;
    class var ErrorsReadCount: Integer;
    class var ErrorOffsets: TArray<Integer>;
    class var LastErrorScope, LastErrorIdentity: string;
    class var FailErrorsRead: Boolean;
    class var DetailsAvailable: array[0..3] of Boolean;
    class var BuildStates: array[0..3] of string;
    class var BuildError, BuildStartedAt, BuildFinishedAt: string;
    class var ErrorReportId: string;
    class var ChangeErrorReportAfterFirstPage: Boolean;
    class var ErrorStateAfterFirstPage: string;
    class var FileCounts, SymbolCounts, SizeBytes: array[0..3] of Int64;
    class var SizeKnown: array[0..3] of Boolean;
    class var OmitSize: Boolean;
    class var ProcessedFiles, TotalFiles: Int64;
    class var RowErrors: array[0..3] of string;
    class var JobError: string;
    class var StorageWarning: string;
    class var ListWarning: string;
    class var IndexNames: array[0..3] of string;
    class procedure Reset; static;
    class function ListIndexes: TJSONObject; static;
    class function Build(const AScope: string; const AExpectedIdentity: string = ''): TJSONObject; static;
    class function Delete(const AScope: string; const AExpectedIdentity: string = ''): TJSONObject; static;
    class function JobStatus(const ARequestId: string): TJSONObject; static;
    class function AIStatus: TJSONObject; static;
    class function IndexErrors(const AScope, AExpectedIdentity: string; const AOffset: Integer = 0; const ALimit: Integer = 500): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses System.Classes, System.SysUtils;

const
  CScopes: array[0..3] of string = ('delphi', 'getit', 'group', 'project');

class procedure TDAISymbolService.Reset;
begin
  ListCount := 0;
  BuildCount := 0;
  DeleteCount := 0;
  PollCount := 0;
  ProviderCount := 0;
  ProjectAvailable := True;
  GroupAvailable := True;
  ProviderAvailable := True;
  FailListing := False;
  for var LIndex := Low(Existing) to High(Existing) do
  begin
    Existing[LIndex] := False;
    ErrorCounts[LIndex] := 0;
    DetailsAvailable[LIndex] := False;
    BuildStates[LIndex] := '';
    FileCounts[LIndex] := 42;
    SymbolCounts[LIndex] := 128;
    SizeBytes[LIndex] := 0;
    SizeKnown[LIndex] := False;
    RowErrors[LIndex] := '';
    IndexNames[LIndex] := 'Testindex ' + CScopes[LIndex];
  end;
  LastScope := '';
  LastIdentity := '';
  CompletionState := 'completed';
  ErrorReason := 'Test: Datei konnte nicht gelesen oder indiziert werden.';
  ErrorFilePrefix := 'C:\Test\Ausgelassen\Unit';
  ErrorsReadCount := 0;
  ErrorOffsets := nil;
  LastErrorScope := '';
  LastErrorIdentity := '';
  FailErrorsRead := False;
  BuildError := '';
  BuildStartedAt := '2026-09-17T10:11:12Z';
  BuildFinishedAt := '2026-09-17T10:12:13Z';
  ErrorReportId := 'persisted-error-report-id';
  ChangeErrorReportAfterFirstPage := False;
  ErrorStateAfterFirstPage := '';
  OmitSize := False;
  ProcessedFiles := 0;
  TotalFiles := 0;
  JobError := '';
  StorageWarning := '';
  ListWarning := 'Indexstand prüfen; aktuelle und ungespeicherte Änderungen können fehlen.';
end;

class function TDAISymbolService.ListIndexes: TJSONObject;
var
  LIndexes: TJSONArray;
  LRow: TJSONObject;
  LIndex: Integer;
  LOwner: string;
begin
  Inc(ListCount);
  if FailListing then
    raise EInvalidOperation.Create('Test: Indexliste nicht verfügbar.');
  Result := TJSONObject.Create;
  LIndexes := TJSONArray.Create;
  Result.AddPair('indexes', LIndexes);
  Result.AddPair('warning', ListWarning);
  for LIndex := Low(CScopes) to High(CScopes) do
  begin
    LRow := TJSONObject.Create;
    LIndexes.AddElement(LRow);
    LRow.AddPair('scope', CScopes[LIndex]);
    LRow.AddPair('identity', 'snapshot-' + CScopes[LIndex]);
    LRow.AddPair('name', IndexNames[LIndex]);
    LOwner := 'C:\Test\Owner';
    if ((LIndex = 2) and not GroupAvailable) or ((LIndex = 3) and not ProjectAvailable) then
      LOwner := '';
    LRow.AddPair('owner', LOwner);
    LRow.AddPair('database', 'C:\Test\' + CScopes[LIndex] + '.sqlite');
    LRow.AddPair('exists', TJSONBool.Create(Existing[LIndex]));
    LRow.AddPair('error_count', TJSONNumber.Create(ErrorCounts[LIndex]));
    LRow.AddPair('details_available', TJSONBool.Create(DetailsAvailable[LIndex] or (ErrorCounts[LIndex] > 0)));
    if RowErrors[LIndex] <> '' then
      LRow.AddPair('error', RowErrors[LIndex]);
    if not OmitSize then
      if SizeKnown[LIndex] then
        LRow.AddPair('size_bytes', TJSONNumber.Create(SizeBytes[LIndex]))
      else
        LRow.AddPair('size_bytes', TJSONNull.Create);
    if Existing[LIndex] then
    begin
      LRow.AddPair('indexed_at', '2026-10-24T12:34:56Z');
      if BuildStates[LIndex] = '' then
        LRow.AddPair('state', 'ready')
      else
        LRow.AddPair('state', BuildStates[LIndex]);
      LRow.AddPair('file_count', TJSONNumber.Create(FileCounts[LIndex]));
      LRow.AddPair('symbol_count', TJSONNumber.Create(SymbolCounts[LIndex]));
    end
    else
    begin
      LRow.AddPair('indexed_at', TJSONNull.Create);
      if BuildStates[LIndex] = '' then
        LRow.AddPair('state', 'missing')
      else
        LRow.AddPair('state', BuildStates[LIndex]);
      LRow.AddPair('file_count', TJSONNumber.Create(0));
      LRow.AddPair('symbol_count', TJSONNumber.Create(0));
    end;
  end;
end;

class function TDAISymbolService.Build(const AScope: string; const AExpectedIdentity: string): TJSONObject;
begin
  Inc(BuildCount);
  LastScope := AScope;
  LastIdentity := AExpectedIdentity;
  Result := TJSONObject.Create;
  Result.AddPair('request_id', 'test-job');
  Result.AddPair('state', 'queued');
  Result.AddPair('running', TJSONBool.Create(True));
end;

class function TDAISymbolService.Delete(const AScope: string; const AExpectedIdentity: string): TJSONObject;
begin
  Inc(DeleteCount);
  LastScope := AScope;
  LastIdentity := AExpectedIdentity;
  for var LIndex := Low(CScopes) to High(CScopes) do
    if AScope = CScopes[LIndex] then
    begin
      Existing[LIndex] := False;
      ErrorCounts[LIndex] := 0;
      DetailsAvailable[LIndex] := False;
      BuildStates[LIndex] := '';
    end;
  Result := TJSONObject.Create;
  Result.AddPair('deleted', TJSONBool.Create(True));
end;

class function TDAISymbolService.JobStatus(const ARequestId: string): TJSONObject;
begin
  Inc(PollCount);
  for var LIndex := Low(CScopes) to High(CScopes) do
    if LastScope = CScopes[LIndex] then
      Existing[LIndex] := CompletionState <> 'error';
  Result := TJSONObject.Create;
  Result.AddPair('request_id', ARequestId);
  Result.AddPair('state', CompletionState);
  Result.AddPair('error', JobError);
  Result.AddPair('running', TJSONBool.Create(False));
  Result.AddPair('message', 'Test: Auftrag abgeschlossen.');
  if (CompletionState = 'building') or (CompletionState = 'queued') then
    Result.RemovePair('message').Free;
  Result.AddPair('processed_files', TJSONNumber.Create(ProcessedFiles));
  Result.AddPair('total_files', TJSONNumber.Create(TotalFiles));
  for var LIndex := Low(CScopes) to High(CScopes) do
    if LastScope = CScopes[LIndex] then
      Result.AddPair('error_count', TJSONNumber.Create(ErrorCounts[LIndex]));
end;

class function TDAISymbolService.IndexErrors(const AScope, AExpectedIdentity: string; const AOffset, ALimit: Integer): TJSONObject;
var
  LTotal, LIndex: Integer;
  LErrors: TJSONArray;
begin
  Inc(ErrorsReadCount);
  SetLength(ErrorOffsets, Length(ErrorOffsets) + 1);
  ErrorOffsets[High(ErrorOffsets)] := AOffset;
  LastErrorScope := AScope;
  LastErrorIdentity := AExpectedIdentity;
  if FailErrorsRead then
    raise EInvalidOperation.Create('Test: Die Projektauswahl wurde geändert. Bitte die Indexliste erneut laden.');
  LTotal := 0;
  for LIndex := Low(CScopes) to High(CScopes) do
    if AScope = CScopes[LIndex] then
      LTotal := ErrorCounts[LIndex];
  Result := TJSONObject.Create;
  LErrors := TJSONArray.Create;
  Result.AddPair('errors', LErrors);
  for LIndex := AOffset to LTotal - 1 do
  begin
    if LIndex - AOffset >= ALimit then
      Break;
    LErrors.AddElement(TJSONObject.Create.AddPair('file', ErrorFilePrefix + Format('%.5d.pas', [LIndex]))
      .AddPair('error', ErrorReason + ' #' + IntToStr(LIndex)));
  end;
  Result.AddPair('total_count', TJSONNumber.Create(LTotal));
  Result.AddPair('offset', TJSONNumber.Create(AOffset));
  Result.AddPair('has_more', TJSONBool.Create(AOffset + LErrors.Count < LTotal));
  if (AOffset > 0) and (ErrorStateAfterFirstPage <> '') then
    Result.AddPair('state', ErrorStateAfterFirstPage)
  else
    for LIndex := Low(CScopes) to High(CScopes) do
      if AScope = CScopes[LIndex] then
        if BuildStates[LIndex] = '' then
          Result.AddPair('state', CompletionState)
        else
          Result.AddPair('state', BuildStates[LIndex]);
  Result.AddPair('error', BuildError);
  Result.AddPair('started_at', BuildStartedAt);
  Result.AddPair('finished_at', BuildFinishedAt);
  Result.AddPair('storage_warning', StorageWarning);
  if ChangeErrorReportAfterFirstPage and (AOffset > 0) then
    Result.AddPair('request_id', ErrorReportId + '-replaced')
  else
    Result.AddPair('request_id', ErrorReportId);
end;

class function TDAISymbolService.AIStatus: TJSONObject;
begin
  Inc(ProviderCount);
  Result := TJSONObject.Create;
  Result.AddPair('available', TJSONBool.Create(ProviderAvailable));
end;

class procedure TDAISymbolService.Shutdown;
begin
end;

initialization
  TDAISymbolService.Reset;

end.
