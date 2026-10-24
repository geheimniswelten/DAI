program TestPermissionOptions;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  h5u.DAI.Settings,
  h5u.DAI.Types,
  h5u.DAI.Permissions.Dialog,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Permissions.Store;

var
  CheckCount: Integer;
  FixtureDirectory: string;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function Context(const AProject: string): TDAIRequestContext;
begin
  Result := Default(TDAIRequestContext);
  Result.ClientName := 'permission-options-fixture';
  Result.ThreadId := '*';
  Result.ProjectKey := AProject;
end;

procedure CheckOptions(const AContext: TDAIRequestContext; const ALevel: TDAIPermissionLevel; const AInherited: Boolean;
  const ADescription: string);
var
  LInherited: Boolean;
  LLevel: TDAIPermissionLevel;
begin
  LLevel := TDAIPermissionManager.Instance.GetLevelForOptions(pcProjectRead, AContext, LInherited);
  Check((LLevel = ALevel) and (LInherited = AInherited), ADescription);
end;

procedure ExpectResetFailure(const AContext: TDAIRequestContext; const ADescription: string);
var
  LFailed: Boolean;
begin
  LFailed := False;
  try
    TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, AContext);
  except
    on E: Exception do
      LFailed := True;
  end;
  Check(LFailed, ADescription);
end;

procedure TestInheritanceAndRuntime;
var
  LGlobal: TDAIRequestContext;
  LOtherProject: TDAIRequestContext;
  LPolicy: string;
  LProject: TDAIRequestContext;
  LReadLevel: TDAIPermissionLevel;
  LSession: TDAIRequestContext;
  LOtherSession: TDAIRequestContext;
begin
  LGlobal := Context('');
  LProject := Context(TPath.Combine(FixtureDirectory, 'Project with spaces.dproj'));
  LOtherProject := Context(TPath.Combine(FixtureDirectory, 'Other.dproj'));
  LPolicy := TDAIPermissionStore.ProjectSettingsFileName(LProject.ProjectKey);
  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIPermissionStore.SetLevel(pcProjectRead, '', plAlways);

  CheckOptions(LGlobal, plAlways, False, 'global options are never marked inherited');
  CheckOptions(LProject, plAlways, True, 'missing project file inherits global');
  Check(not TDAIPermissionStore.TryGetProjectLevel(pcProjectRead, LProject.ProjectKey, LReadLevel), 'missing project policy has no explicit value');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  Check(not TFile.Exists(LPolicy), 'reset does not create a missing project policy');
  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAlways);
  CheckOptions(LProject, plAlways, False, 'explicit project value equal to global remains explicit');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  CheckOptions(LProject, plAlways, True, 'reset removes the project override');

  TDAIPermissionStore.SetLevel(pcProjectRead, '', plAsk);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LGlobal);
  CheckOptions(LProject, plSession, True, 'global runtime permission remains inherited');
  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAsk);
  CheckOptions(LProject, plAsk, False, 'global runtime grant does not disguise an explicit project option');
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LProject) = plAsk, 'explicit project Ask overrides a global session grant');
  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);

  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plOnce, LProject);
  CheckOptions(LProject, plOnce, False, 'own project one-shot permission is not inherited');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LOtherProject);
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  CheckOptions(LProject, plAsk, True, 'reset clears own project runtime grants');
  CheckOptions(LOtherProject, plSession, False, 'reset preserves runtime grants for another project');

  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plDeny, LProject);
  CheckOptions(LProject, plDeny, False, 'own project one-shot denial is not inherited');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  CheckOptions(LProject, plAsk, True, 'reset clears own project runtime denials');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LGlobal);
  ExpectResetFailure(LGlobal, 'reset without project cannot modify global policy');
  CheckOptions(LGlobal, plSession, False, 'rejected global reset preserves global runtime permission');
  Check(TDAIPermissionStore.GetLevel(pcProjectRead, '') = plAsk, 'rejected global reset preserves persisted global permission');
  TDAIPermissionManager.Instance.ClearAllSessions;

  LSession := LProject;
  LSession.ThreadId := 'project-chat';
  LSession.TransportSessionId := 'transport-one';
  LOtherSession := LSession;
  LOtherSession.ThreadId := 'other-chat';
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LSession);
  CheckOptions(LSession, plSession, False, 'own project chat permission is not inherited');
  CheckOptions(LOtherSession, plAsk, True, 'another project chat does not claim a local permission');
  LOtherSession := LSession;
  LOtherSession.TransportSessionId := 'transport-two';
  CheckOptions(LOtherSession, plAsk, True, 'another transport session does not claim a local permission');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plOnce, LProject);
  CheckOptions(LOtherSession, plOnce, False, 'project wildcard permission applies across project chats');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  CheckOptions(LSession, plAsk, True, 'reset clears both chat-specific and wildcard project permissions');
end;

procedure TestPolicyPreservation;
var
  LJson: TJSONObject;
  LPermissions: TJSONObject;
  LPolicy: string;
  LProject: TDAIRequestContext;
  LText: string;
begin
  LProject := Context(TPath.Combine(FixtureDirectory, 'Preserve.dproj'));
  LPolicy := TDAIPermissionStore.ProjectSettingsFileName(LProject.ProjectKey);
  TFile.WriteAllText(LPolicy, '{"version":2,"custom":{"keep":true},"permissions":{"project_read":"never","compile":"always","unknown":"keep"}}', TEncoding.UTF8);
  CheckOptions(LProject, plNever, False, 'explicit project never remains explicit');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(LPolicy, TEncoding.UTF8)) as TJSONObject;
  try
    LPermissions := LJson.GetValue('permissions') as TJSONObject;
    Check(not Assigned(LPermissions.GetValue('project_read')), 'reset removes only requested category');
    Check(LPermissions.GetValue<string>('compile') = 'always', 'reset preserves other permission categories');
    Check(LPermissions.GetValue<string>('unknown') = 'keep', 'reset preserves unknown permission keys');
    Check(LJson.GetValue<Integer>('version') = 2, 'reset preserves existing file version');
    Check(Assigned(LJson.GetValue('custom')), 'reset preserves unrelated root data');
  finally
    LJson.Free;
  end;
  CheckOptions(LProject, plAsk, True, 'missing category in valid policy inherits global');
  LText := TFile.ReadAllText(LPolicy, TEncoding.UTF8);
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  Check(TFile.ReadAllText(LPolicy, TEncoding.UTF8) = LText, 'repeated reset does not rewrite an unchanged policy');
end;

procedure TestMalformedAndWriteFailure;
var
  LLock: TFileStream;
  LMalformed: string;
  LPolicy: string;
  LProject: TDAIRequestContext;
  LFailed: Boolean;
begin
  LProject := Context(TPath.Combine(FixtureDirectory, 'Protected.dproj'));
  LPolicy := TDAIPermissionStore.ProjectSettingsFileName(LProject.ProjectKey);
  TDAIPermissionStore.SetLevel(pcProjectRead, '', plAlways);
  for LMalformed in TArray<string>.Create('invalid-json', '{"permissions":[]}', '{}', '{"version":2,"permissions":[]}',
    '{"version":2.5,"permissions":{"project_read":"always"}}') do
  begin
    TFile.WriteAllText(LPolicy, LMalformed, TEncoding.UTF8);
    CheckOptions(LProject, plAsk, False, 'malformed project policy cannot inherit global always');
    ExpectResetFailure(LProject, 'reset refuses malformed project policy');
    Check(TFile.ReadAllText(LPolicy, TEncoding.UTF8) = LMalformed, 'reset preserves malformed file for repair');
    LFailed := False;
    try
      TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAlways);
    except
      on E: Exception do
        LFailed := True;
    end;
    Check(LFailed, 'set refuses malformed project policy');
    Check(TFile.ReadAllText(LPolicy, TEncoding.UTF8) = LMalformed, 'set preserves malformed file for repair');
  end;

  TFile.WriteAllText(LPolicy, '{"version":2,"permissions":{"project_read":"ask"}}', TEncoding.UTF8);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LProject);
  LLock := TFileStream.Create(LPolicy, fmOpenRead or fmShareDenyWrite);
  try
    ExpectResetFailure(LProject, 'reset reports a policy write failure');
    LFailed := False;
    try
      TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plNever, LProject);
    except
      on E: Exception do
        LFailed := True;
    end;
    Check(LFailed, 'persistent selection reports policy write failure');
  finally
    LLock.Free;
  end;
  CheckOptions(LProject, plSession, False, 'failed policy write preserves own runtime grants');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  CheckOptions(LProject, plAlways, True, 'successful retry removes persisted and runtime overrides');
end;

procedure TestModelAndScope;
var
  LGlobal: TDAIRequestContext;
  LProject: TDAIRequestContext;
  LOtherProject: TDAIRequestContext;
  LSession: TDAIRequestContext;
  LOtherSession: TDAIRequestContext;
  LInherited: Boolean;
  LLevel: TDAIPermissionLevel;
  LPolicy: string;
  LVersion: Integer;
  LRegistry: TRegistry;
  LJson: TJSONObject;
begin
  LGlobal := Context('');
  LProject := Context(TPath.Combine(FixtureDirectory, 'Scope.dproj'));
  LOtherProject := Context(TPath.Combine(FixtureDirectory, 'ScopeOther.dproj'));
  LPolicy := TDAIPermissionStore.ProjectSettingsFileName(LProject.ProjectKey);
  TDAIPermissionManager.Instance.ClearAllSessions;

  TDAIPermissionStore.SetLevel(pcReferenceRead, '', plNever);
  Check(TDAIPermissionStore.GetLevel(pcReferenceRead, '') = plAlways, 'reference reads cannot be disabled');
  TDAIPermissionStore.SetLevel(pcReferenceRead, LProject.ProjectKey, plNever);
  Check(TDAIPermissionManager.Instance.Authorize(pcReferenceRead, 'read SDK', '', LProject), 'reference reads never prompt');
  Check(not TFile.Exists(LPolicy), 'global-only reference category does not create project policy');
  Check(not TDAIPermissionStore.TryGetProjectLevel(pcReferenceRead, LProject.ProjectKey, LLevel), 'reference reads have no project override');

  TDAIPermissionStore.SetLevel(pcIDEOptions, LProject.ProjectKey, plNever);
  Check(TDAIPermissionStore.GetLevel(pcIDEOptions, '') = plNever, 'IDE option writes are always global');
  Check(not TFile.Exists(LPolicy), 'IDE options cannot create project policy');
  LLevel := TDAIPermissionManager.Instance.GetLevelForOptions(pcIDEOptions, LProject, LInherited);
  Check((LLevel = plNever) and not LInherited, 'global-only options are not presented as project inheritance');
  TDAIPermissionStore.SetLevel(pcIDEOptions, '', plAsk);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcIDEOptions, plSession, LProject);
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcIDEOptions, LOtherProject) = plSession, 'IDE runtime grants ignore project identity');
  TDAIPermissionManager.Instance.ClearAllSessions;

  TDAIPermissionStore.SetLevel(pcProjectRead, '', plAsk);
  TDAIPermissionStore.SetLevel(pcProjectWrite, '', plAsk);
  LSession := LProject;
  LSession.ThreadId := 'scope-chat';
  LSession.TransportSessionId := 'scope-transport';
  TDAIPermissionDialog.QueueDecision(plSession, True);
  Check(TDAIPermissionManager.Instance.Authorize(pcProjectRead, 'read project', '', LSession), 'global session selection allows current request');
  LOtherSession := LSession;
  LOtherSession.ProjectKey := LOtherProject.ProjectKey;
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LOtherSession) = plSession, 'global chat grant applies to another project');
  LOtherSession.ThreadId := 'another-chat';
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LOtherSession) = plAsk, 'global chat grant does not authorize another chat');
  LOtherSession := LSession;
  LOtherSession.TransportSessionId := 'another-transport';
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LOtherSession) = plAsk, 'global chat grant does not authorize another transport');
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectWrite, LSession) = plAsk, 'granting reads never elevates writes');
  TDAIPermissionManager.Instance.ClearAllSessions;

  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAsk);
  TDAIPermissionStore.SetLevel(pcProjectRead, LOtherProject.ProjectKey, plNever);
  TDAIPermissionStore.SetLevel(pcProjectWrite, LProject.ProjectKey, plNever);
  LVersion := TDAIPermissionManager.ChangeVersion;
  TDAIPermissionDialog.QueueDecision(plAlways, True);
  Check(TDAIPermissionManager.Instance.Authorize(pcProjectRead, 'read project', '', LSession), 'global always selection allows current request');
  Check(TDAIPermissionManager.ChangeVersion <> LVersion, 'permission changes invalidate toolbar summaries');
  Check(TDAIPermissionStore.GetLevel(pcProjectRead, '') = plAlways, 'global selection persists global permission');
  Check(not TDAIPermissionStore.TryGetProjectLevel(pcProjectRead, LProject.ProjectKey, LLevel), 'global selection resets current project override');
  Check(TDAIPermissionStore.GetLevel(pcProjectRead, LOtherProject.ProjectKey) = plNever, 'global selection preserves another project override');
  Check(TDAIPermissionStore.GetLevel(pcProjectWrite, LProject.ProjectKey) = plNever, 'global selection never promotes other categories');

  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plNever);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plAlways, LGlobal, LProject.ProjectKey);
  CheckOptions(LProject, plAlways, True, 'global option setter resets explicitly supplied current project');
  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAsk);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plOnce, LGlobal);
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LProject) = plAsk, 'explicit project Ask overrides global one-shot grant');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcProjectRead, LProject);
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LProject) = plOnce, 'inherited global one-shot remains available');
  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LProject);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plAsk, LGlobal, LProject.ProjectKey);
  CheckOptions(LProject, plAsk, True, 'global setting reset clears stale project runtime grants');
  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAsk);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plOnce, LProject);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plOnce, LProject);
  Check(TDAIPermissionManager.Instance.Authorize(pcProjectRead, 'first', '', LProject), 'first one-shot grant is consumed once');
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LProject) = plOnce, 'duplicate wildcard lookup preserves second pending grant');
  Check(TDAIPermissionManager.Instance.Authorize(pcProjectRead, 'second', '', LProject), 'second one-shot grant remains available');
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LProject) = plAsk, 'both one-shot grants are exhausted');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plSession, LProject);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcProjectRead, plDeny, LProject);
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcProjectRead, LProject) = plDeny, 'one-shot denial precedes a session grant');
  Check(not TDAIPermissionManager.Instance.Authorize(pcProjectRead, 'denied once', '', LProject), 'one-shot denial is applied');
  Check(TDAIPermissionManager.Instance.Authorize(pcProjectRead, 'session resumes', '', LProject), 'session grant resumes after denial consumed');
  TDAIPermissionManager.Instance.ClearAllSessions;

  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    Check(LRegistry.OpenKey(TDAISettings.Instance.RegistryRoot + '\Permissions', True), 'legacy registry fixture created');
    LRegistry.WriteString('execute', 'always');
  finally
    LRegistry.Free;
  end;
  Check(TDAIPermissionStore.GetLevel(pcExecute, '') = plAsk, 'old global permissions are not migrated');
  TFile.WriteAllText(LPolicy, '{"version":1,"permissions":{"read":"always","compile":"always"}}', TEncoding.UTF8);
  Check(not TDAIPermissionStore.TryGetProjectLevel(pcCompile, LProject.ProjectKey, LLevel), 'legacy project permissions are ignored');
  TDAIPermissionStore.SetLevel(pcProjectWrite, LProject.ProjectKey, plAsk);
  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(LPolicy, TEncoding.UTF8)) as TJSONObject;
  try
    Check(LJson.GetValue<Integer>('version') = 2, 'new project permissions use schema two');
    Check(not Assigned((LJson.GetValue('permissions') as TJSONObject).GetValue('compile')), 'old project compile permission is not migrated');
  finally
    LJson.Free;
  end;
  TFile.WriteAllText(LPolicy, '{"version":2,"permissions":{"project_read":true}}', TEncoding.UTF8);
  CheckOptions(LProject, plAsk, False, 'non-string permission fails closed without raising');
  TFile.WriteAllText(LPolicy, '{"version":99,"permissions":{"project_read":"always"}}', TEncoding.UTF8);
  CheckOptions(LProject, plAsk, False, 'future project policy fails closed');
  ExpectResetFailure(LProject, 'future project policy is protected from changes');
end;

procedure TestAccessSummary;
var
  LGlobal: TDAIRequestContext;
  LProject: TDAIRequestContext;
begin
  LGlobal := Context('');
  LProject := Context(TPath.Combine(FixtureDirectory, 'Summary.dproj'));
  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIPermissionStore.SetLevel(pcIDEOptions, '', plAsk);
  TDAIPermissionStore.SetLevel(pcCompile, '', plAsk);
  TDAIPermissionStore.SetLevel(pcExecute, '', plAsk);
  TDAIPermissionStore.SetLevel(pcProjectRead, '', plAsk);
  TDAIPermissionStore.SetLevel(pcProjectWrite, '', plAsk);
  Check(TDAIPermissionManager.Instance.GetAccessSummary('', True) = 'lesen', 'IDE reference reading is always available');
  Check(TDAIPermissionManager.Instance.GetAccessSummary('', False) = 'kein Projekt', 'missing project is represented honestly');
  Check(TDAIPermissionManager.Instance.GetAccessSummary(LProject.ProjectKey, False) = 'nachfragen', 'ungranted project access is not shown as allowed');
  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plNever);
  Check(TDAIPermissionManager.Instance.GetAccessSummary(LProject.ProjectKey, False) = 'gesperrt', 'blocked project is shown as blocked');
  TDAIPermissionStore.SetLevel(pcProjectRead, LProject.ProjectKey, plAlways);
  Check(TDAIPermissionManager.Instance.GetAccessSummary(LProject.ProjectKey, False) = 'lesen', 'project reads summary');
  TDAIPermissionStore.SetLevel(pcProjectWrite, LProject.ProjectKey, plAlways);
  Check(TDAIPermissionManager.Instance.GetAccessSummary(LProject.ProjectKey, False) = 'schreiben', 'project writes summary');
  TDAIPermissionStore.SetLevel(pcCompile, LProject.ProjectKey, plAlways);
  TDAIPermissionStore.SetLevel(pcExecute, LProject.ProjectKey, plAlways);
  Check(TDAIPermissionManager.Instance.GetAccessSummary(LProject.ProjectKey, False) = 'Vollzugriff', 'all project categories yield full access');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcIDEOptions, plSession, LGlobal);
  Check(TDAIPermissionManager.Instance.GetAccessSummary('', True) = 'schreiben', 'IDE session grant shown without claiming compile/execute');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcCompile, plSession, LGlobal);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcExecute, plSession, LGlobal);
  Check(TDAIPermissionManager.Instance.GetAccessSummary('', True) = 'Vollzugriff', 'global session grants produce full IDE access');
  TDAIPermissionManager.Instance.ClearAllSessions;
end;

procedure CleanupRegistry;
var
  LRegistry: TRegistry;
  LRoot: string;
begin
  LRoot := TDAISettings.Instance.RegistryRoot;
  if not LRoot.StartsWith('Software\DAI\PermissionOptionsTests\') then
    raise EInvalidOperation.Create('Unexpected fixture registry path.');
  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    LRegistry.DeleteKey(LRoot + '\Permissions');
    LRegistry.DeleteKey(LRoot + '\PermissionsV2');
    LRegistry.DeleteKey(LRoot);
  finally
    LRegistry.Free;
  end;
end;

var
  LGuid: TGUID;
begin
  try
    CreateGUID(LGuid);
    FixtureDirectory := TPath.Combine(TPath.GetTempPath, 'DAI-PermissionOptions-' + GUIDToString(LGuid));
    TDirectory.CreateDirectory(FixtureDirectory);
    try
      TestInheritanceAndRuntime;
      TestPolicyPreservation;
      TestMalformedAndWriteFailure;
      TestModelAndScope;
      TestAccessSummary;
      Writeln('OK: ', CheckCount, ' permission option checks');
    finally
      CleanupRegistry;
      if TPath.GetFileName(FixtureDirectory).StartsWith('DAI-PermissionOptions-{') then
        TDirectory.Delete(FixtureDirectory, True);
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
