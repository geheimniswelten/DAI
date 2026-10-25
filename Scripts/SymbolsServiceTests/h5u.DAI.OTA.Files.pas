unit h5u.DAI.OTA.Files;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs;

type
  TDAIIndexFileText = record
    FileName, Content, Sha256, Source, ErrorText: string;
  end;

  TDAIFileService = class sealed
  public
    class var ProjectSources: TDictionary<string, TArray<string>>;
    class var EditorBuffers: TDictionary<string, string>;
    class var ReadEntered: TEvent;
    class var AllowRead: TEvent;
    class var BlockReads: Boolean;
    class var IndexBatchCalls, MaximumIndexBatchSize: Integer;
    class var ReadPrefixLimit, LastMaximumBytes, LargeBatchViolations: Integer;
    class var FailNextIndexBatch: Boolean;
    class constructor Create;
    class destructor Destroy;
    class function ProjectFiles(const AProject: string): TJSONArray; static;
    class function ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject; static;
    class function ReadIndexFiles(const AFileNames: TArray<string>; const AMaximumBytes: Integer): TArray<TDAIIndexFileText>; static;
  end;

implementation

uses
  System.Hash,
  System.IOUtils,
  System.SysUtils;

class constructor TDAIFileService.Create;
begin
  ProjectSources := TDictionary<string, TArray<string>>.Create;
  EditorBuffers := TDictionary<string, string>.Create;
  ReadEntered := TEvent.Create(nil, True, False, '');
  AllowRead := TEvent.Create(nil, True, True, '');
end;

class destructor TDAIFileService.Destroy;
begin
  AllowRead.Free;
  ReadEntered.Free;
  EditorBuffers.Free;
  ProjectSources.Free;
end;

class function TDAIFileService.ProjectFiles(const AProject: string): TJSONArray;
var
  LFiles: TArray<string>;
  LFile: string;
begin
  Result := TJSONArray.Create;
  if ProjectSources.TryGetValue(LowerCase(AProject), LFiles) then
    for LFile in LFiles do
      Result.Add(LFile);
end;

class function TDAIFileService.ReadIndexFiles(const AFileNames: TArray<string>; const AMaximumBytes: Integer): TArray<TDAIIndexFileText>;
var
  LIndex: Integer;
  LText: TJSONObject;
begin
  if FailNextIndexBatch then
  begin
    FailNextIndexBatch := False;
    raise EInvalidOperation.Create('Controlled fatal index batch failure.');
  end;
  if (Length(AFileNames) > 32) or (AMaximumBytes <= 0) then
    raise EArgumentOutOfRangeException.Create('Invalid test index batch size.');
  Inc(IndexBatchCalls);
  LastMaximumBytes := AMaximumBytes;
  if Length(AFileNames) > 1 then
    for var LName in AFileNames do
      if TFile.GetSize(LName) > 1024 * 1024 then
        Inc(LargeBatchViolations);
  if Length(AFileNames) > MaximumIndexBatchSize then
    MaximumIndexBatchSize := Length(AFileNames);
  SetLength(Result, Length(AFileNames));
  if (ReadPrefixLimit > 0) and (Length(Result) > ReadPrefixLimit) then
    SetLength(Result, ReadPrefixLimit);
  for LIndex := 0 to High(Result) do
  begin
    Result[LIndex] := Default(TDAIIndexFileText);
    Result[LIndex].FileName := AFileNames[LIndex];
    try
      if not EditorBuffers.ContainsKey(LowerCase(AFileNames[LIndex])) then
        if TFile.GetSize(AFileNames[LIndex]) > AMaximumBytes then
          raise EInvalidOperation.Create('The test source exceeds the index size limit.');
      LText := ReadFile(AFileNames[LIndex], AMaximumBytes, False);
      try
        Result[LIndex].Content := LText.GetValue<string>('content');
        Result[LIndex].Sha256 := LText.GetValue<string>('sha256');
        Result[LIndex].Source := LText.GetValue<string>('source');
        if Length(Result[LIndex].Content) > AMaximumBytes then
          raise EInvalidOperation.Create('The test editor buffer exceeds the index size limit.');
      finally
        LText.Free;
      end;
    except
      on E: Exception do
        Result[LIndex].ErrorText := E.Message;
    end;
  end;
end;

class function TDAIFileService.ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject;
var
  LContent: string;
  LSource: string;
begin
  if BlockReads then
  begin
    ReadEntered.SetEvent;
    if AllowRead.WaitFor(10000) <> wrSignaled then
      raise EInvalidOperation.Create('Timed out waiting for isolated test read gate.');
  end;
  if EditorBuffers.TryGetValue(LowerCase(AFileName), LContent) then
    LSource := 'editor_buffer'
  else
  begin
    LContent := TFile.ReadAllText(AFileName);
    LSource := 'disk';
  end;
  Result := TJSONObject.Create.AddPair('content', LContent).AddPair('sha256', THashSHA2.GetHashString(LContent))
    .AddPair('source', LSource).AddPair('content_complete', TJSONBool.Create(True));
end;

end.
