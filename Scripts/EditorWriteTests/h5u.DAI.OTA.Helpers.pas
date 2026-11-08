unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  ToolsAPI;

type
  TDAIOTA = class
  public
    class var Buffer: string;
    class var WorkspaceAllowed: Boolean;
    class var ReadOnlyReference: Boolean;
    class var AppendOnWrite: string;
    class var AppendOnSave: string;
    class var WriteCount: Integer;
    class var SaveCount: Integer;
    class var ReadCount: Integer;
    class var FindCount: Integer;
    class var OpenEditor: Boolean;
    class var LoadedModule: Boolean;
    class var LoadOnFinalLookup: Boolean;
    class var OpenOnFinalLookup: Boolean;
    class var FinalBuffer: string;
    class var SourceEditor: IOTASourceEditor;
    class var BufferOptionsAvailable: Boolean;
    class var FileOptionsAvailable: Boolean;
    class var BufferUseTabs: Boolean;
    class var FileUseTabs: Boolean;
    class var OptionsRaise: Boolean;
    class var BufferTabStops: string;
    class var FileTabStops: string;
    class var OptionsFileName: string;
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
    class function IsFileLoadedInIDE(const AFileName: string): Boolean; static;
    class function LoadedFileNames: TArray<string>; static;
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
  System.SysUtils,
  h5u.DAI.Text.Encoding;

type
  TTestEditor = class(TInterfacedObject, IOTAEditor, IOTASourceEditor, IOTAEditBuffer)
    function GetFileName: string;
    function CreateReader: IOTAEditReader;
    function GetBufferOptions: IOTABufferOptions;
  end;

  TTestReader = class(TInterfacedObject, IOTAEditReader)
  private
    FBytes: TBytes;
    FLoaded: Boolean;
  public
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;

  TTestBufferOptions = class(TInterfacedObject, IOTABufferOptions)
  private
    FIsBuffer: Boolean;
  public
    constructor Create(AIsBuffer: Boolean);
    function GetTabStops: string;
    function GetUseTabCharacter: Boolean;
  end;

  TTestEditOptions = class(TInterfacedObject, IOTAEditOptions)
    function GetBufferOptions: IOTABufferOptions;
  end;

  TTestActions = class(TInterfacedObject, IOTAActionServices, IOTAEditorServices)
    function GetEditOptionsForFile(const FileName: string): IOTAEditOptions;
    function OpenFile(const AFileName: string): Boolean;
    function SaveFile(const AFileName: string): Boolean;
  end;

function TTestEditor.GetFileName: string;
begin
  Result := 'IsolatedBuffer.pas';
end;

function TTestEditor.CreateReader: IOTAEditReader;
begin
  Result := TTestReader.Create;
end;

function TTestEditor.GetBufferOptions: IOTABufferOptions;
begin
  Result := nil;
  if TDAIOTA.OptionsRaise then
    raise Exception.Create('Test option failure');
  if TDAIOTA.BufferOptionsAvailable then
    Result := TTestBufferOptions.Create(True);
end;

constructor TTestBufferOptions.Create(AIsBuffer: Boolean);
begin
  inherited Create;
  FIsBuffer := AIsBuffer;
end;

function TTestBufferOptions.GetTabStops: string;
begin
  if TDAIOTA.OptionsRaise then
    raise Exception.Create('Test option failure');
  if FIsBuffer then
    Result := TDAIOTA.BufferTabStops
  else
    Result := TDAIOTA.FileTabStops;
end;

function TTestBufferOptions.GetUseTabCharacter: Boolean;
begin
  if TDAIOTA.OptionsRaise then
    raise Exception.Create('Test option failure');
  if FIsBuffer then
    Result := TDAIOTA.BufferUseTabs
  else
    Result := TDAIOTA.FileUseTabs;
end;

function TTestEditOptions.GetBufferOptions: IOTABufferOptions;
begin
  Result := TTestBufferOptions.Create(False);
end;

function TTestActions.GetEditOptionsForFile(const FileName: string): IOTAEditOptions;
begin
  TDAIOTA.OptionsFileName := FileName;
  if TDAIOTA.OptionsRaise then
    raise Exception.Create('Test option failure');
  Result := nil;
  if TDAIOTA.FileOptionsAvailable then
    Result := TTestEditOptions.Create;
end;

function TTestReader.GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
begin
  if not FLoaded then
  begin
    Inc(TDAIOTA.ReadCount);
    FBytes := TEncoding.UTF8.GetBytes(TDAIOTA.Buffer);
    FLoaded := True;
  end;
  Result := 0;
  if (Position < 0) or (Position >= Length(FBytes)) or (Count <= 0) or (Buffer = nil) then
    Exit;
  Result := Length(FBytes) - Position;
  if Result > Count then
    Result := Count;
  Move(FBytes[Position], Buffer^, Result);
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
  WorkspaceAllowed := True;
  ReadOnlyReference := False;
  AppendOnWrite := '';
  AppendOnSave := '';
  WriteCount := 0;
  SaveCount := 0;
  ReadCount := 0;
  FindCount := 0;
  OpenEditor := True;
  LoadedModule := False;
  LoadOnFinalLookup := False;
  OpenOnFinalLookup := False;
  FinalBuffer := '';
  BufferOptionsAvailable := False;
  FileOptionsAvailable := False;
  BufferUseTabs := True;
  FileUseTabs := True;
  OptionsRaise := False;
  BufferTabStops := '2';
  FileTabStops := '2';
  OptionsFileName := '';
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
  Result := AFileName;
end;

class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
begin
  Result := WorkspaceAllowed;
end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin
  Result := ReadOnlyReference;
end;

class function TDAIOTA.IsPathWithin(const AFileName, ARoot: string): Boolean;
begin
  Result := False;
end;

class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(ALeft, ARight);
end;

class function TDAIOTA.WorkspaceRoots: TArray<string>;
begin
  Result := nil;
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

class function TDAIOTA.IsFileLoadedInIDE(const AFileName: string): Boolean;
begin
  Result := OpenEditor or LoadedModule;
end;

class function TDAIOTA.LoadedFileNames: TArray<string>;
begin
  Result := nil;
  if OpenEditor or LoadedModule then
    Result := ['IsolatedBuffer.pas'];
end;

class function TDAIOTA.FindSourceEditor(const AFileName: string): IOTASourceEditor;
begin
  Inc(FindCount);
  if OpenEditor then
    Result := SourceEditor
  else
    Result := nil;
end;

class function TDAIOTA.EnsureFormTextEditor(const AFileName: string): IOTASourceEditor;
begin
  if LoadOnFinalLookup then
    LoadedModule := True;
  if OpenOnFinalLookup then
  begin
    OpenEditor := True;
    Buffer := FinalBuffer;
  end;
  Result := FindSourceEditor(AFileName);
end;

class function TDAIOTA.IsFileOpenInEditor(const AFileName: string): Boolean;
begin
  Result := OpenEditor;
end;

class function TDAIOTA.IsFormLoadedForFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

class function TDAIOTA.ReadFormText(const AFileName: string; AMaximumBytes: Integer; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

class function TDAIOTA.ReadEditorText(const ASource: IOTASourceEditor): string;
begin
  Inc(ReadCount);
  Result := Buffer;
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
  TDAIOTA.SourceEditor := TTestEditor.Create;
  BorlandIDEServices := TTestActions.Create;

finalization
  BorlandIDEServices := nil;
  TDAIOTA.SourceEditor := nil;

end.
