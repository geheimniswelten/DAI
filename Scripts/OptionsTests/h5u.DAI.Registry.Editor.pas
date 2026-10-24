unit h5u.DAI.Registry.Editor;

interface

uses
  Winapi.Windows;

var
  RegistryEditorOpenCount: Integer;
  RegistryEditorOwner: HWND;
  RegistryEditorOpenResult: Boolean = True;

function DAIOpenUsageLogInRegistryEditor(const AOwner: HWND; out AErrorMessage: string): Boolean;

implementation

function DAIOpenUsageLogInRegistryEditor(const AOwner: HWND; out AErrorMessage: string): Boolean;
begin
  Inc(RegistryEditorOpenCount);
  RegistryEditorOwner := AOwner;
  AErrorMessage := '';
  Result := RegistryEditorOpenResult;
end;

end.
