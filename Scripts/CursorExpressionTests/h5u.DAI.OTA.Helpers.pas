unit h5u.DAI.OTA.Helpers;
interface
uses System.Classes;
type
  TDAIOTA = class sealed
  public
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
  end;
var
  WorkspaceAllowed: Boolean = True;
  ReferenceAllowed: Boolean = False;
implementation
uses System.SysUtils;
class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  AAction();
end;
class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(ALeft, ARight) and (ALeft <> '');
end;
class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
begin
  Result := WorkspaceAllowed;
end;
class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin
  Result := ReferenceAllowed;
end;
end.
