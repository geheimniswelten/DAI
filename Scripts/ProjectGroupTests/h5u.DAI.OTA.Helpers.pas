unit h5u.DAI.OTA.Helpers;

interface

uses System.Classes, ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var TestGroup: IOTAProjectGroup;
    class var TestActiveProject: IOTAProject;
    class var TestProjects: TArray<IOTAProject>;
    class var TestModules: TArray<IOTAModule>;
    class var TestReadOnlyFile: string;
    class var DispatchDepth: Integer;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function MainProjectGroup: IOTAProjectGroup; static;
    class function ActiveProject: IOTAProject; static;
    class function Projects: TArray<IOTAProject>; static;
    class function ProjectByNameOrPath(const AName: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function FindModuleByFileName(const AFileName: string): IOTAModule; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function IsPathWithin(const AFileName, ARoot: string): Boolean; static;
    class function IsFileOpenInEditor(const AFileName: string): Boolean; static;
    class function IsFormLoadedForFile(const AFileName: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class procedure RequireNoReparseWritePath(const AFileName: string); static;
    class function ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean; static;
    class function FormFileName(const AFileName: string): string; static;
    class function EnsureFormTextEditor(const AFileName: string): IOTASourceEditor; static;
  end;

implementation

uses System.IOUtils, System.SysUtils;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  Inc(DispatchDepth);
  try
    AAction();
  finally
    Dec(DispatchDepth);
  end;
end;

class function TDAIOTA.MainProjectGroup: IOTAProjectGroup;
begin Result := TestGroup; end;
class function TDAIOTA.ActiveProject: IOTAProject;
begin Result := TestActiveProject; end;
class function TDAIOTA.Projects: TArray<IOTAProject>;
begin Result := TestProjects; end;
class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  if AProject = nil then Result := '' else Result := AProject.FileName;
end;
class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  if (Trim(ALeft) = '') or (Trim(ARight) = '') then
    Exit(SameText(Trim(ALeft), Trim(ARight)));
  Result := SameText(TPath.GetFullPath(ALeft), TPath.GetFullPath(ARight));
end;
class function TDAIOTA.ProjectByNameOrPath(const AName: string): IOTAProject;
var LProject: IOTAProject;
begin
  Result := nil;
  for LProject in TestProjects do
    if SameFile(LProject.FileName, AName) then Exit(LProject);
end;
class function TDAIOTA.FindModuleByFileName(const AFileName: string): IOTAModule;
var LModule: IOTAModule;
begin
  Result := nil;
  for LModule in TestModules do
    if SameFile(LModule.FileName, AFileName) then Exit(LModule);
end;
class function TDAIOTA.IsPathWithin(const AFileName, ARoot: string): Boolean;
begin Result := SameText(ExcludeTrailingPathDelimiter(TPath.GetFullPath(ARoot)),
  TPath.GetDirectoryName(TPath.GetFullPath(AFileName))); end;
class function TDAIOTA.IsFileOpenInEditor(const AFileName: string): Boolean;
begin Result := FindModuleByFileName(AFileName) <> nil; end;
class function TDAIOTA.IsFormLoadedForFile(const AFileName: string): Boolean;
begin Result := False; end;
class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin Result := (TestReadOnlyFile <> '') and SameFile(TestReadOnlyFile, AFileName); end;
class procedure TDAIOTA.RequireNoReparseWritePath(const AFileName: string);
begin end;
class function TDAIOTA.ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean;
begin Result := False; end;
class function TDAIOTA.FormFileName(const AFileName: string): string;
begin Result := ChangeFileExt(AFileName, '.dfm'); end;
class function TDAIOTA.EnsureFormTextEditor(const AFileName: string): IOTASourceEditor;
begin Result := nil; end;

end.
