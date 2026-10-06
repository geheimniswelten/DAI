unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  public
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
  end;

implementation

uses System.IOUtils;

var GSettings: TDAISettings;

class function TDAISettings.Instance: TDAISettings;
begin
  if GSettings = nil then GSettings := TDAISettings.Create;
  Result := GSettings;
end;

function TDAISettings.ExpandPath(const APath: string): string;
begin
  Result := TPath.GetFullPath(APath);
end;

initialization
  GSettings := nil;

finalization
  GSettings.Free;
end.
