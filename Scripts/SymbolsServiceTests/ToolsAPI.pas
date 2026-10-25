unit ToolsAPI;

interface

type
  IOTAProject = interface
    ['{7F7F79BF-4E62-4A93-B6A3-7FC0C031CF00}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;

  IOTAProjectGroup = interface
    ['{CFB2C90D-4349-49D6-A96F-69E6A6C6DA47}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;

implementation

end.
