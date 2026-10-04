unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  System.Generics.Collections,
  ToolsAPI;

type
  TTestBuffer = record
    Content: string;
    Source: string;
    ReaderAvailable: Boolean;
    ReadFails: Boolean;
  end;

  TDAIOTA = class
  public
    class var TestBuffers: TDictionary<string, TTestBuffer>;
    class var TestWorkspaceRoots: TArray<string>;
    class var TestReadCount: Integer;
    class var TestDesignerReadCount: Integer;
    class constructor Initialize;
    class destructor Finalize;
    class var Buffer: string;
    class var AppendOnWrite: string;
    class var AppendOnSave: string;
    class var WriteCount: Integer;
    class var SaveCount: Integer;
    class var SourceEditor: IOTASourceEditor;
    class procedure Reset(const AText: string); static;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class procedure RequireNoReparseWritePath(const AFileName: string); static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class function IsPathWithin(const AFileName, ARoot: string): Boolean; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function WorkspaceRoots: TArray<string>; static;
    class function Projects: TArray<IOTAProject>; static;
    class function ProjectByNameOrPath(const AProject: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function ProjectConfiguration(const AProject: IOTAProject): string; static;
    class function ProjectPlatform(const AProject: IOTAProject): string; static;
    class function FindSourceEditor(const AFileName: string): IOTASourceEditor; static;
    class function EnsureFormTextEditor(const AFileName: string): IOTASourceEditor; static;
    class function IsFileOpenInEditor(const AFileName: string): Boolean; static;
    class function IsFormLoadedForFile(const AFileName: string): Boolean; static;
    class function ReadFormText(const AFileName: string; AMaximumBytes: Integer; out AText: string): Boolean; static;
    class function ReadEditorText(const ASource: IOTASourceEditor): string; static;
    class function ReplaceEditorText(const ASource: IOTASourceEditor; const AText: string; out AActualText: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Defaults,
  System.IOUtils,
  System.SysUtils,
  h5u.DAI.Settings,
  h5u.DAI.Text.Encoding;

type
  TTestEditor = class(TInterfacedObject, IOTAEditor, IOTASourceEditor)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    function GetFileName: string;
    function CreateReader: IOTAEditReader;
  end;

  TTestReader = class(TInterfacedObject, IOTAEditReader);

  TTestActions = class(TInterfacedObject, IOTAActionServices)
    function OpenFile(const AFileName: string): Boolean;
    function SaveFile(const AFileName: string): Boolean;
  end;

constructor TTestEditor.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

function TTestEditor.GetFileName: string;
begin
  Result := FFileName;
end;

function TTestEditor.CreateReader: IOTAEditReader;
var
  LBuffer: TTestBuffer;
begin
  Result := nil;
  if TDAIOTA.TestBuffers.TryGetValue(FFileName, LBuffer) then
    if LBuffer.ReaderAvailable then
      Result := TTestReader.Create;
end;

class constructor TDAIOTA.Initialize;
begin
  TestBuffers := TDictionary<string, TTestBuffer>.Create(TIStringComparer.Ordinal);
end;

class destructor TDAIOTA.Finalize;
begin
  TestBuffers.Free;
end;

function TTestActions.OpenFile(const AFileName: string): Boolean;
begin
  Result := True;
end;

function TTestActions.SaveFile(const AFileName: string): Boolean;
begin
  Inc(TDAIOTA.SaveCount);
  TDAIOTA.Buffer := TDAIOTA.Buffer + TDAIOTA.AppendOnSave;
  Result := True;
end;

class procedure TDAIOTA.Reset(const AText: string);
begin
  Buffer := AText;
  AppendOnWrite := '';
  AppendOnSave := '';
  WriteCount := 0;
  SaveCount := 0;
end;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  AAction();
end;

class procedure TDAIOTA.RequireNoReparseWritePath(const AFileName: string);
begin
  // These editor doubles have virtual paths. Real filesystem guards are tested by Test.ReadOnlyPolicy.
  if AFileName = '' then
    raise EArgumentException.Create('A virtual editor path is required.');
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AFileName));
end;

class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in TestWorkspaceRoots do
    if IsPathWithin(AFileName, LRoot) then
      Exit(True);
end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in TDAISettings.TestReadRoots do
    if IsPathWithin(AFileName, LRoot) then
      Exit(True);
end;

class function TDAIOTA.IsPathWithin(const AFileName, ARoot: string): Boolean;
begin
  Result := NormalizeFileName(AFileName).StartsWith(IncludeTrailingPathDelimiter(NormalizeFileName(ARoot)), True);
end;

class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(ALeft, ARight);
end;

class function TDAIOTA.WorkspaceRoots: TArray<string>;
begin
  Result := TestWorkspaceRoots;
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
begin
  Result := nil;
end;

class function TDAIOTA.ProjectByNameOrPath(const AProject: string): IOTAProject;
begin
  Result := nil;
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  Result := '';
end;

class function TDAIOTA.ProjectConfiguration(const AProject: IOTAProject): string;
begin
  Result := '';
end;

class function TDAIOTA.ProjectPlatform(const AProject: IOTAProject): string;
begin
  Result := '';
end;

class function TDAIOTA.FindSourceEditor(const AFileName: string): IOTASourceEditor;
var
  LBuffer: TTestBuffer;
begin
  Result := nil;
  if TestBuffers.TryGetValue(NormalizeFileName(AFileName), LBuffer) then
    if LBuffer.Source = 'editor_buffer' then
      Result := TTestEditor.Create(NormalizeFileName(AFileName));
end;

class function TDAIOTA.EnsureFormTextEditor(const AFileName: string): IOTASourceEditor;
begin
  Result := FindSourceEditor(AFileName);
end;

class function TDAIOTA.IsFileOpenInEditor(const AFileName: string): Boolean;
begin
  Result := Assigned(FindSourceEditor(AFileName));
end;

class function TDAIOTA.IsFormLoadedForFile(const AFileName: string): Boolean;
var
  LBuffer: TTestBuffer;
begin
  Result := False;
  if TestBuffers.TryGetValue(NormalizeFileName(AFileName), LBuffer) then
    Result := LBuffer.Source = 'designer_buffer';
end;

class function TDAIOTA.ReadFormText(const AFileName: string; AMaximumBytes: Integer; out AText: string): Boolean;
var
  LBuffer: TTestBuffer;
begin
  AText := '';
  Result := False;
  if TestBuffers.TryGetValue(NormalizeFileName(AFileName), LBuffer) then
    if LBuffer.Source = 'designer_buffer' then
    begin
      Inc(TestDesignerReadCount);
      if LBuffer.ReadFails then
        raise EInvalidOperation.Create('Test designer read failed.');
      if not LBuffer.ReaderAvailable then
        Exit;
      if Length(LBuffer.Content) > AMaximumBytes then
        raise EInvalidOperation.Create('Test designer text exceeds limit.');
      AText := LBuffer.Content;
      Result := True;
    end;
end;

class function TDAIOTA.ReadEditorText(const ASource: IOTASourceEditor): string;
var
  LBuffer: TTestBuffer;
begin
  Inc(TestReadCount);
  if not TestBuffers.TryGetValue(ASource.FileName, LBuffer) then
    raise EInvalidOperation.Create('Test buffer no longer exists.');
  if LBuffer.ReadFails then
    raise EInvalidOperation.Create('Test editor read failed.');
  Result := LBuffer.Content;
end;

class function TDAIOTA.ReplaceEditorText(const ASource: IOTASourceEditor; const AText: string; out AActualText: string): Boolean;
begin
  AActualText := '';
  if Pos(#0, AText) <> 0 then
    Exit(False);
  Inc(WriteCount);
  Buffer := AText + AppendOnWrite;
  AActualText := Buffer;
  Result := TDAITextEncoding.EditorWriteMatches(AText, AActualText);
end;

initialization
  BorlandIDEServices := TTestActions.Create;

finalization
  BorlandIDEServices := nil;
  TDAIOTA.SourceEditor := nil;

end.
