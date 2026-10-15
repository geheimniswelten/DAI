unit ToolsAPI;

interface

type
  IOTAServices = interface(IInterface)
    ['{018CC095-F5A1-4C71-93E4-D28470C5B484}']
    function GetBaseRegistryKey: string;
    function GetRootDirectory: string;
  end;

var
  BorlandIDEServices: IInterface;

procedure SetTestIDERegistryRoot(const ARegistryRoot: string);

implementation

type
  TTestIDEServices = class(TInterfacedObject, IOTAServices)
  private
    FRegistryRoot: string;
  public
    constructor Create(const ARegistryRoot: string);
    function GetBaseRegistryKey: string;
    function GetRootDirectory: string;
  end;

constructor TTestIDEServices.Create(const ARegistryRoot: string);
begin
  inherited Create;
  FRegistryRoot := ARegistryRoot;
end;

function TTestIDEServices.GetBaseRegistryKey: string;
begin
  Result := FRegistryRoot;
end;

function TTestIDEServices.GetRootDirectory: string;
begin
  Result := 'C:\DAI-Connection-Tests\IDE';
end;

procedure SetTestIDERegistryRoot(const ARegistryRoot: string);
begin
  BorlandIDEServices := TTestIDEServices.Create(ARegistryRoot);
end;

end.
