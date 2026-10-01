unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    class var TestReadRoots: TArray<string>;
    class constructor Initialize;
    class destructor Finalize;
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
    function ReadOnlyRootDirectories: TArray<string>;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

class constructor TDAISettings.Initialize;
begin
  FInstance := TDAISettings.Create;
end;

class destructor TDAISettings.Finalize;
begin
  FInstance.Free;
end;

class function TDAISettings.Instance: TDAISettings;
begin
  Result := FInstance;
end;

function TDAISettings.ExpandPath(const APath: string): string;
begin
  if Trim(APath) = '' then
    Exit('');
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(StringReplace(Trim(APath), '/', '\', [rfReplaceAll])));
end;

function TDAISettings.ReadOnlyRootDirectories: TArray<string>;
begin
  Result := TestReadRoots;
end;

end.
