unit h5u.DAI.Settings;

interface

type
  TDAISettings = class sealed
  public
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
  end;

implementation

uses
  System.SysUtils;

class function TDAISettings.Instance: TDAISettings;
begin
  raise Exception.Create('Unexpected settings lookup');
end;

function TDAISettings.ExpandPath(const APath: string): string;
begin
  raise Exception.Create('Unexpected path expansion');
end;

end.
