unit h5u.DAI.Lifecycle.Policy;

interface

type
  TDAILifecyclePolicy = class sealed
  public
    class var Allowed: Boolean;
    class function ReadAllowed(out AReason: string): Boolean; static;
  end;

implementation

class function TDAILifecyclePolicy.ReadAllowed(out AReason: string): Boolean;
begin
  Result := Allowed;
  if Result then
    AReason := 'allowed'
  else
    AReason := 'disabled_in_dai_options';
end;

end.
