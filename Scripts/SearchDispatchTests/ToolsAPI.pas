unit ToolsAPI;

interface

type
  IOTAProject = interface(IInterface)
    ['{66A6D995-D2CD-4E17-82C7-4BA47B61BFA7}']
    function GetFileName: string;
    function GetFiles: TArray<string>;
    property FileName: string read GetFileName;
    property Files: TArray<string> read GetFiles;
  end;

  IOTAProjectGroup = interface(IInterface)
    ['{69281BF6-94AC-4E23-B2BE-DAE5F3DAA7F2}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;

  IOTASourceEditor = interface(IInterface)
    ['{ECE1DB46-84AD-4F28-A572-2049BFA690C0}']
  end;

  TTestProject = class(TInterfacedObject, IOTAProject)
  private
    FFileName: string;
    FFiles: TArray<string>;
  public
    constructor Create(const AFileName: string; const AFiles: TArray<string>);
    function GetFileName: string;
    function GetFiles: TArray<string>;
  end;

  TTestProjectGroup = class(TInterfacedObject, IOTAProjectGroup)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    function GetFileName: string;
  end;

  TTestSourceEditor = class(TInterfacedObject, IOTASourceEditor);

implementation

constructor TTestProject.Create(const AFileName: string; const AFiles: TArray<string>);
begin
  inherited Create;
  FFileName := AFileName;
  FFiles := AFiles;
end;

function TTestProject.GetFileName: string;
begin
  Result := FFileName;
end;

function TTestProject.GetFiles: TArray<string>;
begin
  Result := FFiles;
end;

constructor TTestProjectGroup.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

function TTestProjectGroup.GetFileName: string;
begin
  Result := FFileName;
end;

end.
