unit h5u.DAI.Lifecycle.Policy;

interface

type
  TDAILifecyclePolicy = class sealed
  public
    class function ReadAllowed(out AReason: string): Boolean; static;
  end;

implementation

class function TDAILifecyclePolicy.ReadAllowed(out AReason: string): Boolean;
begin
  AReason := 'isolated in-memory policy';
  Result := True;
end;

end.
