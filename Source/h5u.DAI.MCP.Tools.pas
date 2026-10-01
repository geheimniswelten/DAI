unit h5u.DAI.MCP.Tools;

interface

uses
  System.JSON,
  h5u.DAI.Types;

type
  TDAIMCPTools = class sealed
  public
    class function ListTools: TJSONArray; static;
    class function CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.Clients.Registration,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Log,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.CodeInsight,
  h5u.DAI.OTA.Debugger,
  h5u.DAI.OTA.Designer,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Projects,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Settings,
  h5u.DAI.UI;

function JsonObjectFromText(const AText: string): TJSONObject;
var
  LValue: TJSONValue;
begin
  LValue := TJSONObject.ParseJSONValue(AText);
  if not (LValue is TJSONObject) then
  begin
    LValue.Free;
    raise EConvertError.Create('Ungültiges internes JSON-Schema.');
  end;
  Result := TJSONObject(LValue);
end;

procedure AddTool(const ATools: TJSONArray; const AName: string; const ADescription: string; const ASchema: string; const AReadOnly: Boolean);
var
  LAnnotations: TJSONObject;
  LTool: TJSONObject;
begin
  LTool := TJSONObject.Create;
  LTool.AddPair('name', AName);
  LTool.AddPair('description', ADescription);
  LTool.AddPair('inputSchema', JsonObjectFromText(ASchema));
  LAnnotations := TJSONObject.Create;
  LAnnotations.AddPair('readOnlyHint', TJSONBool.Create(AReadOnly));
  LTool.AddPair('annotations', LAnnotations);
  ATools.AddElement(LTool);
end;

function ArgumentString(const AArguments: TJSONObject; const AName: string; const ADefault: string = ''): string;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AArguments) then
    Exit;
  LValue := AArguments.GetValue(AName);
  if LValue is TJSONString then
    Result := TJSONString(LValue).Value;
end;

function ArgumentBoolean(const AArguments: TJSONObject; const AName: string; const ADefault: Boolean): Boolean;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AArguments) then
    Exit;
  LValue := AArguments.GetValue(AName);
  if not Assigned(LValue) then
    Exit;
  if SameText(LValue.Value, 'true') then
    Result := True
  else if SameText(LValue.Value, 'false') then
    Result := False;
end;

function ArgumentInteger(const AArguments: TJSONObject; const AName: string; const ADefault: Integer): Integer;
var
  LNumber: Double;
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AArguments) then
    Exit;
  LValue := AArguments.GetValue(AName);
  if Assigned(LValue) and TryStrToFloat(LValue.Value, LNumber, TFormatSettings.Invariant) then
    Result := Trunc(LNumber);
end;

function ArgumentStringArray(const AArguments: TJSONObject; const AName: string): TArray<string>;
var
  LArray: TJSONArray;
  LIndex: Integer;
begin
  Result := [];
  if not Assigned(AArguments) then
    Exit;
  LArray := AArguments.GetValue<TJSONArray>(AName);
  if not Assigned(LArray) then
    Exit;

  SetLength(Result, LArray.Count);
  for LIndex := 0 to LArray.Count - 1 do
    Result[LIndex] := LArray.Items[LIndex].Value;
end;

procedure RequirePermission(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext);
begin
  if not TDAIPermissionManager.Instance.Authorize(ACategory, AOperation, AResource, AContext) then
    raise EAbort.Create('Die Operation wurde durch die DAI-Berechtigungsrichtlinie verweigert.');
end;

procedure EnsureDebuggerIdle;
var
  LDebugger: IOTADebuggerServices;
begin
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) and Assigned(LDebugger.CurrentProcess) and
         not (LDebugger.CurrentProcess.ProcessState in [psNothing, psTerminated, psNoProcess]) then
        raise EInvalidOperation.Create('Ein Debuggerprozess ist bereits aktiv. Verwenden Sie debugger_control oder project_stop.');
    end);
end;

function ToolStatus(const AContext: TDAIRequestContext): TJSONObject;
var
  LPermissions: TJSONObject;
  LCategory: TDAIPermissionCategory;
begin
  LPermissions := TJSONObject.Create;
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    LPermissions.AddPair(
      DAIPermissionCategoryKey(LCategory),
      DAIPermissionLevelKey(TDAIPermissionManager.Instance.GetEffectiveLevel(LCategory, AContext))
    );

  Result := TJSONObject.Create;
  Result.AddPair('name', 'DAI');
  Result.AddPair('display_name', 'Delphi AI');
  Result.AddPair('enabled', TJSONBool.Create(TDAISettings.Instance.Enabled));
  Result.AddPair('port', TJSONNumber.Create(TDAISettings.Instance.Port));
  Result.AddPair('active_project', TDAIOTA.ActiveProjectFileName);
  Result.AddPair('thread_id', AContext.ThreadId);
  Result.AddPair('transport_session_id', AContext.TransportSessionId);
  Result.AddPair('permissions', LPermissions);
end;

function ContextForArguments(const AArguments: TJSONObject; const AContext: TDAIRequestContext): TDAIRequestContext;
var
  LFileName: string;
  LProject: IOTAProject;
  LProjectName: string;
  LRoot: string;
  LBestLength: Integer;
begin
  Result := AContext;
  LProjectName := ArgumentString(AArguments, 'project');
  if LProjectName <> '' then
  begin
    LProject := TDAIOTA.ProjectByNameOrPath(LProjectName);
    if Assigned(LProject) then
      Result.ProjectKey := TDAIOTA.ProjectFileName(LProject);
    Exit;
  end;
  LFileName := ArgumentString(AArguments, 'file');
  if LFileName = '' then
    LFileName := ArgumentString(AArguments, 'directory');
  if LFileName = '' then
    Exit;
  LFileName := TDAISettings.Instance.ExpandPath(LFileName);
  LProject := TDAIOTA.ProjectByNameOrPath('');
  if Assigned(LProject) and TDAIOTA.ProjectContainsFile(LProject, LFileName) then
  begin
    Result.ProjectKey := TDAIOTA.ProjectFileName(LProject);
    Exit;
  end;
  LBestLength := 0;
  for LProject in TDAIOTA.Projects do
  begin
    if TDAIOTA.ProjectContainsFile(LProject, LFileName) then
    begin
      Result.ProjectKey := TDAIOTA.ProjectFileName(LProject);
      Exit;
    end;
    LRoot := TPath.GetDirectoryName(TDAIOTA.ProjectFileName(LProject));
    if (Length(LRoot) > LBestLength) and (TDAIOTA.IsPathWithin(LFileName, LRoot) or TDAIOTA.SameFile(LFileName, LRoot)) then
    begin
      LBestLength := Length(LRoot);
      Result.ProjectKey := TDAIOTA.ProjectFileName(LProject);
    end;
  end;
end;

class function TDAIMCPTools.CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
var
  LBuildFirst: Boolean;
  LCompileResult: TJSONObject;
  LContext: TDAIRequestContext;
  LExpandedFileName: string;
  LFileName: string;
  LProjectObject: IOTAProject;
  LProject: string;
  LUsedEditorBuffer: Boolean;
  LWithDebugger: Boolean;
begin
  LContext := ContextForArguments(AArguments, AContext);
  TDAILog.Access('MCP tools/call: ' + AName);

  if SameText(AName, 'ide_status') then
  begin
    RequirePermission(pcReadAccess, 'Status der Delphi-IDE lesen', '', LContext);
    Exit(ToolStatus(LContext));
  end;

  if SameText(AName, 'open_files_list') then
  begin
    RequirePermission(pcReadAccess, 'Liste der aktuell geöffneten Dateien lesen', '', LContext);
    Result := TJSONObject.Create;
    Result.AddPair('files', TDAIFileService.OpenFiles);
    Exit;
  end;

  if SameText(AName, 'projects_list') then
  begin
    RequirePermission(pcReadAccess, 'Projekte und Projektpfade der aktuellen Projektgruppe lesen', '', LContext);
    Result := TJSONObject.Create;
    Result.AddPair('projects', TDAIFileService.Projects);
    Exit;
  end;

  if SameText(AName, 'project_files_list') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcReadAccess, 'Dateien eines Projekts lesen', LProject, LContext);
    Result := TJSONObject.Create;
    Result.AddPair('files', TDAIFileService.ProjectFiles(LProject));
    Exit;
  end;

  if SameText(AName, 'project_directory_files_list') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcReadAccess, 'Dateien im Projektverzeichnis auflisten', LProject, LContext);
    LProjectObject := TDAIOTA.ProjectByNameOrPath(LProject);
    if not Assigned(LProjectObject) then
      raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
    LFileName := LProjectObject.FileName;
    Result := TJSONObject.Create;
    Result.AddPair(
      'files',
      TDAIFileService.DirectoryFiles(
        TPath.GetDirectoryName(LFileName),
        ArgumentString(AArguments, 'search_pattern', '*'),
        ArgumentBoolean(AArguments, 'recursive', True),
        ArgumentInteger(AArguments, 'maximum_count', 5000)
      )
    );
    Exit;
  end;

  if SameText(AName, 'directory_files_list') then
  begin
    LFileName := ArgumentString(AArguments, 'directory');
    RequirePermission(pcReadAccess, 'Freigegebenes Verzeichnis auflisten', LFileName, LContext);
    Result := TJSONObject.Create;
    Result.AddPair(
      'files',
      TDAIFileService.DirectoryFiles(
        LFileName,
        ArgumentString(AArguments, 'search_pattern', '*'),
        ArgumentBoolean(AArguments, 'recursive', True),
        ArgumentInteger(AArguments, 'maximum_count', 5000)
      )
    );
    Exit;
  end;

  if SameText(AName, 'reference_roots_list') then
  begin
    RequirePermission(pcReadAccess, 'Delphi-, Demo-, GetIt- und zusätzliche Referenzpfade lesen', '', LContext);
    Result := TJSONObject.Create;
    Result.AddPair('roots', TDAIFileService.ReferenceRoots);
    Exit;
  end;

  if SameText(AName, 'reference_files_list') then
  begin
    LFileName := ArgumentString(AArguments, 'directory');
    RequirePermission(pcReadAccess, 'Dateien eines schreibgeschützten Referenzpfads auflisten', LFileName, LContext);
    Result := TJSONObject.Create;
    Result.AddPair(
      'files',
      TDAIFileService.DirectoryFiles(
        LFileName,
        ArgumentString(AArguments, 'search_pattern', '*'),
        ArgumentBoolean(AArguments, 'recursive', True),
        ArgumentInteger(AArguments, 'maximum_count', 5000)
      )
    );
    Exit;
  end;

  if SameText(AName, 'file_read') or SameText(AName, 'reference_file_read') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcReadAccess, 'Dateiinhalt lesen', LFileName, LContext);
    Exit(TDAIFileService.ReadFile(LFileName, ArgumentInteger(AArguments, 'maximum_characters', 0)));
  end;

  if SameText(AName, 'code_insight_status') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcReadAccess, 'Status der IDE-Code-Insight-Provider lesen', LFileName, LContext);
    Exit(TDAICodeInsightService.Status(LFileName));
  end;

  if SameText(AName, 'code_definition') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcReadAccess, 'Semantische Definition über IDE Code Insight ermitteln', LFileName, LContext);
    Exit(
      TDAICodeInsightService.Definition(
        LFileName,
        ArgumentInteger(AArguments, 'line', 0),
        ArgumentInteger(AArguments, 'character', -1),
        ArgumentInteger(AArguments, 'timeout_ms', 10000)
      )
    );
  end;

  if SameText(AName, 'code_hover') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcReadAccess, 'Help Insight für eine Quelltextposition lesen', LFileName, LContext);
    Exit(
      TDAICodeInsightService.Hover(
        LFileName,
        ArgumentInteger(AArguments, 'line', 0),
        ArgumentInteger(AArguments, 'column', 0),
        ArgumentInteger(AArguments, 'timeout_ms', 10000)
      )
    );
  end;

  if SameText(AName, 'file_diagnostics') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcReadAccess, 'Error-Insight-Diagnosen einer IDE-Datei lesen', LFileName, LContext);
    Exit(TDAICodeInsightService.Diagnostics(LFileName));
  end;

  if SameText(AName, 'project_context') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcReadAccess, 'Aktiven Projekt- und Compilerkontext lesen', LProject, LContext);
    Exit(
      TDAICodeInsightService.ProjectContext(
        LProject,
        ArgumentBoolean(AArguments, 'include_files', True),
        ArgumentInteger(AArguments, 'maximum_files', 5000),
        ArgumentBoolean(AArguments, 'include_compiler_options', True)
      )
    );
  end;

  if SameText(AName, 'file_write') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    LExpandedFileName := TDAISettings.Instance.ExpandPath(LFileName);
    if SameText(TPath.GetExtension(LExpandedFileName), '.dfm') or SameText(TPath.GetExtension(LExpandedFileName), '.fmx') or
       TDAIOTA.IsFileOpenInEditor(LExpandedFileName) or
       TDAIOTA.IsFormLoadedForFile(LExpandedFileName) then
      RequirePermission(pcEditInsideIDE, 'Datei im Editorpuffer bearbeiten', LFileName, LContext)
    else
      RequirePermission(pcEditOutsideIDE, 'Datei auf dem Datenträger bearbeiten', LFileName, LContext);

    Exit(
      TDAIFileService.WriteFile(
        LFileName,
        ArgumentString(AArguments, 'content'),
        ArgumentString(AArguments, 'expected_sha256'),
        ArgumentBoolean(AArguments, 'save', False),
        LUsedEditorBuffer
      )
    );
  end;

  if SameText(AName, 'project_create') then
  begin
    RequirePermission(pcEditInsideIDE, 'Projekt in der aktuellen Projektgruppe erstellen', ArgumentString(AArguments, 'directory'), LContext);
    Exit(
      TDAIProjectService.CreateProject(
        ArgumentString(AArguments, 'name'),
        ArgumentString(AArguments, 'directory'),
        ArgumentString(AArguments, 'project_kind', 'console')
      )
    );
  end;

  if SameText(AName, 'project_open') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Projekt öffnen', LFileName, LContext);
    Exit(TDAIProjectService.OpenProject(LFileName));
  end;

  if SameText(AName, 'project_save') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcEditInsideIDE, 'Projekt speichern', LProject, LContext);
    Exit(TDAIProjectService.SaveProject(LProject));
  end;

  if SameText(AName, 'project_remove') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcEditInsideIDE, 'Projekt aus der aktuellen Projektgruppe entfernen', LProject, LContext);
    Exit(TDAIProjectService.RemoveProject(LProject));
  end;

  if SameText(AName, 'unit_create') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcEditInsideIDE, 'Unit erstellen und zum Projekt hinzufügen', ArgumentString(AArguments, 'file'), LContext);
    Exit(
      TDAIProjectService.CreateUnit(
        LProject,
        ArgumentString(AArguments, 'file'),
        ArgumentString(AArguments, 'source')
      )
    );
  end;

  if SameText(AName, 'form_unit_create') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcEditInsideIDE, 'Form-Unit erstellen und zum Projekt hinzufügen', ArgumentString(AArguments, 'file'), LContext);
    Exit(
      TDAIProjectService.CreateFormUnit(
        LProject,
        ArgumentString(AArguments, 'file'),
        ArgumentString(AArguments, 'form_name', 'Form1'),
        ArgumentString(AArguments, 'ancestor_name', 'TForm')
      )
    );
  end;

  if SameText(AName, 'file_open') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Datei in der IDE öffnen', LFileName, LContext);
    Exit(TDAIProjectService.OpenFile(LFileName));
  end;

  if SameText(AName, 'file_activate') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Datei in der IDE aktivieren', LFileName, LContext);
    Exit(TDAIProjectService.ActivateFile(LFileName));
  end;

  if SameText(AName, 'file_close') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Datei in der IDE schließen', LFileName, LContext);
    Exit(TDAIProjectService.CloseFile(LFileName));
  end;

  if SameText(AName, 'project_file_remove') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Datei aus dem Projekt entfernen', LFileName, LContext);
    Exit(TDAIProjectService.RemoveFileFromProject(ArgumentString(AArguments, 'project'), LFileName));
  end;

  if SameText(AName, 'form_show_as_text') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Formular in den DFM-Textmodus umschalten', LFileName, LContext);
    Exit(TDAIProjectService.ShowFormAsText(LFileName));
  end;

  if SameText(AName, 'form_designer_inspect') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcReadAccess, 'Formdesigner und veröffentlichte Eigenschaften lesen', LFileName, LContext);
    Exit(TDAIDesignerService.InspectForm(LFileName));
  end;

  if SameText(AName, 'form_show_designer') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Formdesigner in der IDE anzeigen', LFileName, LContext);
    Exit(TDAIDesignerService.ShowDesigner(LFileName));
  end;

  if SameText(AName, 'debugger_status') then
  begin
    RequirePermission(pcReadAccess, 'Debugger-, Prozess- und Threadstatus lesen', '', LContext);
    Exit(TDAIDebuggerService.Status);
  end;

  if SameText(AName, 'breakpoints_list') then
  begin
    RequirePermission(pcReadAccess, 'Quellhaltepunkte lesen', '', LContext);
    Result := TJSONObject.Create;
    Result.AddPair('breakpoints', TDAIDebuggerService.Breakpoints);
    Exit;
  end;

  if SameText(AName, 'breakpoint_set') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Quellhaltepunkt erstellen oder ändern', LFileName, LContext);
    Exit(TDAIDebuggerService.SetBreakpoint(LFileName, ArgumentInteger(AArguments, 'line', 0),
      ArgumentBoolean(AArguments, 'enabled', True), ArgumentString(AArguments, 'condition'), ArgumentInteger(AArguments, 'pass_count', 0)));
  end;

  if SameText(AName, 'breakpoint_remove') then
  begin
    LFileName := ArgumentString(AArguments, 'file');
    RequirePermission(pcEditInsideIDE, 'Quellhaltepunkt entfernen', LFileName, LContext);
    Exit(TDAIDebuggerService.RemoveBreakpoint(LFileName, ArgumentInteger(AArguments, 'line', 0)));
  end;

  if SameText(AName, 'debugger_control') then
  begin
    RequirePermission(pcExecute, 'Debugger steuern: ' + ArgumentString(AArguments, 'action'), '', LContext);
    Exit(TDAIDebuggerService.Control(ArgumentString(AArguments, 'action')));
  end;

  if SameText(AName, 'clients_registration_status') then
  begin
    RequirePermission(pcReadAccess, 'MCP-Registrierung der KI-Clients prüfen', '', LContext);
    Exit(TDAIClientRegistration.Status(ArgumentString(AArguments, 'client')));
  end;

  if SameText(AName, 'clients_register') then
  begin
    RequirePermission(pcEditOutsideIDE, 'DAI beim KI-Client registrieren: ' + ArgumentString(AArguments, 'client', 'all'),
      TDAICodexRegistration.UserProfileDirectory, LContext);
    Exit(TDAIClientRegistration.RegisterFiles(ArgumentString(AArguments, 'client')));
  end;

  if SameText(AName, 'clients_unregister') then
  begin
    RequirePermission(pcEditOutsideIDE, 'DAI beim KI-Client deregistrieren: ' + ArgumentString(AArguments, 'client', 'all'),
      TDAICodexRegistration.UserProfileDirectory, LContext);
    Exit(TDAIClientRegistration.UnregisterFiles(ArgumentString(AArguments, 'client')));
  end;

  if SameText(AName, 'project_compile') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    RequirePermission(pcCompile, 'Projekt kompilieren', LProject, LContext);
    Exit(
      TDAIBuildService.CompileProject(
        LProject,
        ArgumentBoolean(AArguments, 'full_build', False),
        ArgumentBoolean(AArguments, 'clear_messages', True)
      )
    );
  end;

  if SameText(AName, 'project_group_compile') then
  begin
    for LProjectObject in TDAIOTA.Projects do
    begin
      LContext.ProjectKey := TDAIOTA.ProjectFileName(LProjectObject);
      RequirePermission(pcCompile, 'Projekt der Projektgruppe kompilieren', LContext.ProjectKey, LContext);
    end;
    Exit(
      TDAIBuildService.CompileProjectGroup(
        ArgumentBoolean(AArguments, 'full_build', False),
        ArgumentBoolean(AArguments, 'clear_messages', True)
      )
    );
  end;

  if SameText(AName, 'project_run') then
  begin
    LProject := ArgumentString(AArguments, 'project');
    LBuildFirst := ArgumentBoolean(AArguments, 'build_first', True);
    LWithDebugger := ArgumentBoolean(AArguments, 'debugger', True);
    RequirePermission(pcExecute, 'Projekt starten', LProject, LContext);
    if LWithDebugger or LBuildFirst then
      EnsureDebuggerIdle;
    if LBuildFirst then
    begin
      RequirePermission(pcCompile, 'Projekt vor dem Start kompilieren', LProject, LContext);
      LCompileResult := TDAIBuildService.CompileProject(LProject, False, True);
      try
        if not LCompileResult.GetValue<Boolean>('succeeded') then
          raise EInvalidOperation.Create('Das Projekt wurde nicht gestartet, weil die Kompilierung fehlgeschlagen ist.');
      finally
        LCompileResult.Free;
      end;
    end;
    Exit(TDAIBuildService.RunProject(LProject, LWithDebugger));
  end;

  if SameText(AName, 'project_stop') then
  begin
    LWithDebugger := ArgumentBoolean(AArguments, 'debugger', True);
    RequirePermission(pcExecute, 'Laufendes Projekt stoppen', '', LContext);
    Exit(TDAIBuildService.StopProject(ArgumentString(AArguments, 'project'), LWithDebugger));
  end;

  if SameText(AName, 'ui_message_box') then
  begin
    RequirePermission(pcEditInsideIDE, 'MessageBox in der Delphi-IDE anzeigen', ArgumentString(AArguments, 'title', 'DAI'), LContext);
    Exit(
      TDAIUIService.ShowMessage(
        ArgumentString(AArguments, 'title', 'DAI'),
        ArgumentString(AArguments, 'message'),
        ArgumentString(AArguments, 'kind', 'information')
      )
    );
  end;

  if SameText(AName, 'ui_input_box') then
  begin
    RequirePermission(pcEditInsideIDE, 'InputBox in der Delphi-IDE anzeigen', ArgumentString(AArguments, 'title', 'DAI'), LContext);
    Exit(
      TDAIUIService.AskInput(
        ArgumentString(AArguments, 'title', 'DAI'),
        ArgumentString(AArguments, 'prompt'),
        ArgumentString(AArguments, 'default_value')
      )
    );
  end;

  if SameText(AName, 'ui_balloon_hint') then
  begin
    RequirePermission(pcEditInsideIDE, 'BalloonHint in der Delphi-IDE anzeigen', ArgumentString(AArguments, 'title', 'DAI'), LContext);
    Exit(
      TDAIUIService.ShowBalloon(
        ArgumentString(AArguments, 'title', 'DAI'),
        ArgumentString(AArguments, 'message'),
        ArgumentInteger(AArguments, 'timeout_ms', 5000)
      )
    );
  end;

  if SameText(AName, 'codex_registration_status') then
  begin
    RequirePermission(pcReadAccess, 'Status der Codex- und Skill-Registrierung lesen', '', LContext);
    Exit(TDAICodexRegistration.Status);
  end;

  if SameText(AName, 'codex_register') then
  begin
    RequirePermission(pcEditOutsideIDE, 'DAI in .codex und .agents registrieren', TDAICodexRegistration.UserProfileDirectory, LContext);
    TDAICodexRegistration.RegisterFiles;
    Exit(TDAICodexRegistration.Status);
  end;

  if SameText(AName, 'codex_unregister') then
  begin
    RequirePermission(pcEditOutsideIDE, 'DAI aus .codex und .agents deregistrieren', TDAICodexRegistration.UserProfileDirectory, LContext);
    TDAICodexRegistration.UnregisterFiles;
    Exit(TDAICodexRegistration.Status);
  end;

  if SameText(AName, 'msbuild_execute') then
  begin
    RequirePermission(pcCompile, 'MSBuild.exe direkt ausführen', ArgumentString(AArguments, 'working_directory'), LContext);
    Exit(
      TDAIBuildService.ExecuteMSBuild(
        ArgumentString(AArguments, 'executable'),
        ArgumentStringArray(AArguments, 'arguments'),
        ArgumentString(AArguments, 'working_directory'),
        Cardinal(EnsureRange(ArgumentInteger(AArguments, 'timeout_ms', 300000), 1000, 1800000))
      )
    );
  end;

  if SameText(AName, 'dcc32_execute') then
  begin
    RequirePermission(pcCompile, 'DCC32.exe direkt ausführen', ArgumentString(AArguments, 'working_directory'), LContext);
    Exit(
      TDAIBuildService.ExecuteDCC32(
        ArgumentStringArray(AArguments, 'arguments'),
        ArgumentString(AArguments, 'working_directory'),
        Cardinal(EnsureRange(ArgumentInteger(AArguments, 'timeout_ms', 300000), 1000, 1800000))
      )
    );
  end;

  raise EArgumentException.CreateFmt('Unbekanntes MCP-Werkzeug: %s', [AName]);
end;

class function TDAIMCPTools.ListTools: TJSONArray;
begin
  Result := TJSONArray.Create;

  AddTool(Result, 'ide_status', 'Liefert Server-, IDE-, Projekt-, Chat- und Berechtigungsstatus.', '{"type":"object","additionalProperties":false}', True);
  AddTool(Result, 'open_files_list', 'Listet aktuell in der IDE geöffnete Dateien.', '{"type":"object","additionalProperties":false}', True);
  AddTool(Result, 'projects_list', 'Listet Projekte und Projektpfade der aktuellen Gruppe oder das einzelne Projekt.', '{"type":"object","additionalProperties":false}', True);

  AddTool(
    Result,
    'project_files_list',
    'Listet Units und weitere Dateien eines geöffneten Projekts.',
    '{"type":"object","properties":{"project":{"type":"string"}},"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'project_directory_files_list',
    'Listet Dateien im Verzeichnis eines geöffneten Projekts.',
    '{"type":"object","properties":{"project":{"type":"string"},"search_pattern":{"type":"string"},"recursive":{"type":"boolean"},' +
    '"maximum_count":{"type":"integer","minimum":1,"maximum":50000}},"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'directory_files_list',
    'Listet Dateien in einem Workspace- oder freigegebenen Referenzverzeichnis.',
    '{"type":"object","properties":{"directory":{"type":"string"},"search_pattern":{"type":"string"},"recursive":{"type":"boolean"},' +
    '"maximum_count":{"type":"integer","minimum":1,"maximum":50000}},"required":["directory"],"additionalProperties":false}',
    True
  );
  AddTool(Result, 'reference_roots_list', 'Listet schreibgeschützte Delphi-, Demo-, GetIt- und zusätzliche Referenzpfade.',
    '{"type":"object","additionalProperties":false}', True);
  AddTool(
    Result,
    'reference_files_list',
    'Listet Dateien in einem schreibgeschützten Referenzverzeichnis.',
    '{"type":"object","properties":{"directory":{"type":"string"},"search_pattern":{"type":"string"},"recursive":{"type":"boolean"},' +
    '"maximum_count":{"type":"integer","minimum":1,"maximum":50000}},"required":["directory"],"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'file_read',
    'Liest den aktuellen Editorpuffer oder ersatzweise die Datei vom Datenträger.',
    '{"type":"object","properties":{"file":{"type":"string"},"maximum_characters":{"type":"integer","minimum":0}},"required":["file"],"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'reference_file_read',
    'Liest eine Datei aus den schreibgeschützten Referenzpfaden.',
    '{"type":"object","properties":{"file":{"type":"string"},"maximum_characters":{"type":"integer","minimum":0}},"required":["file"],"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'code_insight_status',
    'Listet die IDE-Code-Insight-Provider und deren semantische Fähigkeiten für eine optionale Datei.',
    '{"type":"object","properties":{"file":{"type":"string"}},"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'code_definition',
    'Ermittelt die Definition eines Symbols über den bereits von Delphi verwendeten Code-Insight-/LSP-Provider.',
    '{"type":"object","properties":{"file":{"type":"string"},"line":{"type":"integer","minimum":1},' +
    '"character":{"type":"integer","minimum":0},"timeout_ms":{"type":"integer","minimum":100,"maximum":60000}},' +
    '"required":["file","line","character"],"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'code_hover',
    'Liest Help Insight an einer Editorposition; die Datei muss in einem Code-Editor geöffnet sein.',
    '{"type":"object","properties":{"file":{"type":"string"},"line":{"type":"integer","minimum":1},' +
    '"column":{"type":"integer","minimum":1},"timeout_ms":{"type":"integer","minimum":100,"maximum":60000}},' +
    '"required":["file","line","column"],"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'file_diagnostics',
    'Liest die von Delphi Error Insight gemeldeten Fehler, Warnungen und Hinweise einer geladenen Datei.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'project_context',
    'Liest den aktiven Delphi-Projekt-, Plattform-, Build-Konfigurations- und Compilerkontext.',
    '{"type":"object","properties":{"project":{"type":"string"},"include_files":{"type":"boolean"},' +
    '"maximum_files":{"type":"integer","minimum":1,"maximum":50000},"include_compiler_options":{"type":"boolean"}},' +
    '"additionalProperties":false}',
    True
  );
  AddTool(
    Result,
    'file_write',
    'Ersetzt Editorpuffer; geschlossene Workspace-Dateien benötigen save=true. DFM/FMX werden ausschließlich über IDE-Textpuffer geschrieben.',
    '{"type":"object","properties":{"file":{"type":"string"},"content":{"type":"string"},"expected_sha256":{"type":"string"},' +
    '"save":{"type":"boolean"}},"required":["file","content"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_create',
    'Erstellt ein Console- oder VCL-Projekt in der aktuellen Projektgruppe.',
    '{"type":"object","properties":{"name":{"type":"string"},"directory":{"type":"string"},"project_kind":{"type":"string","enum":["console","vcl"]}},' +
    '"required":["name","directory"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_open',
    'Öffnet ein Projekt. Vorhandene Projekte werden niemals ohne zusätzliche Rückfrage ersetzt oder geschlossen.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_save',
    'Speichert ein geöffnetes Projekt.',
    '{"type":"object","properties":{"project":{"type":"string"}},"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_remove',
    'Entfernt ein Projekt nach zusätzlicher Rückfrage aus der aktuellen Projektgruppe.',
    '{"type":"object","properties":{"project":{"type":"string"}},"required":["project"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'unit_create',
    'Erstellt eine Unit innerhalb eines geöffneten Projekts.',
    '{"type":"object","properties":{"project":{"type":"string"},"file":{"type":"string"},"source":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'form_unit_create',
    'Erstellt eine VCL-Form-Unit innerhalb eines geöffneten Projekts.',
    '{"type":"object","properties":{"project":{"type":"string"},"file":{"type":"string"},"form_name":{"type":"string"},' +
    '"ancestor_name":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    False
  );
  AddTool(Result, 'file_open', 'Öffnet eine Datei in der IDE.', '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    False);
  AddTool(Result, 'file_activate', 'Aktiviert eine bereits geöffnete Datei.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}', False);
  AddTool(Result, 'file_close', 'Schließt eine Datei über die IDE und lässt deren Speicherdialog zu.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}', False);
  AddTool(
    Result,
    'project_file_remove',
    'Entfernt eine Datei aus einem geöffneten Projekt, ohne sie vom Datenträger zu löschen.',
    '{"type":"object","properties":{"project":{"type":"string"},"file":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'form_show_as_text',
    'Öffnet die DFM-Datei eines Formulars im Texteditor.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_compile',
    'Kompiliert ein geöffnetes Projekt mit Make oder Build.',
    '{"type":"object","properties":{"project":{"type":"string"},"full_build":{"type":"boolean"},"clear_messages":{"type":"boolean"}},"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_group_compile',
    'Kompiliert alle Projekte der aktuellen Projektgruppe.',
    '{"type":"object","properties":{"full_build":{"type":"boolean"},"clear_messages":{"type":"boolean"}},"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_run',
    'Startet ein Projekt mit oder ohne Debugger; optional wird vorher kompiliert.',
    '{"type":"object","properties":{"project":{"type":"string"},"debugger":{"type":"boolean"},"build_first":{"type":"boolean"}},"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'project_stop',
    'Stoppt das mit oder ohne Debugger laufende Projekt.',
    '{"type":"object","properties":{"project":{"type":"string"},"debugger":{"type":"boolean"}},"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'ui_message_box',
    'Zeigt eine MessageBox in der Delphi-IDE.',
    '{"type":"object","properties":{"title":{"type":"string"},"message":{"type":"string"},"kind":{"type":"string","enum":["information","warning","error","confirmation"]}},' +
    '"required":["message"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'ui_input_box',
    'Zeigt eine InputBox in der Delphi-IDE.',
    '{"type":"object","properties":{"title":{"type":"string"},"prompt":{"type":"string"},"default_value":{"type":"string"}},"required":["prompt"],"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'ui_balloon_hint',
    'Zeigt einen BalloonHint am Hauptfenster der Delphi-IDE.',
    '{"type":"object","properties":{"title":{"type":"string"},"message":{"type":"string"},"timeout_ms":{"type":"integer","minimum":1000,"maximum":60000}},' +
    '"required":["message"],"additionalProperties":false}',
    False
  );
  AddTool(Result, 'form_designer_inspect', 'Liest Komponenten, Auswahl und skalare veröffentlichte Eigenschaften eines geladenen Formdesigners.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}', True);
  AddTool(Result, 'form_show_designer', 'Öffnet ein Workspace-Formular bei Bedarf und zeigt seinen Formdesigner.',
    '{"type":"object","properties":{"file":{"type":"string"}},"required":["file"],"additionalProperties":false}', False);
  AddTool(Result, 'debugger_status', 'Liest den Debuggerstatus einschließlich aktueller Prozesse und Threads.',
    '{"type":"object","additionalProperties":false}', True);
  AddTool(Result, 'breakpoints_list', 'Listet Quellhaltepunkte mit Datei, Zeile, Bedingung und Aktivierung.',
    '{"type":"object","additionalProperties":false}', True);
  AddTool(Result, 'breakpoint_set', 'Erstellt oder aktualisiert einen Quellhaltepunkt im geöffneten Workspace.',
    '{"type":"object","properties":{"file":{"type":"string"},"line":{"type":"integer","minimum":1},"enabled":{"type":"boolean"},' +
    '"condition":{"type":"string"},"pass_count":{"type":"integer","minimum":0}},"required":["file","line"],"additionalProperties":false}', False);
  AddTool(Result, 'breakpoint_remove', 'Entfernt Quellhaltepunkte an der angegebenen Datei und Zeile.',
    '{"type":"object","properties":{"file":{"type":"string"},"line":{"type":"integer","minimum":1}},' +
    '"required":["file","line"],"additionalProperties":false}', False);
  AddTool(Result, 'debugger_control', 'Pausiert den aktiven Prozess oder setzt einen angehaltenen Thread fort beziehungsweise führt Einzelschritte aus.',
    '{"type":"object","properties":{"action":{"type":"string","enum":["pause","continue","step_into","step_over","step_out"]}},' +
    '"required":["action"],"additionalProperties":false}', False);
  AddTool(Result, 'clients_registration_status', 'Prüft erkannte KI-Clients, Konfigurationspfade und DAI-Registrierungen ohne Tokenausgabe.',
    '{"type":"object","properties":{"client":{"type":"string"}},"additionalProperties":false}', True);
  AddTool(Result, 'clients_register', 'Registriert DAI für einen Client oder alle erkannten unterstützten Clients. Fremde Einträge bleiben erhalten.',
    '{"type":"object","properties":{"client":{"type":"string"}},"additionalProperties":false}', False);
  AddTool(Result, 'clients_unregister', 'Entfernt ausschließlich unveränderte, von DAI verwaltete KI-Client-Einträge.',
    '{"type":"object","properties":{"client":{"type":"string"}},"additionalProperties":false}', False);
  AddTool(Result, 'codex_registration_status', 'Prüft DAI-Einträge unter .codex und .agents.', '{"type":"object","additionalProperties":false}', True);
  AddTool(Result, 'codex_register', 'Registriert den DAI-MCP-Server und den Delphi-Skill für Codex.', '{"type":"object","additionalProperties":false}', False);
  AddTool(Result, 'codex_unregister', 'Entfernt ausschließlich die von DAI verwalteten Codex- und Skill-Einträge.', '{"type":"object","additionalProperties":false}', False);
  AddTool(
    Result,
    'msbuild_execute',
    'Ruft eine bekannte MSBuild.exe direkt und ohne Shell-Interpretation auf.',
    '{"type":"object","properties":{"executable":{"type":"string"},"arguments":{"type":"array","items":{"type":"string"}},' +
    '"working_directory":{"type":"string"},"timeout_ms":{"type":"integer","minimum":1000,"maximum":1800000}},"additionalProperties":false}',
    False
  );
  AddTool(
    Result,
    'dcc32_execute',
    'Ruft %BDS%\\bin\\dcc32.exe direkt und ohne Shell-Interpretation auf.',
    '{"type":"object","properties":{"arguments":{"type":"array","items":{"type":"string"}},"working_directory":{"type":"string"},' +
    '"timeout_ms":{"type":"integer","minimum":1000,"maximum":1800000}},"additionalProperties":false}',
    False
  );
end;

end.
