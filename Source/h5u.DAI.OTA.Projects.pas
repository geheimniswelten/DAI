unit h5u.DAI.OTA.Projects;

interface

uses
  System.JSON;

type
  TDAIProjectService = class sealed
  public
    class function CreateProject(const AName: string; const ADirectory: string; const AKind: string): TJSONObject; static;
    class function OpenProject(const AFileName: string): TJSONObject; static;
    class function SaveProject(const AProjectNameOrPath: string): TJSONObject; static;
    class function RemoveProject(const AProjectNameOrPath: string): TJSONObject; static;
    class function CreateUnit(const AProjectNameOrPath: string; const AFileName: string; const ASource: string): TJSONObject; static;
    class function CreateFormUnit(const AProjectNameOrPath: string; const AFileName: string; const AFormName: string; const AAncestorName: string): TJSONObject; static;
    class function OpenFile(const AFileName: string): TJSONObject; static;
    class function ActivateFile(const AFileName: string): TJSONObject; static;
    class function CloseFile(const AFileName: string): TJSONObject; static;
    class function RemoveFileFromProject(const AProjectNameOrPath: string; const AFileName: string): TJSONObject; static;
    class function ShowFormAsText(const AFileName: string): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  h5u.DAI.OTA.Creators,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Settings,
  h5u.DAI.Types;

function ConfirmWorkspaceChange(const ATitle: string; const AText: string): Boolean;
var
  LButton: TTaskDialogButtonItem;
  LDialog: TTaskDialog;
begin
  Result := False;
  LDialog := TTaskDialog.Create(nil);
  try
    LDialog.Caption := 'DAI';
    LDialog.Title := ATitle;
    LDialog.Text := AText;
    LDialog.MainIcon := tdiWarning;
    LDialog.CommonButtons := [];
    LDialog.Flags := [tfAllowDialogCancellation, tfUseCommandLinks];

    LButton := TTaskDialogButtonItem(LDialog.Buttons.Add);
    LButton.Caption := 'Fortfahren';
    LButton.CommandLinkHint := 'Die angeforderte Projektoperation jetzt ausführen.';
    LButton.ModalResult := mrYes;

    LButton := TTaskDialogButtonItem(LDialog.Buttons.Add);
    LButton.Caption := 'Abbrechen';
    LButton.CommandLinkHint := 'Geöffnete Projekte und die Projektgruppe unverändert lassen.';
    LButton.ModalResult := mrCancel;
    LButton.Default := True;

    Result := LDialog.Execute and (LDialog.ModalResult = mrYes);
  finally
    LDialog.Free;
  end;
end;

function OpenProjectSummary: string;
var
  LProject: IOTAProject;
begin
  Result := '';
  for LProject in TDAIOTA.Projects do
  begin
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + '• ' + TDAIOTA.ProjectFileName(LProject);
  end;
end;

function ProjectOperationNeedsConfirmation(const ATargetFileName: string): Boolean;
var
  LProject: IOTAProject;
begin
  Result := False;
  for LProject in TDAIOTA.Projects do
    if not TDAIOTA.SameFile(TDAIOTA.ProjectFileName(LProject), ATargetFileName) then
      Exit(True);
end;

function ResolveUnitFileName(const AProject: IOTAProject; const AFileName: string): string;
var
  LProjectFileName: string;
begin
  LProjectFileName := TDAIOTA.ProjectFileName(AProject);
  if TPath.IsPathRooted(AFileName) then
    Result := TDAISettings.Instance.ExpandPath(AFileName)
  else
    Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(LProjectFileName), AFileName));
  if TPath.GetExtension(Result) = '' then
    Result := Result + '.pas';
end;

class function TDAIProjectService.ActivateFile(const AFileName: string): TJSONObject;
var
  LFileName: string;
  LModule: IOTAModule;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  LModule := TDAIOTA.FindModuleByFileName(LFileName);
  if not Assigned(LModule) then
    Exit(OpenFile(LFileName));

  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LModule.ShowFileName(LFileName);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('activated', TJSONBool.Create(True));
end;

class function TDAIProjectService.CloseFile(const AFileName: string): TJSONObject;
var
  LClosed: Boolean;
  LFileName: string;
  LModule: IOTAModule;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  LModule := TDAIOTA.FindModuleByFileName(LFileName);
  if not Assigned(LModule) then
    raise EArgumentException.Create('Die Datei ist nicht in der IDE geöffnet.');

  LClosed := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LClosed := LModule.CloseModule(False);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('closed', TJSONBool.Create(LClosed));
end;

class function TDAIProjectService.CreateFormUnit(const AProjectNameOrPath: string; const AFileName: string; const AFormName: string; const AAncestorName: string): TJSONObject;
var
  LCreatedModule: IOTAModule;
  LFileName: string;
  LModuleServices: IOTAModuleServices;
  LProject: IOTAProject;
  LAncestorName: string;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LFileName := ResolveUnitFileName(LProject, AFileName);
  if TFile.Exists(LFileName) then
    raise EDAIFileAlreadyExists.CreateFmt('Die Datei existiert bereits: %s', [LFileName]);
  if not TDAIOTA.IsPathWithin(LFileName, TPath.GetDirectoryName(TDAIOTA.ProjectFileName(LProject))) then
    raise EDAIAccessDenied.Create('Neue Form-Units müssen innerhalb des Projektverzeichnisses liegen.');

  LAncestorName := Trim(AAncestorName);
  if LAncestorName = '' then
    LAncestorName := 'TForm';

  LCreatedModule := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        raise EInvalidOperation.Create('IOTAModuleServices ist nicht verfügbar.');
      LCreatedModule := LModuleServices.CreateModule(
        TDAIModuleCreator.CreateForm(LProject, LFileName, AFormName, LAncestorName, False)
      );
      if Assigned(LCreatedModule) and not LCreatedModule.Save(False, True) then
        raise EInvalidOperation.Create('Die neue Form-Unit konnte nicht gespeichert werden.');
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('created', TJSONBool.Create(Assigned(LCreatedModule)));
  Result.AddPair('form_name', AFormName);
  Result.AddPair('ancestor', LAncestorName);
end;

class function TDAIProjectService.CreateProject(const AName: string; const ADirectory: string; const AKind: string): TJSONObject;
var
  LActiveProject: IOTAProject;
  LCreatedModule: IOTAModule;
  LDirectory: string;
  LFileName: string;
  LGroup: IOTAProjectGroup;
  LKind: TDAIProjectKind;
  LModuleServices: IOTAModuleServices;
  LName: string;
  LOpenProjects: string;
begin
  LName := Trim(AName);
  if LName = '' then
    raise EArgumentException.Create('Ein Projektname ist erforderlich.');

  LDirectory := TDAISettings.Instance.ExpandPath(ADirectory);
  if LDirectory = '' then
    raise EArgumentException.Create('Ein Projektverzeichnis ist erforderlich.');

  LGroup := TDAIOTA.MainProjectGroup;
  LActiveProject := TDAIOTA.ActiveProject;
  if Assigned(LActiveProject) and not Assigned(LGroup) then
    raise EInvalidOperation.Create(
      'Es ist ein einzelnes Projekt ohne Projektgruppe geöffnet. DAI erstellt kein weiteres Projekt, weil die IDE dabei das vorhandene Projekt schließen könnte. ' +
      'Erstellen oder öffnen Sie zuerst manuell eine Projektgruppe.'
    );

  ForceDirectories(LDirectory);
  LFileName := TPath.Combine(LDirectory, LName + '.dpr');

  if TFile.Exists(LFileName) or TFile.Exists(ChangeFileExt(LFileName, '.dproj')) then
    raise EDAIFileAlreadyExists.CreateFmt('Das Projekt existiert bereits: %s', [LFileName]);

  LOpenProjects := OpenProjectSummary;
  if LOpenProjects <> '' then
    if not ConfirmWorkspaceChange(
      'Neues Projekt erstellen',
      'DAI erstellt das neue Projekt in der aktuellen Projektgruppe. Sollte die IDE die vorhandene Gruppe nicht erweitern können, könnte sie einen Wechsel anbieten.' +
      sLineBreak + sLineBreak + 'Geöffnete Projekte:' + sLineBreak + LOpenProjects
    ) then
      raise EAbort.Create('Die Projekterstellung wurde durch den Benutzer abgebrochen.');

  if SameText(AKind, 'vcl') then
    LKind := pkVCL
  else if SameText(AKind, 'console') or (Trim(AKind) = '') then
    LKind := pkConsole
  else
    raise EArgumentException.Create('project_kind muss "console" oder "vcl" sein.');

  LCreatedModule := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        raise EInvalidOperation.Create('IOTAModuleServices ist nicht verfügbar.');
      LGroup := LModuleServices.MainProjectGroup;
      LCreatedModule := LModuleServices.CreateModule(TDAIProjectCreator.Create(LGroup, LFileName, LKind));
      if Assigned(LCreatedModule) and not LCreatedModule.Save(False, True) then
        raise EInvalidOperation.Create('Das neue Projekt konnte nicht gespeichert werden.');
    end);

  Result := TJSONObject.Create;
  Result.AddPair('requested_file', LFileName);
  if Assigned(LCreatedModule) then
    Result.AddPair('project_file', LCreatedModule.FileName)
  else
    Result.AddPair('project_file', '');
  Result.AddPair('created', TJSONBool.Create(Assigned(LCreatedModule)));
end;

class function TDAIProjectService.CreateUnit(const AProjectNameOrPath: string; const AFileName: string; const ASource: string): TJSONObject;
var
  LCreatedModule: IOTAModule;
  LFileName: string;
  LModuleServices: IOTAModuleServices;
  LProject: IOTAProject;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LFileName := ResolveUnitFileName(LProject, AFileName);
  if TFile.Exists(LFileName) then
    raise EDAIFileAlreadyExists.CreateFmt('Die Datei existiert bereits: %s', [LFileName]);
  if not TDAIOTA.IsPathWithin(LFileName, TPath.GetDirectoryName(TDAIOTA.ProjectFileName(LProject))) then
    raise EDAIAccessDenied.Create('Neue Units müssen innerhalb des Projektverzeichnisses liegen.');

  LCreatedModule := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        raise EInvalidOperation.Create('IOTAModuleServices ist nicht verfügbar.');
      LCreatedModule := LModuleServices.CreateModule(TDAIModuleCreator.CreateUnit(LProject, LFileName, ASource));
      if Assigned(LCreatedModule) and not LCreatedModule.Save(False, True) then
        raise EInvalidOperation.Create('Die neue Unit konnte nicht gespeichert werden.');
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('created', TJSONBool.Create(Assigned(LCreatedModule)));
end;

class function TDAIProjectService.OpenFile(const AFileName: string): TJSONObject;
var
  LActionServices: IOTAActionServices;
  LFileName: string;
  LOpened: Boolean;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not TFile.Exists(LFileName) then
    raise EDAIFileNotFound.CreateFmt('Datei nicht gefunden: %s', [LFileName]);

  LOpened := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
        raise EInvalidOperation.Create('IOTAActionServices ist nicht verfügbar.');
      LOpened := LActionServices.OpenFile(LFileName);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('opened', TJSONBool.Create(LOpened));
end;

class function TDAIProjectService.OpenProject(const AFileName: string): TJSONObject;
var
  LActionServices: IOTAActionServices;
  LActiveProject: IOTAProject;
  LFileName: string;
  LOpened: Boolean;
  LOpenProjects: string;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not TFile.Exists(LFileName) then
    raise EDAIFileNotFound.CreateFmt('Projektdatei nicht gefunden: %s', [LFileName]);

  if Assigned(TDAIOTA.ProjectByNameOrPath(LFileName)) then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('file', LFileName);
    Result.AddPair('opened', TJSONBool.Create(True));
    Result.AddPair('already_open', TJSONBool.Create(True));
    Exit;
  end;

  LActiveProject := TDAIOTA.ActiveProject;
  if Assigned(LActiveProject) and (TDAIOTA.MainProjectGroup = nil) then
    raise EInvalidOperation.Create(
      'Es ist ein einzelnes Projekt ohne Projektgruppe geöffnet. DAI öffnet kein weiteres Projekt, weil die IDE dabei das vorhandene Projekt schließen könnte. ' +
      'Erstellen oder öffnen Sie zuerst manuell eine Projektgruppe.'
    );

  if ProjectOperationNeedsConfirmation(LFileName) then
  begin
    LOpenProjects := OpenProjectSummary;
    if not ConfirmWorkspaceChange(
      'Projekt öffnen',
      'DAI wird die folgende Projektdatei öffnen:' + sLineBreak + LFileName + sLineBreak + sLineBreak +
      'Die vorhandenen Projekte sollen geöffnet bleiben. Falls die IDE stattdessen einen Gruppenwechsel verlangt, erscheint zusätzlich deren eigener Dialog.' +
      sLineBreak + sLineBreak + 'Bereits geöffnet:' + sLineBreak + LOpenProjects
    ) then
      raise EAbort.Create('Das Öffnen des Projekts wurde durch den Benutzer abgebrochen.');
  end;

  LOpened := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
        raise EInvalidOperation.Create('IOTAActionServices ist nicht verfügbar.');
      LOpened := LActionServices.OpenFile(LFileName);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('opened', TJSONBool.Create(LOpened));
  Result.AddPair('already_open', TJSONBool.Create(False));
end;

class function TDAIProjectService.RemoveFileFromProject(const AProjectNameOrPath: string; const AFileName: string): TJSONObject;
var
  LFileName: string;
  LProject: IOTAProject;
  LRemoved: Boolean;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not TDAIOTA.ProjectContainsFile(LProject, LFileName) then
    raise EArgumentException.Create('Die Datei gehört nicht zum angegebenen Projekt.');

  LRemoved := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LProject.RemoveFile(LFileName);
      LRemoved := not TDAIOTA.ProjectContainsFile(LProject, LFileName);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
  Result.AddPair('file', LFileName);
  Result.AddPair('removed', TJSONBool.Create(LRemoved));
end;

class function TDAIProjectService.RemoveProject(const AProjectNameOrPath: string): TJSONObject;
var
  LGroup: IOTAProjectGroup;
  LProject: IOTAProject;
  LRemoved: Boolean;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LGroup := TDAIOTA.MainProjectGroup;
  if not Assigned(LGroup) then
    raise EInvalidOperation.Create('Ein einzelnes Projekt ohne Projektgruppe kann nicht aus einer Projektgruppe entfernt werden.');

  if not ConfirmWorkspaceChange(
    'Projekt aus Projektgruppe entfernen',
    'Projekt:' + sLineBreak + TDAIOTA.ProjectFileName(LProject) + sLineBreak + sLineBreak +
    'Das Projekt wird nur aus der aktuellen Projektgruppe entfernt. Dateien auf dem Datenträger werden nicht gelöscht.'
  ) then
    raise EAbort.Create('Das Entfernen des Projekts wurde durch den Benutzer abgebrochen.');

  LRemoved := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LGroup.RemoveProject(LProject);
      LRemoved := not Assigned(TDAIOTA.ProjectByNameOrPath(TDAIOTA.ProjectFileName(LProject)));
      if LRemoved then
        TDAIPermissionManager.Instance.ClearProjectSession(TDAIOTA.ProjectFileName(LProject));
    end);

  Result := TJSONObject.Create;
  Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
  Result.AddPair('removed', TJSONBool.Create(LRemoved));
end;

class function TDAIProjectService.SaveProject(const AProjectNameOrPath: string): TJSONObject;
var
  LProject: IOTAProject;
  LSaved: Boolean;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LSaved := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LSaved := LProject.Save(False, True);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
  Result.AddPair('saved', TJSONBool.Create(LSaved));
end;

class function TDAIProjectService.ShowFormAsText(const AFileName: string): TJSONObject;
var
  LActionServices: IOTAActionServices;
  LDFMFileName: string;
  LFileName: string;
  LOpened: Boolean;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if SameText(TPath.GetExtension(LFileName), '.dfm') then
    LDFMFileName := LFileName
  else
    LDFMFileName := ChangeFileExt(LFileName, '.dfm');

  if not TFile.Exists(LDFMFileName) and not TDAIOTA.IsFormLoadedForFile(LFileName) then
    raise EDAIFileNotFound.CreateFmt('DFM-Datei nicht gefunden: %s', [LDFMFileName]);

  LOpened := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
        raise EInvalidOperation.Create('IOTAActionServices ist nicht verfügbar.');
      LOpened := LActionServices.OpenFile(LDFMFileName);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LDFMFileName);
  Result.AddPair('text_mode_requested', TJSONBool.Create(LOpened));
  Result.AddPair('source_editor_available', TJSONBool.Create(Assigned(TDAIOTA.FindSourceEditor(LDFMFileName))));
end;

end.
