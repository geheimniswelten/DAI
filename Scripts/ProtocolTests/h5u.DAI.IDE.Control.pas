unit h5u.DAI.IDE.Control;

interface

type
  TDAIIDEControl = class sealed
  public
    class var Completed: Integer;
    class procedure PrepareFixtureClose; static;
    class procedure ResetDeferredClose; static;
    class function HasDeferredClose: Boolean; static;
    class function CompleteDeferredClose: Boolean; static;
  end;

implementation

uses Winapi.Windows;

threadvar Pending: Boolean;

class procedure TDAIIDEControl.PrepareFixtureClose;
begin
  Pending := True;
end;

class procedure TDAIIDEControl.ResetDeferredClose;
begin
  Pending := False;
end;

class function TDAIIDEControl.HasDeferredClose: Boolean;
begin
  Result := Pending;
end;

class function TDAIIDEControl.CompleteDeferredClose: Boolean;
begin
  Result := Pending;
  Pending := False;
  if Result then
    InterlockedIncrement(Completed);
end;

end.
