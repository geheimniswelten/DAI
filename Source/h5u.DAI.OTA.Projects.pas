unit h5u.DAI.OTA.Projects;

{$IF CompilerVersion >= 36.0}  // Delphi 12+
{$TEXTBLOCK CRLF}
{$IFEND}

interface

uses
  System.JSON;

type
  TDAIProjectService = class sealed
  public
    class function CreateProject(const AName: string; const ADirectory: string; const AKind: string; const ASave: Boolean = True): TJSONObject; static;
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

procedure RequireWritablePath(const AFileName: string);
var
  LExtension, LProjectSidecar: string;
begin
  TDAIOTA.RequireNoReparseWritePath(AFileName);
  if (Trim(AFileName) <> '') and TDAIOTA.IsReadOnlyReferenceFile(AFileName) then
    raise EDAIAccessDenied.CreateFmt('Referenzverzeichnisse sind schreibgeschützt. Die Projektoperation darf diese Datei nicht ändern: %s', [AFileName]);
  LExtension := TPath.GetExtension(AFileName);
  if SameText(LExtension, '.dpr') or SameText(LExtension, '.dpk') then
    LProjectSidecar := ChangeFileExt(AFileName, '.dproj')
  else if SameText(LExtension, '.dproj') then
    LProjectSidecar := AFileName
  else
    Exit;
  // A project save can write these files even when they have no ModuleFileEditor.
  TDAIOTA.RequireNoReparseWritePath(LProjectSidecar);
  TDAIOTA.RequireNoReparseWritePath(LProjectSidecar + '.local');
end;

procedure RequireWritableModuleOnMainThread(const AModule: IOTAModule; const AModifiedOnly: Boolean = False);
var
  LEditor: IOTAEditor;
  LIndex: Integer;
begin
  if not Assigned(AModule) then
    Exit;
  if not AModifiedOnly then
    RequireWritablePath(AModule.FileName);
  for LIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    LEditor := AModule.ModuleFileEditors[LIndex];
    if Assigned(LEditor) then
      if not AModifiedOnly or LEditor.Modified then
        RequireWritablePath(LEditor.FileName);
  end;
end;

procedure RequireWritableModule(const AModule: IOTAModule);
begin
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      RequireWritableModuleOnMainThread(AModule);
    end);
end;

function ConfirmWorkspaceChangeOnMainThread(const ATitle: string; const AText: string): Boolean;
var
  LButton: TTaskDialogButtonItem;
  LDialog: TTaskDialog;
begin
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

function ConfirmWorkspaceChange(const ATitle: string; const AText: string): Boolean;
var
  LConfirmed: Boolean;
begin
  LConfirmed := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LConfirmed := ConfirmWorkspaceChangeOnMainThread(ATitle, AText);
    end);
  Result := LConfirmed;
end;

function IsProjectFile(const AFileName: string): Boolean;
var
  LExtension: string;
begin
  LExtension := TPath.GetExtension(AFileName);
  Result := SameText(LExtension, '.dpr') or SameText(LExtension, '.dproj') or SameText(LExtension, '.dpk') or
    SameText(LExtension, '.cbproj') or SameText(LExtension, '.bpr') or SameText(LExtension, '.bpk') or
    SameText(LExtension, '.groupproj') or SameText(LExtension, '.bpg');
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
  if not SameText(TPath.GetExtension(Result), '.pas') then
    raise EArgumentException.Create('Neue Delphi-Units müssen die Dateiendung .pas verwenden.');
end;

class function TDAIProjectService.ActivateFile(const AFileName: string): TJSONObject;
var
  LFileName: string;
  LModule: IOTAModule;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  LModule := TDAIOTA.FindModuleByFileName(LFileName);
  if not Assigned(LModule) then
  begin
    if IsProjectFile(LFileName) then
      raise EArgumentException.Create('Projektdateien müssen mit project_open geöffnet werden.');
    Exit(OpenFile(LFileName));
  end;

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
  LGroup: IOTAProjectGroup;
  LModule: IOTAModule;
  LProject: IOTAProject;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  LModule := TDAIOTA.FindModuleByFileName(LFileName);
  if not Assigned(LModule) then
    raise EArgumentException.Create('Die Datei ist nicht in der IDE geöffnet.');
  LClosed := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if Supports(LModule, IOTAProject, LProject) or Supports(LModule, IOTAProjectGroup, LGroup) then
        raise EInvalidOperation.Create('Projektmodule und Projektgruppen können nicht mit file_close geschlossen werden.');
      // CloseModule(False) can offer to save modified associated editors.
      RequireWritableModuleOnMainThread(LModule, True);
      LClosed := LModule.CloseModule(False);
      if LClosed then
        LModule := nil;
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('closed', TJSONBool.Create(LClosed));
  Result.AddPair('closed_entire_module', TJSONBool.Create(LClosed));
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

  RequireWritableModule(LProject);
  LFileName := ResolveUnitFileName(LProject, AFileName);
  RequireWritablePath(LFileName);
  RequireWritablePath(ChangeFileExt(LFileName, '.dfm'));
  if TFile.Exists(LFileName) or TDAIOTA.IsFileOpenInEditor(LFileName) then
    raise EDAIFileAlreadyExists.CreateFmt('Die Datei existiert bereits: %s', [LFileName]);
  if TFile.Exists(ChangeFileExt(LFileName, '.dfm')) or TDAIOTA.IsFormLoadedForFile(LFileName) then
    raise EDAIFileAlreadyExists.CreateFmt('Die Formulardatei existiert bereits: %s', [ChangeFileExt(LFileName, '.dfm')]);
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
      RequireWritableModuleOnMainThread(LProject);
      RequireWritablePath(LFileName);
      RequireWritablePath(ChangeFileExt(LFileName, '.dfm'));
      LCreatedModule := LModuleServices.CreateModule(
        TDAIModuleCreator.CreateForm(LProject, LFileName, AFormName, LAncestorName, False)
      );
      if Assigned(LCreatedModule) then
      begin
        RequireWritableModuleOnMainThread(LCreatedModule);
        if not LCreatedModule.Save(False, True) then
          raise EInvalidOperation.Create('Die neue Form-Unit konnte nicht gespeichert werden.');
      end;
    end);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('created', TJSONBool.Create(Assigned(LCreatedModule)));
  Result.AddPair('form_name', AFormName);
  Result.AddPair('ancestor', LAncestorName);
end;

class function TDAIProjectService.CreateProject(const AName: string; const ADirectory: string; const AKind: string; const ASave: Boolean): TJSONObject;
var
  LActiveProject: IOTAProject;
  LCreator: TDAIProjectCreator;
  LCreatorInterface: IOTACreator;
  LCreatedModule: IOTAModule;
  LCreatedProject: IOTAProject;
  LDirectory: string;
  LFileName: string;
  LGroup: IOTAProjectGroup;
  LKind: TDAIProjectKind;
  LMainFormFileName: string;
  LMainFormName: string;
  LMainUnitFileName: string;
  LModuleServices: IOTAModuleServices;
  LName: string;
  LOpenProjects: string;
  LProjectFileName: string;
begin
  LName := Trim(AName);
  if LName = '' then
    raise EArgumentException.Create('Ein Projektname ist erforderlich.');
  if (TPath.GetFileName(LName) <> LName) or not IsValidIdent(LName) then
    raise EArgumentException.Create('Der Projektname muss ein gültiger Delphi-Bezeichner ohne Pfadangabe sein.');

  LDirectory := TDAISettings.Instance.ExpandPath(ADirectory);
  if LDirectory = '' then
    raise EArgumentException.Create('Ein Projektverzeichnis ist erforderlich.');

  LFileName := TPath.Combine(LDirectory, LName + '.dpr');
  // The target is protected even for an unsaved creator, before any confirmation or IDE mutation.
  RequireWritablePath(LFileName);
  LGroup := TDAIOTA.MainProjectGroup;
  RequireWritableModule(LGroup);
  LActiveProject := TDAIOTA.ActiveProject;
  if Assigned(LActiveProject) and not Assigned(LGroup) then
    raise EInvalidOperation.Create(
      'Es ist ein einzelnes Projekt ohne Projektgruppe geöffnet. DAI erstellt kein weiteres Projekt, weil die IDE dabei das vorhandene Projekt schließen könnte. ' +
      'Erstellen oder öffnen Sie zuerst manuell eine Projektgruppe.'
    );

  if TFile.Exists(LFileName) or TFile.Exists(ChangeFileExt(LFileName, '.dproj')) or
    TDirectory.Exists(LFileName) or TDirectory.Exists(ChangeFileExt(LFileName, '.dproj')) then
    raise EDAIFileAlreadyExists.CreateFmt('Das Projekt existiert bereits: %s', [LFileName]);

  LOpenProjects := OpenProjectSummary;
  if LOpenProjects <> '' then
    if not ConfirmWorkspaceChange(
      'Neues Projekt erstellen',
      Format(
        {$IF CompilerVersion >= 36.0}  // Delphi 12+
        '''
        DAI erstellt das neue Projekt in der aktuellen Projektgruppe. Sollte die IDE die vorhandene Gruppe nicht erweitern können, könnte sie einen Wechsel anbieten.

        Geöffnete Projekte:
        %s
        ''', [LOpenProjects]
        {$ELSE}
        'DAI erstellt das neue Projekt in der aktuellen Projektgruppe. Sollte die IDE die vorhandene Gruppe nicht erweitern können, könnte sie einen Wechsel anbieten.' + sLineBreak +
        '' + sLineBreak +
        'Geöffnete Projekte:' + sLineBreak +
        '%s'
        , [LOpenProjects]
        {$IFEND}
      )
    ) then
      raise EAbort.Create('Die Projekterstellung wurde durch den Benutzer abgebrochen.');

  if SameText(AKind, 'vcl') then
    LKind := pkVCL
  else if SameText(AKind, 'console') or (Trim(AKind) = '') then
    LKind := pkConsole
  else
    raise EArgumentException.Create('project_kind muss "console" oder "vcl" sein.');

  LCreatedModule := nil;
  LProjectFileName := '';
  LMainUnitFileName := '';
  LMainFormFileName := '';
  LMainFormName := '';
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        raise EInvalidOperation.Create('IOTAModuleServices ist nicht verfügbar.');
      if LModuleServices.MainProjectGroup <> LGroup then
        raise EInvalidOperation.Create('Die Projektgruppe wurde während der Erstellungsanfrage geändert. Wiederholen Sie die Anfrage.');
      if not Assigned(LGroup) and Assigned(LModuleServices.GetActiveProject) then
        raise EInvalidOperation.Create('Inzwischen wurde ein einzelnes Projekt geöffnet. Die Projekterstellung wird zum Schutz dieses Projekts abgebrochen.');
      if Assigned(TDAIOTA.FindModuleByFileName(LFileName)) or Assigned(TDAIOTA.FindModuleByFileName(ChangeFileExt(LFileName, '.dproj'))) then
        raise EDAIFileAlreadyExists.CreateFmt('Das Projekt ist bereits als IDE-Modul geöffnet: %s', [LFileName]);
      RequireWritablePath(LFileName);
      RequireWritableModuleOnMainThread(LGroup);
      if ASave and not ForceDirectories(LDirectory) then
        raise EInvalidOperation.Create('Das neue Projektverzeichnis konnte nicht erstellt werden.');
      LCreator := TDAIProjectCreator.Create(LGroup, LFileName, LKind, not ASave);
      LCreatorInterface := LCreator;
      RequireWritablePath(LCreator.MainUnitFileName);
      if LCreator.MainUnitFileName <> '' then
        RequireWritablePath(ChangeFileExt(LCreator.MainUnitFileName, '.dfm'));
      LCreatedModule := LModuleServices.CreateModule(LCreatorInterface);
      if not Supports(LCreatedModule, IOTAProject, LCreatedProject) then
        raise EInvalidOperation.Create('Das neue Projekt konnte nicht als IDE-Projekt erstellt werden.');
      RequireWritableModuleOnMainThread(LCreatedModule);
      // The current IDE invokes the IOTAProjectCreator50 callback. The guarded
      // call also handles a creator host that does not invoke it automatically.
      LCreator.NewDefaultProjectModule(LCreatedProject);
      if Assigned(LCreator.MainFormModule) then
      begin
        LMainUnitFileName := LCreator.MainFormModule.FileName;
        LMainFormFileName := ChangeFileExt(LMainUnitFileName, '.dfm');
        LMainFormName := LCreator.MainFormName;
        RequireWritableModuleOnMainThread(LCreator.MainFormModule);
        if ASave and not LCreator.MainFormModule.Save(False, True) then
          raise EInvalidOperation.Create('Die neue VCL-Hauptform konnte nicht gespeichert werden.');
      end;
      if ASave then
      begin
        RequireWritableModuleOnMainThread(LCreatedModule);
        if not LCreatedModule.Save(False, True) then
          raise EInvalidOperation.Create('Das neue Projekt konnte nicht gespeichert werden.');
      end;
      LProjectFileName := LCreatedModule.FileName;
    end);

  Result := TJSONObject.Create;
  Result.AddPair('requested_file', LFileName);
  Result.AddPair('project_file', LProjectFileName);
  Result.AddPair('created', TJSONBool.Create(Assigned(LCreatedModule)));
  Result.AddPair('saved', TJSONBool.Create(ASave));
  Result.AddPair('unnamed', TJSONBool.Create(not ASave));
  if LMainUnitFileName <> '' then
  begin
    Result.AddPair('main_unit_file', LMainUnitFileName);
    Result.AddPair('main_form_file', LMainFormFileName);
    Result.AddPair('main_form_name', LMainFormName);
  end;
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

  RequireWritableModule(LProject);
  LFileName := ResolveUnitFileName(LProject, AFileName);
  RequireWritablePath(LFileName);
  if TFile.Exists(LFileName) or TDAIOTA.IsFileOpenInEditor(LFileName) then
    raise EDAIFileAlreadyExists.CreateFmt('Die Datei existiert bereits: %s', [LFileName]);
  if not TDAIOTA.IsPathWithin(LFileName, TPath.GetDirectoryName(TDAIOTA.ProjectFileName(LProject))) then
    raise EDAIAccessDenied.Create('Neue Units müssen innerhalb des Projektverzeichnisses liegen.');

  LCreatedModule := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        raise EInvalidOperation.Create('IOTAModuleServices ist nicht verfügbar.');
      RequireWritableModuleOnMainThread(LProject);
      RequireWritablePath(LFileName);
      LCreatedModule := LModuleServices.CreateModule(TDAIModuleCreator.CreateUnit(LProject, LFileName, ASource));
      if Assigned(LCreatedModule) then
      begin
        RequireWritableModuleOnMainThread(LCreatedModule);
        if not LCreatedModule.Save(False, True) then
          raise EInvalidOperation.Create('Die neue Unit konnte nicht gespeichert werden.');
      end;
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
  if IsProjectFile(LFileName) then
    raise EArgumentException.Create('Projektdateien müssen mit project_open geöffnet werden.');
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
      Format(
        {$IF CompilerVersion >= 36.0}  // Delphi 12+
        '''
        DAI wird die folgende Projektdatei öffnen:
        %s

        Die vorhandenen Projekte sollen geöffnet bleiben. Falls die IDE stattdessen einen Gruppenwechsel verlangt, erscheint zusätzlich deren eigener Dialog.

        Bereits geöffnet:
        %s
        ''', [LFileName, LOpenProjects]
        {$ELSE}
        'DAI wird die folgende Projektdatei öffnen:' + sLineBreak +
        '%s' + sLineBreak +
        '' + sLineBreak +
        'Die vorhandenen Projekte sollen geöffnet bleiben. Falls die IDE stattdessen einen Gruppenwechsel verlangt, erscheint zusätzlich deren eigener Dialog.' + sLineBreak +
        '' + sLineBreak +
        'Bereits geöffnet:' + sLineBreak +
        '%s'
        , [LFileName, LOpenProjects]
        {$IFEND}
      )
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

  RequireWritableModule(LProject);
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not TDAIOTA.ProjectContainsFile(LProject, LFileName) then
    raise EArgumentException.Create('Die Datei gehört nicht zum angegebenen Projekt.');

  LRemoved := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      RequireWritableModuleOnMainThread(LProject);
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
  LProjectFileName: string;
  LRemoved: Boolean;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
  LProjectFileName := TDAIOTA.ProjectFileName(LProject);

  LGroup := TDAIOTA.MainProjectGroup;
  if not Assigned(LGroup) then
    raise EInvalidOperation.Create('Ein einzelnes Projekt ohne Projektgruppe kann nicht aus einer Projektgruppe entfernt werden.');
  RequireWritableModule(LGroup);
  RequireWritableModule(LProject);

  if not ConfirmWorkspaceChange(
    'Projekt aus Projektgruppe entfernen',
    Format(
      {$IF CompilerVersion >= 36.0}  // Delphi 12+
      '''
      Projekt:
      %s

      Das Projekt wird nur aus der aktuellen Projektgruppe entfernt. Dateien auf dem Datenträger werden nicht gelöscht.
      ''', [LProjectFileName]
      {$ELSE}
      'Projekt:' + sLineBreak +
      '%s' + sLineBreak +
      '' + sLineBreak +
      'Das Projekt wird nur aus der aktuellen Projektgruppe entfernt. Dateien auf dem Datenträger werden nicht gelöscht.'
      , [LProjectFileName]
      {$IFEND}
    )
  ) then
    raise EAbort.Create('Das Entfernen des Projekts wurde durch den Benutzer abgebrochen.');

  LRemoved := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      RequireWritableModuleOnMainThread(LGroup);
      RequireWritableModuleOnMainThread(LProject);
      LGroup.RemoveProject(LProject);
      LRemoved := not Assigned(TDAIOTA.ProjectByNameOrPath(LProjectFileName));
      if LRemoved then
        TDAIPermissionManager.Instance.ClearProjectSession(LProjectFileName);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('project', LProjectFileName);
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
      RequireWritableModuleOnMainThread(LProject);
      LSaved := LProject.Save(False, True);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
  Result.AddPair('saved', TJSONBool.Create(LSaved));
end;

class function TDAIProjectService.ShowFormAsText(const AFileName: string): TJSONObject;
var
  LFormFileName: string;
  LFileName: string;
  LSourceEditor: IOTASourceEditor;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  LFormFileName := TDAIOTA.FormFileName(LFileName);
  if LFormFileName = '' then
    raise EDAIFileNotFound.CreateFmt('Formulardatei nicht gefunden: %s', [LFileName]);
  LSourceEditor := TDAIOTA.EnsureFormTextEditor(LFormFileName);
  if not Assigned(LSourceEditor) then
    raise EInvalidOperation.CreateFmt('Der native IDE-Textmodus für dieses Formular ist nicht verfügbar: %s', [LFormFileName]);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFormFileName);
  Result.AddPair('text_mode_requested', TJSONBool.Create(True));
  Result.AddPair('source_editor_available', TJSONBool.Create(True));
end;

end.
