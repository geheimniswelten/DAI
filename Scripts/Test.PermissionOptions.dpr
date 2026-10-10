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
  LLevel := TDAIPermissionManager.Instance.GetLevelForOptions(pcReadAccess, AContext, LInherited);
  Check((LLevel = ALevel) and (LInherited = AInherited), ADescription);
end;

procedure ExpectResetFailure(const AContext: TDAIRequestContext; const ADescription: string);
var
  LFailed: Boolean;
begin
  LFailed := False;
  try
    TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, AContext);
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
  TDAIPermissionStore.SetLevel(pcReadAccess, '', plAlways);

  CheckOptions(LGlobal, plAlways, False, 'global options are never marked inherited');
  CheckOptions(LProject, plAlways, True, 'missing project file inherits global');
  Check(not TDAIPermissionStore.TryGetProjectLevel(pcReadAccess, LProject.ProjectKey, LReadLevel), 'missing project policy has no explicit value');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  Check(not TFile.Exists(LPolicy), 'reset does not create a missing project policy');
  TDAIPermissionStore.SetLevel(pcReadAccess, LProject.ProjectKey, plAlways);
  CheckOptions(LProject, plAlways, False, 'explicit project value equal to global remains explicit');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  CheckOptions(LProject, plAlways, True, 'reset removes the project override');

  TDAIPermissionStore.SetLevel(pcReadAccess, '', plAsk);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plSession, LGlobal);
  CheckOptions(LProject, plSession, True, 'global runtime permission remains inherited');
  TDAIPermissionStore.SetLevel(pcReadAccess, LProject.ProjectKey, plAsk);
  CheckOptions(LProject, plAsk, False, 'global runtime grant does not disguise an explicit project option');
  Check(TDAIPermissionManager.Instance.GetEffectiveLevel(pcReadAccess, LProject) = plSession, 'authorization effective-level behavior remains unchanged');
  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);

  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plOnce, LProject);
  CheckOptions(LProject, plOnce, False, 'own project one-shot permission is not inherited');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plSession, LOtherProject);
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  CheckOptions(LProject, plAsk, True, 'reset clears own project runtime grants');
  CheckOptions(LOtherProject, plSession, False, 'reset preserves runtime grants for another project');

  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plDeny, LProject);
  CheckOptions(LProject, plDeny, False, 'own project one-shot denial is not inherited');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  CheckOptions(LProject, plAsk, True, 'reset clears own project runtime denials');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plSession, LGlobal);
  ExpectResetFailure(LGlobal, 'reset without project cannot modify global policy');
  CheckOptions(LGlobal, plSession, False, 'rejected global reset preserves global runtime permission');
  Check(TDAIPermissionStore.GetLevel(pcReadAccess, '') = plAsk, 'rejected global reset preserves persisted global permission');
  TDAIPermissionManager.Instance.ClearAllSessions;

  LSession := LProject;
  LSession.ThreadId := 'project-chat';
  LSession.TransportSessionId := 'transport-one';
  LOtherSession := LSession;
  LOtherSession.ThreadId := 'other-chat';
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plSession, LSession);
  CheckOptions(LSession, plSession, False, 'own project chat permission is not inherited');
  CheckOptions(LOtherSession, plAsk, True, 'another project chat does not claim a local permission');
  LOtherSession := LSession;
  LOtherSession.TransportSessionId := 'transport-two';
  CheckOptions(LOtherSession, plAsk, True, 'another transport session does not claim a local permission');
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plOnce, LProject);
  CheckOptions(LOtherSession, plOnce, False, 'project wildcard permission applies across project chats');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
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
  TFile.WriteAllText(LPolicy, '{"version":42,"custom":{"keep":true},"permissions":{"read":"never","compile":"always","unknown":"keep"}}', TEncoding.UTF8);
  CheckOptions(LProject, plNever, False, 'explicit project never remains explicit');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(LPolicy, TEncoding.UTF8)) as TJSONObject;
  try
    LPermissions := LJson.GetValue('permissions') as TJSONObject;
    Check(not Assigned(LPermissions.GetValue('read')), 'reset removes only requested category');
    Check(LPermissions.GetValue<string>('compile') = 'always', 'reset preserves other permission categories');
    Check(LPermissions.GetValue<string>('unknown') = 'keep', 'reset preserves unknown permission keys');
    Check(LJson.GetValue<Integer>('version') = 42, 'reset preserves existing file version');
    Check(Assigned(LJson.GetValue('custom')), 'reset preserves unrelated root data');
  finally
    LJson.Free;
  end;
  CheckOptions(LProject, plAsk, True, 'missing category in valid policy inherits global');
  LText := TFile.ReadAllText(LPolicy, TEncoding.UTF8);
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  Check(TFile.ReadAllText(LPolicy, TEncoding.UTF8) = LText, 'repeated reset does not rewrite an unchanged policy');
end;

procedure TestMalformedAndWriteFailure;
var
  LLock: TFileStream;
  LMalformed: string;
  LPolicy: string;
  LProject: TDAIRequestContext;
begin
  LProject := Context(TPath.Combine(FixtureDirectory, 'Protected.dproj'));
  LPolicy := TDAIPermissionStore.ProjectSettingsFileName(LProject.ProjectKey);
  TDAIPermissionStore.SetLevel(pcReadAccess, '', plAlways);
  for LMalformed in TArray<string>.Create('invalid-json', '{"permissions":[]}', '{}') do
  begin
    TFile.WriteAllText(LPolicy, LMalformed, TEncoding.UTF8);
    CheckOptions(LProject, plAsk, False, 'malformed project policy cannot inherit global always');
    ExpectResetFailure(LProject, 'reset refuses malformed project policy');
    Check(TFile.ReadAllText(LPolicy, TEncoding.UTF8) = LMalformed, 'reset preserves malformed file for repair');
  end;

  TFile.WriteAllText(LPolicy, '{"permissions":{"read":"ask"}}', TEncoding.UTF8);
  TDAIPermissionManager.Instance.SetLevelFromOptions(pcReadAccess, plSession, LProject);
  LLock := TFileStream.Create(LPolicy, fmOpenRead or fmShareDenyWrite);
  try
    ExpectResetFailure(LProject, 'reset reports a policy write failure');
  finally
    LLock.Free;
  end;
  CheckOptions(LProject, plSession, False, 'failed policy write preserves own runtime grants');
  TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(pcReadAccess, LProject);
  CheckOptions(LProject, plAlways, True, 'successful retry removes persisted and runtime overrides');
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
