unit h5u.DAI.OTA.Helpers;

interface

uses System.Classes, System.SysUtils, ToolsAPI;

type
  TDAIOTA = class
  public
    class var TestEditor: IOTAFormEditor;
    class var WorkspaceAllowed: Boolean;
    class var ReferenceFile: Boolean;
    class var DeniedPath: string;
    class var ReferencePath: string;
    class var RejectReparsePath: Boolean;
    class var DispatchDepth: Integer;
    class var ReparseChecks: Integer;
    class procedure RunOnMainThread(const AProc: TProc); static;
    class function FindFormEditor(const AFileName: string): IOTAFormEditor; static;
    class function EnsureFormDesigner(const AFileName: string): IOTAFormEditor; static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class procedure RequireNoReparseWritePath(const AFileName: string); static;
  end;

implementation

class procedure TDAIOTA.RunOnMainThread(const AProc: TProc);
begin
  Inc(DispatchDepth);
  try AProc(); finally Dec(DispatchDepth); end;
end;

class function TDAIOTA.FindFormEditor(const AFileName: string): IOTAFormEditor;
begin Result := TestEditor; end;

class function TDAIOTA.EnsureFormDesigner(const AFileName: string): IOTAFormEditor;
begin Result := TestEditor; end;

class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
begin Result := WorkspaceAllowed and not SameText(AFileName, DeniedPath); end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin Result := ReferenceFile or SameText(AFileName, ReferencePath); end;

class procedure TDAIOTA.RequireNoReparseWritePath(const AFileName: string);
begin
  Inc(ReparseChecks);
  if RejectReparsePath then raise EInvalidOperation.Create('Fixture reparse write path rejected');
end;

end.
