unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  ToolsAPI;

type
  TTestBuffer = record
    Content: string;
    Source: string;
    Truncated: Boolean;
    ReadFails: Boolean;
  end;

  TDAIOTA = class
  public
    class var TestProjects: TArray<IOTAProject>;
    class var TestActiveProject: IOTAProject;
    class var TestGroup: IOTAProjectGroup;
    class var TestBuffers: TDictionary<string, TTestBuffer>;
    class var TestProjectReadDelayMs: Cardinal;
    class var TestReadCount: Integer;
    class var TestProjectReadCount: Integer;
    class var TestProjectReadKeys: TArray<string>;
    class constructor Initialize;
    class destructor Finalize;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const AFileName, AOtherFileName: string): Boolean; static;
    class function IsPathWithin(const AFileName, ARootDirectory: string): Boolean; static;
    class function Projects: TArray<IOTAProject>; static;
    class function ProjectByNameOrPath(const AName: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean; static;
    class function MainProjectGroup: IOTAProjectGroup; static;
    class procedure RunOnMainThread(const AProcedure: TProc); static;
    class function FindSourceEditor(const AFileName: string): IOTASourceEditor; static;
    class function IsFormLoadedForFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Defaults,
  System.IOUtils;

class constructor TDAIOTA.Initialize;
begin
  TestBuffers := TDictionary<string, TTestBuffer>.Create(TIStringComparer.Ordinal);
end;

class destructor TDAIOTA.Finalize;
begin
  TestBuffers.Free;
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  if Trim(AFileName) = '' then
    Exit('');
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(StringReplace(Trim(AFileName), '/', '\', [rfReplaceAll])));
end;

class function TDAIOTA.SameFile(const AFileName, AOtherFileName: string): Boolean;
begin
  Result := SameText(NormalizeFileName(AFileName), NormalizeFileName(AOtherFileName));
end;

class function TDAIOTA.IsPathWithin(const AFileName, ARootDirectory: string): Boolean;
begin
  Result := (Trim(AFileName) <> '') and (Trim(ARootDirectory) <> '') and
    NormalizeFileName(AFileName).StartsWith(IncludeTrailingPathDelimiter(NormalizeFileName(ARootDirectory)), True);
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
begin
  Result := TestProjects;
end;

class function TDAIOTA.ProjectByNameOrPath(const AName: string): IOTAProject;
var
  LProject: IOTAProject;
begin
  if AName = '' then
    Exit(TestActiveProject);
  Result := nil;
  for LProject in TestProjects do
    if SameFile(LProject.FileName, AName) or SameText(ChangeFileExt(TPath.GetFileName(LProject.FileName), ''), AName) then
      Exit(LProject);
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  if Assigned(AProject) then
    Result := AProject.FileName
  else
    Result := '';
end;

class function TDAIOTA.ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean;
var
  LFile: string;
begin
  Result := Assigned(AProject) and SameFile(AProject.FileName, AFileName);
  if Result or not Assigned(AProject) then
    Exit;
  for LFile in AProject.Files do
    if SameFile(LFile, AFileName) then
      Exit(True);
end;

class function TDAIOTA.MainProjectGroup: IOTAProjectGroup;
begin
  Result := TestGroup;
end;

class procedure TDAIOTA.RunOnMainThread(const AProcedure: TProc);
begin
  AProcedure();
end;

class function TDAIOTA.FindSourceEditor(const AFileName: string): IOTASourceEditor;
begin
  if TestBuffers.ContainsKey(NormalizeFileName(AFileName)) then
    Result := TTestSourceEditor.Create
  else
    Result := nil;
end;

class function TDAIOTA.IsFormLoadedForFile(const AFileName: string): Boolean;
var
  LBuffer: TTestBuffer;
begin
  Result := TestBuffers.TryGetValue(NormalizeFileName(AFileName), LBuffer) and (LBuffer.Source = 'designer_buffer');
end;

end.
