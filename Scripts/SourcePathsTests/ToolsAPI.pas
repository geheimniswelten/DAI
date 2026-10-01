unit ToolsAPI;

interface

type
  // Only the read-only service members used by the real Settings unit are supplied.
  IOTAServices = interface(IInterface)
    ['{865099ED-089F-4E73-9F2A-56A3E4DA3139}']
    function GetBaseRegistryKey: string;
    function GetRootDirectory: string;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
