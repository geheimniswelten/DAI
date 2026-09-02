unit CodexMCP.OTA.Creators;

interface

uses
  ToolsAPI;

type
  TCodexProjectKind = (cpkConsole, cpkVcl);

function CreateDelphiProject(
  const ADirectory,
  AProjectName: string;
  const AKind: TCodexProjectKind;
  out AProject: IOTAProject
): Boolean;

function CreateDelphiUnit(
  const AProject: IOTAProject;
  const AFileName,
  AUnitName,
  ASource: string;
  out AModule: IOTAModule
): Boolean;

function CreateDelphiFormUnit(
  const AProject: IOTAProject;
  const AFileName,
  AUnitName,
  AFormName,
  AAncestorName,
  ASource,
  AFormSource: string;
  const AMainForm: Boolean;
  out AModule: IOTAModule
): Boolean;

implementation

uses
  PlatformAPI,
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  CodexMCP.OTA.Common;

type
  TCodexStringFile = class(TInterfacedObject, IOTAFile)
  private
    FSource: string;
  public
    constructor Create(const ASource: string);
    function GetAge: TDateTime;
    function GetSource: string;
  end;

  TCodexModuleCreator = class(
    TInterfacedObject,
    IOTACreator,
    IOTAModuleCreator
  )
  private
    FAncestorName: string;
    FFileName: string;
    FFormName: string;
    FFormSource: string;
    FIsForm: Boolean;
    FMainForm: Boolean;
    FOwner: IOTAProject;
    FSource: string;
    FUnitName: string;
  public
    constructor CreateUnit(
      const AOwner: IOTAProject;
      const AFileName,
      AUnitName,
      ASource: string
    );
    constructor CreateFormUnit(
      const AOwner: IOTAProject;
      const AFileName,
      AUnitName,
      AFormName,
      AAncestorName,
      ASource,
      AFormSource: string;
      const AMainForm: Boolean
    );

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
    function NewFormFile(
      const FormIdent,
      AncestorIdent: string
    ): IOTAFile;
    function NewImplSource(
      const ModuleIdent,
      FormIdent,
      AncestorIdent: string
    ): IOTAFile;
    function NewIntfSource(
      const ModuleIdent,
      FormIdent,
      AncestorIdent: string
    ): IOTAFile;
    procedure FormCreated(const FormEditor: IOTAFormEditor);
  end;

  TCodexProjectCreator = class(
    TInterfacedObject,
    IOTACreator,
    IOTAProjectCreator,
    IOTAProjectCreator50,
    IOTAProjectCreator80,
    IOTAProjectCreator160
    {$IF CompilerVersion >= 32.0}, IOTAProjectCreator190{$ENDIF}
  )
  private
    FDirectory: string;
    FFileName: string;
    FKind: TCodexProjectKind;
    FProjectName: string;
  public
    constructor Create(
      const ADirectory,
      AProjectName: string;
      const AKind: TCodexProjectKind
    );

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

    {$IF CompilerVersion >= 32.0}
    function GetSupportedPlatforms: TArray<string>;
    {$ENDIF}
  end;

function DefaultUnitSource(const AUnitName: string): string;
begin
  Result :=
    'unit ' + AUnitName + ';' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function DefaultFormUnitSource(
  const AUnitName,
  AFormName,
  AAncestorName: string
): string;
var
  LAncestorUnit: string;
begin
  LAncestorUnit := 'Vcl.Forms';
  Result :=
    'unit ' + AUnitName + ';' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses' + sLineBreak +
    '  System.Classes,' + sLineBreak +
    '  ' + LAncestorUnit + ';' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  T' + AFormName + ' = class(' + AAncestorName + ')' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'var' + sLineBreak +
    '  ' + AFormName + ': T' + AFormName + ';' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    '{$R *.dfm}' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function DefaultDfmSource(
  const AFormName,
  AAncestorName: string
): string;
begin
  Result :=
    'object ' + AFormName + ': T' + AFormName + sLineBreak +
    '  Left = 0' + sLineBreak +
    '  Top = 0' + sLineBreak +
    '  Caption = ''' + AFormName + '''' + sLineBreak +
    '  ClientHeight = 480' + sLineBreak +
    '  ClientWidth = 720' + sLineBreak +
    '  Color = clBtnFace' + sLineBreak +
    '  Font.Charset = DEFAULT_CHARSET' + sLineBreak +
    '  Font.Color = clWindowText' + sLineBreak +
    '  Font.Height = -12' + sLineBreak +
    '  Font.Name = ''Segoe UI''' + sLineBreak +
    '  Font.Style = []' + sLineBreak +
    '  TextHeight = 15' + sLineBreak +
    'end' + sLineBreak;
end;

{ TCodexStringFile }

constructor TCodexStringFile.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
end;

function TCodexStringFile.GetAge: TDateTime;
begin
  Result := -1;
end;

function TCodexStringFile.GetSource: string;
begin
  Result := FSource;
end;

{ TCodexModuleCreator }

constructor TCodexModuleCreator.CreateUnit(
  const AOwner: IOTAProject;
  const AFileName,
  AUnitName,
  ASource: string
);
begin
  inherited Create;
  FOwner := AOwner;
  FFileName := AFileName;
  FUnitName := AUnitName;
  FSource := ASource;
  FIsForm := False;
  FMainForm := False;
end;

constructor TCodexModuleCreator.CreateFormUnit(
  const AOwner: IOTAProject;
  const AFileName,
  AUnitName,
  AFormName,
  AAncestorName,
  ASource,
  AFormSource: string;
  const AMainForm: Boolean
);
begin
  inherited Create;
  FOwner := AOwner;
  FFileName := AFileName;
  FUnitName := AUnitName;
  FFormName := AFormName;
  FAncestorName := AAncestorName;
  FSource := ASource;
  FFormSource := AFormSource;
  FIsForm := True;
  FMainForm := AMainForm;
end;

procedure TCodexModuleCreator.FormCreated(const FormEditor: IOTAFormEditor);
begin
end;

function TCodexModuleCreator.GetAncestorName: string;
begin
  Result := FAncestorName;
end;

function TCodexModuleCreator.GetCreatorType: string;
begin
  if FIsForm then
    Result := sForm
  else
    Result := sUnit;
end;

function TCodexModuleCreator.GetExisting: Boolean;
begin
  Result := False;
end;

function TCodexModuleCreator.GetFileSystem: string;
begin
  Result := '';
end;

function TCodexModuleCreator.GetFormName: string;
begin
  Result := FFormName;
end;

function TCodexModuleCreator.GetImplFileName: string;
begin
  Result := FFileName;
end;

function TCodexModuleCreator.GetIntfFileName: string;
begin
  Result := '';
end;

function TCodexModuleCreator.GetMainForm: Boolean;
begin
  Result := FMainForm;
end;

function TCodexModuleCreator.GetOwner: IOTAModule;
begin
  Result := FOwner;
end;

function TCodexModuleCreator.GetShowForm: Boolean;
begin
  Result := FIsForm;
end;

function TCodexModuleCreator.GetShowSource: Boolean;
begin
  Result := True;
end;

function TCodexModuleCreator.GetUnnamed: Boolean;
begin
  Result := False;
end;

function TCodexModuleCreator.NewFormFile(
  const FormIdent,
  AncestorIdent: string
): IOTAFile;
begin
  if FIsForm then
    Result := TCodexStringFile.Create(FFormSource)
  else
    Result := nil;
end;

function TCodexModuleCreator.NewImplSource(
  const ModuleIdent,
  FormIdent,
  AncestorIdent: string
): IOTAFile;
begin
  Result := TCodexStringFile.Create(FSource);
end;

function TCodexModuleCreator.NewIntfSource(
  const ModuleIdent,
  FormIdent,
  AncestorIdent: string
): IOTAFile;
begin
  Result := nil;
end;

{ TCodexProjectCreator }

constructor TCodexProjectCreator.Create(
  const ADirectory,
  AProjectName: string;
  const AKind: TCodexProjectKind
);
begin
  inherited Create;
  FDirectory := ADirectory;
  FProjectName := AProjectName;
  FFileName := TPath.Combine(FDirectory, FProjectName + '.dpr');
  FKind := AKind;
end;

function TCodexProjectCreator.GetCreatorType: string;
begin
  if FKind = cpkConsole then
    Result := sConsole
  else
    Result := sApplication;
end;

function TCodexProjectCreator.GetExisting: Boolean;
begin
  Result := False;
end;

function TCodexProjectCreator.GetFileName: string;
begin
  Result := FFileName;
end;

function TCodexProjectCreator.GetFileSystem: string;
begin
  Result := '';
end;

function TCodexProjectCreator.GetFrameworkType: string;
begin
  if FKind = cpkConsole then
    Result := sFrameworkTypeNone
  else
    Result := sFrameworkTypeVCL;
end;

function TCodexProjectCreator.GetOptionFileName: string;
begin
  Result := '';
end;

function TCodexProjectCreator.GetOwner: IOTAModule;
var
  LModuleServices: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Result := LModuleServices.MainProjectGroup;
end;

function TCodexProjectCreator.GetPlatforms: TArray<string>;
begin
  Result := [cWin32Platform, cWin64Platform];
end;

function TCodexProjectCreator.GetPreferredPlatform: string;
begin
  Result := cWin32Platform;
end;

function TCodexProjectCreator.GetProjectPersonality: string;
begin
  Result := sDelphiPersonality;
end;

function TCodexProjectCreator.GetShowSource: Boolean;
begin
  Result := True;
end;

{$IF CompilerVersion >= 32.0}
function TCodexProjectCreator.GetSupportedPlatforms: TArray<string>;
begin
  Result := GetPlatforms;
end;
{$ENDIF}

function TCodexProjectCreator.GetUnnamed: Boolean;
begin
  Result := False;
end;

procedure TCodexProjectCreator.NewDefaultModule;
begin
end;

procedure TCodexProjectCreator.NewDefaultProjectModule(
  const Project: IOTAProject
);
var
  LModuleServices: IOTAModuleServices;
  LUnitFile: string;
begin
  if (FKind <> cpkVcl) or not Assigned(Project) then
    Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Exit;
  LUnitFile := TPath.Combine(FDirectory, 'MainFormUnit.pas');
  LModuleServices.CreateModule(
    TCodexModuleCreator.CreateFormUnit(
      Project,
      LUnitFile,
      'MainFormUnit',
      'MainForm',
      'TForm',
      DefaultFormUnitSource('MainFormUnit', 'MainForm', 'TForm'),
      DefaultDfmSource('MainForm', 'TForm'),
      True
    )
  );
end;

function TCodexProjectCreator.NewOptionSource(
  const ProjectName: string
): IOTAFile;
begin
  Result := nil;
end;

procedure TCodexProjectCreator.NewProjectResource(const Project: IOTAProject);
begin
end;

function TCodexProjectCreator.NewProjectSource(
  const ProjectName: string
): IOTAFile;
var
  LSource: string;
begin
  if FKind = cpkConsole then
    LSource :=
      'program ' + FProjectName + ';' + sLineBreak + sLineBreak +
      '{$APPTYPE CONSOLE}' + sLineBreak + sLineBreak +
      'uses' + sLineBreak +
      '  System.SysUtils;' + sLineBreak + sLineBreak +
      'begin' + sLineBreak +
      'end.' + sLineBreak
  else
    LSource :=
      'program ' + FProjectName + ';' + sLineBreak + sLineBreak +
      'uses' + sLineBreak +
      '  Vcl.Forms;' + sLineBreak + sLineBreak +
      '{$R *.res}' + sLineBreak + sLineBreak +
      'begin' + sLineBreak +
      '  Application.Initialize;' + sLineBreak +
      '  Application.MainFormOnTaskbar := True;' + sLineBreak +
      '  Application.Run;' + sLineBreak +
      'end.' + sLineBreak;
  Result := TCodexStringFile.Create(LSource);
end;

procedure TCodexProjectCreator.SetInitialOptions(
  const NewProject: IOTAProject
);
begin
end;

function CreateDelphiProject(
  const ADirectory,
  AProjectName: string;
  const AKind: TCodexProjectKind;
  out AProject: IOTAProject
): Boolean;
var
  LModule: IOTAModule;
  LModuleServices: IOTAModuleServices;
  LProjectFile: string;
begin
  AProject := nil;
  Result := False;
  if not IsValidIdent(AProjectName) then
    raise EArgumentException.CreateFmt(
      '"%s" ist kein gültiger Delphi-Projektbezeichner.',
      [AProjectName]
    );
  ForceDirectories(ADirectory);
  LProjectFile := TPath.Combine(ADirectory, AProjectName + '.dpr');
  if TFile.Exists(LProjectFile) or
    TFile.Exists(ChangeFileExt(LProjectFile, '.dproj')) then
    raise EFileAlreadyExistsException.Create(LProjectFile);
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Exit;
  LModule := LModuleServices.CreateModule(
    TCodexProjectCreator.Create(ADirectory, AProjectName, AKind)
  );
  Result := Supports(LModule, IOTAProject, AProject);
end;

function CreateDelphiUnit(
  const AProject: IOTAProject;
  const AFileName,
  AUnitName,
  ASource: string;
  out AModule: IOTAModule
): Boolean;
var
  LModuleServices: IOTAModuleServices;
  LSource: string;
begin
  AModule := nil;
  Result := False;
  if not Assigned(AProject) then
    raise EArgumentNilException.Create('AProject');
  if not IsValidIdent(AUnitName) then
    raise EArgumentException.CreateFmt(
      '"%s" ist kein gültiger Delphi-Unitbezeichner.',
      [AUnitName]
    );
  if TFile.Exists(AFileName) then
    raise EFileAlreadyExistsException.Create(AFileName);
  ForceDirectories(TPath.GetDirectoryName(AFileName));
  LSource := ASource;
  if Trim(LSource) = '' then
    LSource := DefaultUnitSource(AUnitName);
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Exit;
  AModule := LModuleServices.CreateModule(
    TCodexModuleCreator.CreateUnit(
      AProject,
      AFileName,
      AUnitName,
      LSource
    )
  );
  Result := Assigned(AModule);
end;

function CreateDelphiFormUnit(
  const AProject: IOTAProject;
  const AFileName,
  AUnitName,
  AFormName,
  AAncestorName,
  ASource,
  AFormSource: string;
  const AMainForm: Boolean;
  out AModule: IOTAModule
): Boolean;
var
  LDfmFile: string;
  LFormSource: string;
  LModuleServices: IOTAModuleServices;
  LSource: string;
begin
  AModule := nil;
  Result := False;
  if not Assigned(AProject) then
    raise EArgumentNilException.Create('AProject');
  if not IsValidIdent(AUnitName) then
    raise EArgumentException.CreateFmt(
      '"%s" ist kein gültiger Delphi-Unitbezeichner.',
      [AUnitName]
    );
  if not IsValidIdent(AFormName) then
    raise EArgumentException.CreateFmt(
      '"%s" ist kein gültiger Formularbezeichner.',
      [AFormName]
    );
  if Trim(AAncestorName) = '' then
    raise EArgumentException.Create('Der Formular-Vorfahr darf nicht leer sein.');
  LDfmFile := ChangeFileExt(AFileName, '.dfm');
  if TFile.Exists(AFileName) or TFile.Exists(LDfmFile) then
    raise EFileAlreadyExistsException.Create(AFileName);
  ForceDirectories(TPath.GetDirectoryName(AFileName));
  LSource := ASource;
  if Trim(LSource) = '' then
    LSource := DefaultFormUnitSource(
      AUnitName,
      AFormName,
      AAncestorName
    );
  LFormSource := AFormSource;
  if Trim(LFormSource) = '' then
    LFormSource := DefaultDfmSource(AFormName, AAncestorName);
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Exit;
  AModule := LModuleServices.CreateModule(
    TCodexModuleCreator.CreateFormUnit(
      AProject,
      AFileName,
      AUnitName,
      AFormName,
      AAncestorName,
      LSource,
      LFormSource,
      AMainForm
    )
  );
  Result := Assigned(AModule);
end;

end.
