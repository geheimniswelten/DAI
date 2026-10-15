unit h5u.DAI.OTA.Creators;

interface

uses ToolsAPI;

type
  TDAIProjectKind = (pkConsole, pkVCL);
  TDAIModuleCreator = class sealed
    class function CreateUnit(const AProject: IOTAProject; const AFileName, ASource: string): IOTACreator; static;
    class function CreateForm(const AProject: IOTAProject; const AFileName, AFormName, AAncestorName: string;
      const AMainForm: Boolean; const AUnnamed: Boolean = False): IOTACreator; static;
  end;
  TDAIProjectCreator = class(TInterfacedObject, IOTACreator)
  private
    FOwner: IOTAModule;
    FFileName: string;
    FUnnamed: Boolean;
    FMainFormModule: IOTAModule;
    FMainUnitFileName, FMainFormName: string;
  public
    constructor Create(const AOwner: IOTAProjectGroup; const AFileName: string; const AKind: TDAIProjectKind;
      const AUnnamed: Boolean = False);
    function GetOwner: IOTAModule;
    function GetUnnamed: Boolean;
    function GetFileName: string;
    function GetCreatorType: string;
    procedure NewDefaultProjectModule(const AProject: IOTAProject);
    property MainFormModule: IOTAModule read FMainFormModule;
    property MainFormName: string read FMainFormName;
    property MainUnitFileName: string read FMainUnitFileName;
  end;

implementation

class function TDAIModuleCreator.CreateUnit(const AProject: IOTAProject; const AFileName, ASource: string): IOTACreator;
begin Result := nil; end;
class function TDAIModuleCreator.CreateForm(const AProject: IOTAProject; const AFileName, AFormName, AAncestorName: string;
  const AMainForm, AUnnamed: Boolean): IOTACreator;
begin Result := nil; end;
constructor TDAIProjectCreator.Create(const AOwner: IOTAProjectGroup; const AFileName: string; const AKind: TDAIProjectKind;
  const AUnnamed: Boolean);
begin
  inherited Create;
  FOwner := AOwner;
  FFileName := AFileName;
  FUnnamed := AUnnamed;
end;
function TDAIProjectCreator.GetOwner: IOTAModule;
begin Result := FOwner; end;
function TDAIProjectCreator.GetUnnamed: Boolean;
begin Result := FUnnamed; end;
function TDAIProjectCreator.GetFileName: string;
begin Result := FFileName; end;
function TDAIProjectCreator.GetCreatorType: string;
begin Result := 'Console'; end;
procedure TDAIProjectCreator.NewDefaultProjectModule(const AProject: IOTAProject);
begin end;

end.
