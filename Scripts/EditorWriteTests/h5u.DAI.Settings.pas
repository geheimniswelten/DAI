unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  strict private
    class var FInstance: TDAISettings;
  public
    class constructor Initialize;
    class destructor Finalize;
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
    function ReadOnlyRootDirectories: TArray<string>;
    function DelphiSourceDirectory: string;
    function ToolsAPIDirectory: string;
    function SamplesDirectory: string;
    function CatalogRepositoryDirectory: string;
    function CatalogRepositoryAllUsersDirectory: string;
  end;

implementation

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
  Result := APath;
end;

function TDAISettings.ReadOnlyRootDirectories: TArray<string>;
begin
  Result := nil;
end;

function TDAISettings.DelphiSourceDirectory: string;
begin
  Result := '';
end;

function TDAISettings.ToolsAPIDirectory: string;
begin
  Result := '';
end;

function TDAISettings.SamplesDirectory: string;
begin
  Result := '';
end;

function TDAISettings.CatalogRepositoryDirectory: string;
begin
  Result := '';
end;

function TDAISettings.CatalogRepositoryAllUsersDirectory: string;
begin
  Result := '';
end;

end.
