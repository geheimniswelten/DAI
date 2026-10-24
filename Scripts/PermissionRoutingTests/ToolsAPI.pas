unit ToolsAPI;

interface

type
  IOTAProject = interface
    ['{75B6B40B-A13D-4914-A4E4-CA690A0DFF04}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;

implementation

end.
