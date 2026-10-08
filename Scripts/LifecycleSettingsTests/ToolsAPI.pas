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

implementation

initialization
  BorlandIDEServices := nil;

end.
