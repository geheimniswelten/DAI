unit h5u.DAI.OTA.Helpers;

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var TestGroup: IOTAProjectGroup;
    class var DispatchDepth: Integer;
    class var WritePreflightCount: Integer;
    class var DeniedReferencePrefix: string;
    class var DeniedReparsePrefix: string;
    class procedure RunOnMainThread(const AProc: TProc); static;
    class function ActiveProject: IOTAProject; static;
    class function MainProjectGroup: IOTAProjectGroup; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const AFirst, ASecond: string): Boolean; static;
    class procedure RequireNoReparseWritePath(const AFileName: string); static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  h5u.DAI.Types;

class procedure TDAIOTA.RunOnMainThread(const AProc: TProc);
begin
  Inc(DispatchDepth);
  try
    AProc();
  finally
    Dec(DispatchDepth);
  end;
end;

class function TDAIOTA.ActiveProject: IOTAProject;
begin
  Result := nil;
  if Assigned(TestGroup) then
    Result := TestGroup.ActiveProject;
end;

class function TDAIOTA.MainProjectGroup: IOTAProjectGroup;
begin
  Result := TestGroup;
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  Result := AProject.FileName;
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  Result := TPath.GetFullPath(AFileName);
end;

class function TDAIOTA.SameFile(const AFirst, ASecond: string): Boolean;
begin
  Result := SameText(NormalizeFileName(AFirst), NormalizeFileName(ASecond));
end;

class procedure TDAIOTA.RequireNoReparseWritePath(const AFileName: string);
begin
  Inc(WritePreflightCount);
  if (DeniedReparsePrefix <> '') and NormalizeFileName(AFileName).StartsWith(DeniedReparsePrefix, True) then
    raise EDAIAccessDenied.Create('Synthetic reparse path denies writes.');
end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin
  Result := (DeniedReferencePrefix <> '') and NormalizeFileName(AFileName).StartsWith(DeniedReferencePrefix, True);
end;

end.
