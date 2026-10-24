unit h5u.DAI.OTA.Helpers;

interface

uses ToolsAPI;

type
  TDAIOTA = class
  private
    class var FProjects: TArray<IOTAProject>;
  public
    class var ResolveCalls: Integer;
    class procedure Reset; static;
    class function ProjectByNameOrPath(const AName: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function ProjectContainsFile(const AProject: IOTAProject; const AFile: string): Boolean; static;
    class function Projects: TArray<IOTAProject>; static;
    class function IsAlwaysReadableReference(const AFile: string): Boolean; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function IsPathWithin(const APath, ARoot: string): Boolean; static;
  end;

implementation

uses System.IOUtils, System.SysUtils, h5u.DAI.Settings;

type
  TTestProject = class(TInterfacedObject, IOTAProject)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    function GetFileName: string;
  end;

constructor TTestProject.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

function TTestProject.GetFileName: string;
begin
  Result := FFileName;
end;

class procedure TDAIOTA.Reset;
begin
  FProjects := [TTestProject.Create('C:\SyntheticDAITest\Current.dproj'), TTestProject.Create('C:\SyntheticDAITest\Denied\Other.dproj')];
  ResolveCalls := 0;
end;

class function TDAIOTA.ProjectByNameOrPath(const AName: string): IOTAProject;
var
  LProject: IOTAProject;
begin
  Inc(ResolveCalls);
  if AName = '' then
    Exit(FProjects[0]);
  for LProject in FProjects do
    if SameFile(AName, LProject.FileName) then
      Exit(LProject);
  Result := nil;
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  Result := AProject.FileName;
end;

class function TDAIOTA.ProjectContainsFile(const AProject: IOTAProject; const AFile: string): Boolean;
begin
  Result := SameFile(AProject.FileName, AFile) or SameFile(TPath.Combine(TPath.GetDirectoryName(AProject.FileName), 'Unit1.pas'), AFile);
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
begin
  Result := FProjects;
end;

class function TDAIOTA.IsAlwaysReadableReference(const AFile: string): Boolean;
begin
  Result := IsPathWithin(AFile, 'C:\Delphi\Source') or IsPathWithin(AFile, 'C:\GetIt');
  if TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed then
    Result := Result or IsPathWithin(AFile, 'C:\AdditionalRefs');
end;

class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(TPath.GetFullPath(ALeft), TPath.GetFullPath(ARight));
end;

class function TDAIOTA.IsPathWithin(const APath, ARoot: string): Boolean;
begin
  Result := TPath.GetFullPath(APath).StartsWith(IncludeTrailingPathDelimiter(TPath.GetFullPath(ARoot)), True);
end;

initialization
  TDAIOTA.Reset;
end.
