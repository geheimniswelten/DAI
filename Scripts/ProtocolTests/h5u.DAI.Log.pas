unit h5u.DAI.Log;
interface
type TDAILog = class
  class procedure Access(const AText: string); static;
  class procedure Error(const AText: string); static;
end;
implementation
class procedure TDAILog.Access(const AText: string);
begin end;
class procedure TDAILog.Error(const AText: string);
begin end;
end.