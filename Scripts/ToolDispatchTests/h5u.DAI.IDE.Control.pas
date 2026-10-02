unit h5u.DAI.IDE.Control;

interface

uses
  System.JSON;

type
  TDAIIDEControl = class sealed
  public
    class var ControlCalls: Integer;
    class var DeferredCloseCalls: Integer;
    class var LastAction: string;
    class procedure Reset; static;
    class function Control(const AAction: string): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils;

class procedure TDAIIDEControl.Reset;
begin
  ControlCalls := 0;
  DeferredCloseCalls := 0;
  LastAction := '';
end;

class function TDAIIDEControl.Control(const AAction: string): TJSONObject;
begin
  Inc(ControlCalls);
  LastAction := AAction;
  if (AAction <> 'minimize') and (AAction <> 'restore') and (AAction <> 'foreground') and
    (AAction <> 'background') and (AAction <> 'close') then
    raise EArgumentException.Create('Das Testdouble erwartet eine kanonische, gueltige Aktion.');
  if AAction = 'close' then
    Inc(DeferredCloseCalls);
  Result := TJSONObject.Create;
  Result.AddPair('action', AAction);
  Result.AddPair('success', TJSONBool.Create(True));
end;

end.
