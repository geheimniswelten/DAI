unit h5u.DAI.Log;

interface

uses
  System.Classes;

type
  TDAILog = class sealed
  public
    class var Messages: TStringList;
    class procedure Error(const AText: string); static;
  end;

implementation

class procedure TDAILog.Error(const AText: string);
begin
  Messages.Add(AText);
end;

initialization
  TDAILog.Messages := TStringList.Create;

finalization
  TDAILog.Messages.Free;

end.
