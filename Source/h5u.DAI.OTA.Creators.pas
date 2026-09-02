unit h5u.DAI.OTA.Creators;

interface

uses
  ToolsAPI;

type
  TDAIProjectKind = (
    pkConsole,
    pkVCL
  );

  TDAIModuleCreator = class sealed
  public
    class function CreateUnit(const AProject: IOTAProject; const AFileName: string; const ASource: string): IOTACreator; static;
    class function CreateForm(const AProject: IOTAProject; const AFileName: string; const AFormName: string; const AAncestorName: string; const AMainForm: Boolean):
      IOTACreator; static;
  end;

  TDAIProjectCreator = class(TInterfacedObject, IOTACreator, IOTAProjectCreator, IOTAProjectCreator50, IOTAProjectCreator80, IOTAProjectCreator160,
    IOTAProjectCreator190)
  private
    FFileName: string;
    FKind: TDAIProjectKind;
    FOwner: IOTAModule;
    FProjectName: string;
  public
    constructor Create(const AOwner: IOTAProjectGroup; const AFileName: string; const AKind: TDAIProjectKind);

    function GetCreatorType: string;
    function GetExisting: Boolean;
    function GetFileSystem: string;
    function GetOwner: IOTAModule;
    function GetUnnamed: Boolean;

    function GetFileName: string;
    function GetOptionFileName: string;
    function GetShowSource: Boolean;
    procedure NewDefaultModule;
    function NewOptionSource(const ProjectName: string): IOTAFile;
    procedure NewProjectResource(const Project: IOTAProject);
    function NewProjectSource(const ProjectName: string): IOTAFile;

    procedure NewDefaultProjectModule(const Project: IOTAProject);

    function GetProjectPersonality: string;

    function GetFrameworkType: string;
    function GetPlatforms: TArray<string>;
    function GetPreferredPlatform: string;
    procedure SetInitialOptions(const NewProject: IOTAProject);

    function GetSupportedPlatforms: TArray<string>;
  end;

implementation

uses
  System.Character,
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  PlatformAPI;

type
  TDAIStringFile = class(TInterfacedObject, IOTAFile)
  private
    FSource: string;
  public
    constructor Create(const ASource: string);
    function GetAge: TDateTime;
    function GetSource: string;
  end;

  TDAIModuleCreatorKind = (
    mckUnit,
    mckForm
  );

  TDAIModuleCreatorImpl = class(TInterfacedObject, IOTACreator, IOTAModuleCreator)
  private
    FAncestorName: string;
    FFileName: string;
    FFormName: string;
    FKind: TDAIModuleCreatorKind;
    FMainForm: Boolean;
    FOwner: IOTAModule;
    FSource: string;
    FUnitName: string;
    function EffectiveAncestorName(const AAncestorIdent: string): string;
    function EffectiveFormName(const AFormIdent: string): string;
    function FormClassName(const AFormIdent: string): string;
    function BuildDefaultUnitSource: string;
    function BuildFormSource(const AFormIdent: string; const AAncestorIdent: string): string;
    function BuildFormResource(const AFormIdent: string): string;
  public
    constructor CreateUnit(const AProject: IOTAProject; const AFileName: string; const ASource: string);
    constructor CreateForm(const AProject: IOTAProject; const AFileName: string; const AFormName: string; const AAncestorName: string; const AMainForm: Boolean);

    function GetCreatorType: string;
    function GetExisting: Boolean;
    function GetFileSystem: string;
    function GetOwner: IOTAModule;
    function GetUnnamed: Boolean;

    function GetAncestorName: string;
    function GetImplFileName: string;
    function GetIntfFileName: string;
    function GetFormName: string;
    function GetMainForm: Boolean;
    function GetShowForm: Boolean;
    function GetShowSource: Boolean;
    function NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
    function NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    function NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    procedure FormCreated(const FormEditor: IOTAFormEditor);
  end;

function NormalizeIdentifier(const AValue: string; const AFallback: string): string;
var
  LCharacter: Char;
  LIndex: Integer;
begin
  Result := Trim(AValue);
  if Result = '' then
    Result := AFallback;

  for LIndex := 1 to Length(Result) do
  begin
    LCharacter := Result[LIndex];
    if not (TCharacter.IsLetterOrDigit(LCharacter) or (LCharacter = '_')) then
      Result[LIndex] := '_';
  end;

  if (Result = '') or not (TCharacter.IsLetter(Result[1]) or (Result[1] = '_')) then
    Result := '_' + Result;
end;

function EscapePascalString(const AValue: string): string;
begin
  Result := StringReplace(AValue, '''', '''''', [rfReplaceAll]);
end;

{ TDAIStringFile }

constructor TDAIStringFile.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
end;

function TDAIStringFile.GetAge: TDateTime;
begin
  Result := -1;
end;

function TDAIStringFile.GetSource: string;
begin
  Result := FSource;
end;

{ TDAIModuleCreator }

class function TDAIModuleCreator.CreateForm(const AProject: IOTAProject; const AFileName: string; const AFormName: string; const AAncestorName: string; const AMainForm: Boolean):
  IOTACreator;
begin
  Result := TDAIModuleCreatorImpl.CreateForm(AProject, AFileName, AFormName, AAncestorName, AMainForm);
end;

class function TDAIModuleCreator.CreateUnit(const AProject: IOTAProject; const AFileName: string; const ASource: string): IOTACreator;
begin
  Result := TDAIModuleCreatorImpl.CreateUnit(AProject, AFileName, ASource);
end;

{ TDAIModuleCreatorImpl }

constructor TDAIModuleCreatorImpl.CreateForm(const AProject: IOTAProject; const AFileName: string; const AFormName: string; const AAncestorName: string; const AMainForm: Boolean);
begin
  inherited Create;
  FAncestorName := NormalizeIdentifier(AAncestorName, 'TForm');
  FFileName := TPath.GetFullPath(AFileName);
  FFormName := NormalizeIdentifier(AFormName, 'Form1');
  FKind := mckForm;
  FMainForm := AMainForm;
  FOwner := AProject;
  FUnitName := NormalizeIdentifier(TPath.GetFileNameWithoutExtension(FFileName), 'Unit1');
end;

constructor TDAIModuleCreatorImpl.CreateUnit(const AProject: IOTAProject; const AFileName: string; const ASource: string);
begin
  inherited Create;
  FFileName := TPath.GetFullPath(AFileName);
  FKind := mckUnit;
  FOwner := AProject;
  FSource := ASource;
  FUnitName := NormalizeIdentifier(TPath.GetFileNameWithoutExtension(FFileName), 'Unit1');
end;

function TDAIModuleCreatorImpl.BuildDefaultUnitSource: string;
begin
  Result := 'unit ' + FUnitName + ';' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak + 'implementation' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function TDAIModuleCreatorImpl.BuildFormResource(const AFormIdent: string): string;
var
  LFormName: string;
begin
  LFormName := EffectiveFormName(AFormIdent);
  Result := 'object ' + LFormName + ': ' + FormClassName(LFormName) + sLineBreak + '  Left = 0' + sLineBreak + '  Top = 0' + sLineBreak +
    '  Caption = ''' + EscapePascalString(LFormName) + '''' + sLineBreak + '  ClientHeight = 480' + sLineBreak + '  ClientWidth = 640' + sLineBreak +
    '  Color = clBtnFace' + sLineBreak + '  Font.Charset = DEFAULT_CHARSET' + sLineBreak + '  Font.Color = clWindowText' + sLineBreak +
    '  Font.Height = -12' + sLineBreak + '  Font.Name = ''Segoe UI''' + sLineBreak + '  Font.Style = []' + sLineBreak + '  Position = poScreenCenter' +
    sLineBreak + '  TextHeight = 15' + sLineBreak + 'end' + sLineBreak;
end;

function TDAIModuleCreatorImpl.BuildFormSource(const AFormIdent: string; const AAncestorIdent: string): string;
var
  LAncestorName: string;
  LFormName: string;
begin
  LAncestorName := EffectiveAncestorName(AAncestorIdent);
  LFormName := EffectiveFormName(AFormIdent);
  Result := 'unit ' + FUnitName + ';' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak + 'uses' + sLineBreak +
    '  System.Classes,' + sLineBreak + '  Vcl.Controls,' + sLineBreak + '  Vcl.Forms;' + sLineBreak + sLineBreak + 'type' + sLineBreak + '  ' +
    FormClassName(LFormName) + ' = class(' + LAncestorName + ')' + sLineBreak + '  end;' + sLineBreak + sLineBreak + 'var' + sLineBreak + '  ' + LFormName +
    ': ' + FormClassName(LFormName) + ';' + sLineBreak + sLineBreak + 'implementation' + sLineBreak + sLineBreak + '{$R *.dfm}' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function TDAIModuleCreatorImpl.EffectiveAncestorName(const AAncestorIdent: string): string;
begin
  if Trim(AAncestorIdent) <> '' then
    Result := NormalizeIdentifier(AAncestorIdent, 'TForm')
  else
    Result := FAncestorName;
end;

function TDAIModuleCreatorImpl.EffectiveFormName(const AFormIdent: string): string;
begin
  if Trim(AFormIdent) <> '' then
    Result := NormalizeIdentifier(AFormIdent, 'Form1')
  else
    Result := FFormName;
end;

function TDAIModuleCreatorImpl.FormClassName(const AFormIdent: string): string;
var
  LFormName: string;
begin
  LFormName := EffectiveFormName(AFormIdent);
  if LFormName.StartsWith('T', True) then
    Result := LFormName
  else
    Result := 'T' + LFormName;
end;

procedure TDAIModuleCreatorImpl.FormCreated(const FormEditor: IOTAFormEditor);
begin
end;

function TDAIModuleCreatorImpl.GetAncestorName: string;
begin
  if FKind = mckForm then
    Result := FAncestorName
  else
    Result := '';
end;

function TDAIModuleCreatorImpl.GetCreatorType: string;
begin
  if FKind = mckForm then
    Result := sForm
  else
    Result := sUnit;
end;

function TDAIModuleCreatorImpl.GetExisting: Boolean;
begin
  Result := False;
end;

function TDAIModuleCreatorImpl.GetFileSystem: string;
begin
  Result := '';
end;

function TDAIModuleCreatorImpl.GetFormName: string;
begin
  if FKind = mckForm then
    Result := FFormName
  else
    Result := '';
end;

function TDAIModuleCreatorImpl.GetImplFileName: string;
begin
  Result := FFileName;
end;

function TDAIModuleCreatorImpl.GetIntfFileName: string;
begin
  Result := '';
end;

function TDAIModuleCreatorImpl.GetMainForm: Boolean;
begin
  Result := (FKind = mckForm) and FMainForm;
end;

function TDAIModuleCreatorImpl.GetOwner: IOTAModule;
begin
  Result := FOwner;
end;

function TDAIModuleCreatorImpl.GetShowForm: Boolean;
begin
  Result := FKind = mckForm;
end;

function TDAIModuleCreatorImpl.GetShowSource: Boolean;
begin
  Result := True;
end;

function TDAIModuleCreatorImpl.GetUnnamed: Boolean;
begin
  Result := False;
end;

function TDAIModuleCreatorImpl.NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
begin
  if FKind = mckForm then
    Result := TDAIStringFile.Create(BuildFormResource(FormIdent))
  else
    Result := nil;
end;

function TDAIModuleCreatorImpl.NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  if FKind = mckForm then
    Result := TDAIStringFile.Create(BuildFormSource(FormIdent, AncestorIdent))
  else if FSource <> '' then
    Result := TDAIStringFile.Create(FSource)
  else
    Result := TDAIStringFile.Create(BuildDefaultUnitSource);
end;

function TDAIModuleCreatorImpl.NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;
end;

{ TDAIProjectCreator }

constructor TDAIProjectCreator.Create(const AOwner: IOTAProjectGroup; const AFileName: string; const AKind: TDAIProjectKind);
begin
  inherited Create;
  FFileName := TPath.GetFullPath(AFileName);
  FKind := AKind;
  FOwner := AOwner;
  FProjectName := NormalizeIdentifier(TPath.GetFileNameWithoutExtension(FFileName), 'Project1');
end;

function TDAIProjectCreator.GetCreatorType: string;
begin
  if FKind = pkVCL then
    Result := sApplication
  else
    Result := sConsole;
end;

function TDAIProjectCreator.GetExisting: Boolean;
begin
  Result := False;
end;

function TDAIProjectCreator.GetFileName: string;
begin
  Result := FFileName;
end;

function TDAIProjectCreator.GetFileSystem: string;
begin
  Result := '';
end;

function TDAIProjectCreator.GetFrameworkType: string;
begin
  if FKind = pkVCL then
    Result := sFrameworkTypeVCL
  else
    Result := sFrameworkTypeNone;
end;

function TDAIProjectCreator.GetOptionFileName: string;
begin
  Result := '';
end;

function TDAIProjectCreator.GetOwner: IOTAModule;
begin
  Result := FOwner;
end;

function TDAIProjectCreator.GetPlatforms: TArray<string>;
begin
  Result := [cWin32Platform, cWin64Platform];
end;

function TDAIProjectCreator.GetPreferredPlatform: string;
begin
  Result := cWin32Platform;
end;

function TDAIProjectCreator.GetProjectPersonality: string;
begin
  Result := sDelphiPersonality;
end;

function TDAIProjectCreator.GetShowSource: Boolean;
begin
  Result := True;
end;

function TDAIProjectCreator.GetSupportedPlatforms: TArray<string>;
begin
  Result := GetPlatforms;
end;

function TDAIProjectCreator.GetUnnamed: Boolean;
begin
  Result := False;
end;

procedure TDAIProjectCreator.NewDefaultModule;
begin
end;

procedure TDAIProjectCreator.NewDefaultProjectModule(const Project: IOTAProject);
begin
end;

function TDAIProjectCreator.NewOptionSource(const ProjectName: string): IOTAFile;
begin
  Result := nil;
end;

procedure TDAIProjectCreator.NewProjectResource(const Project: IOTAProject);
begin
end;

function TDAIProjectCreator.NewProjectSource(const ProjectName: string): IOTAFile;
var
  LSource: string;
begin
  if FKind = pkVCL then
    LSource := 'program ' + FProjectName + ';' + sLineBreak + sLineBreak + 'uses' + sLineBreak + '  Vcl.Forms;' + sLineBreak + sLineBreak + 'begin' +
      sLineBreak + '  Application.Initialize;' + sLineBreak + '  Application.MainFormOnTaskbar := True;' + sLineBreak + '  Application.Run;' + sLineBreak +
      'end.' + sLineBreak
  else
    LSource := 'program ' + FProjectName + ';' + sLineBreak + sLineBreak + '{$APPTYPE CONSOLE}' + sLineBreak + sLineBreak + 'begin' + sLineBreak + 'end.' +
      sLineBreak;
  Result := TDAIStringFile.Create(LSource);
end;

procedure TDAIProjectCreator.SetInitialOptions(const NewProject: IOTAProject);
begin
end;

end.
