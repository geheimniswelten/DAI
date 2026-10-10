unit h5u.DAI.Log;

interface

type
  TDAILog = class sealed
  public
    class procedure Access(const AText: string); static;
  end;

implementation

class procedure TDAILog.Access(const AText: string);
begin
end;

end.
