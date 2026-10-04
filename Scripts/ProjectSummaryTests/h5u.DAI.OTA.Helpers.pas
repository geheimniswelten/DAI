unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  System.Generics.Collections,
  ToolsAPI;

type
  TTestBuffer = record
    Text: string;
    ReaderAvailable: Boolean;
    ReadFails: Boolean;
  end;

  TDAIOTA = class sealed
  public
    class var TestProjects: TArray<IOTAProject>;
    class var TestActiveProject: IOTAProject;
    class var TestBuffers: TDictionary<string, TTestBuffer>;
    class var DispatchDepth, ProjectsCount, ActiveProjectCount, BufferReadCount: Integer;
    class constructor Initialize;
    class destructor Finalize;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function Projects: TArray<IOTAProject>; static;
    class function ActiveProject: IOTAProject; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function FindSourceEditor(const AFileName: string): IOTASourceEditor; static;
    class function ReadEditorText(const AEditor: IOTASourceEditor): string; static;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

type
  TTestReader = class(TInterfacedObject, IOTAEditReader);

  TTestEditor = class(TInterfacedObject, IOTASourceEditor)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    function CreateReader: IOTAEditReader;
    function GetFileName: string;
  end;

constructor TTestEditor.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
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

function TTestEditor.GetFileName: string;
begin
  Result := FFileName;
end;

class constructor TDAIOTA.Initialize;
begin
  TestBuffers := TDictionary<string, TTestBuffer>.Create;
end;

class destructor TDAIOTA.Finalize;
begin
  TestBuffers.Free;
end;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  Inc(DispatchDepth);
  try
    AAction();
  finally
    Dec(DispatchDepth);
  end;
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
begin
  if DispatchDepth = 0 then
    raise EInvalidOperation.Create('Project list must be captured on the IDE thread.');
  Inc(ProjectsCount);
  Result := TestProjects;
end;

class function TDAIOTA.ActiveProject: IOTAProject;
begin
  if DispatchDepth = 0 then
    raise EInvalidOperation.Create('Active project must be captured on the IDE thread.');
  Inc(ActiveProjectCount);
  Result := TestActiveProject;
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AFileName));
end;

class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(NormalizeFileName(ALeft), NormalizeFileName(ARight));
end;

class function TDAIOTA.FindSourceEditor(const AFileName: string): IOTASourceEditor;
begin
  Result := nil;
  if TestBuffers.ContainsKey(NormalizeFileName(AFileName)) then
    Result := TTestEditor.Create(NormalizeFileName(AFileName));
end;

class function TDAIOTA.ReadEditorText(const AEditor: IOTASourceEditor): string;
var
  LBuffer: TTestBuffer;
begin
  Inc(BufferReadCount);
  LBuffer := TestBuffers[AEditor.FileName];
  if LBuffer.ReadFails then
    raise EInvalidOperation.Create('Synthetic reader failure.');
  Result := LBuffer.Text;
end;

end.
