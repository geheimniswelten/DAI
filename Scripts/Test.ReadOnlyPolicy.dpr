program TestReadOnlyPolicy;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Projects,
  h5u.DAI.Settings,
  h5u.DAI.Types;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure DeniedCreator(const ADirectory, AKind: string; const ASave: Boolean);
var
  LDenied: Boolean;
  LResult: TJSONObject;
  LTarget: string;
begin
  LTarget := TDAISettings.Instance.ExpandPath(ADirectory);
  Check(not TDirectory.Exists(LTarget), 'readonly fixture target does not exist');
  LDenied := False;
  LResult := nil;
  try
    try
      LResult := TDAIProjectService.CreateProject('PolicyFixture', ADirectory, AKind, ASave);
    except
      on E: EDAIAccessDenied do
        LDenied := True;
    end;
  finally
    LResult.Free;
  end;
  Check(LDenied, 'creator rejects readonly source before any IDE service is needed');
  Check(not TDirectory.Exists(LTarget), 'readonly creator never creates a directory');
  Check(not TFile.Exists(TPath.Combine(LTarget, 'PolicyFixture.dpr')), 'readonly creator never writes a project');
end;

procedure WritableCreator(const ADirectory: string; const ASave: Boolean);
var
  LAllowedByPolicy: Boolean;
  LResult: TJSONObject;
begin
  LAllowedByPolicy := False;
  LResult := nil;
  try
    try
      LResult := TDAIProjectService.CreateProject('PolicyFixture', ADirectory, 'console', ASave);
    except
      on E: EInvalidOperation do
        LAllowedByPolicy := E.Message.Contains('IOTAModuleServices');
    end;
  finally
    LResult.Free;
  end;
  Check(LAllowedByPolicy, 'writable target passes policy and stops at absent IDE service');
  Check(not TDirectory.Exists(ADirectory), 'isolated writable test stops before file creation');
end;

procedure DeniedReparsePath(const APath: string);
var
  LDenied: Boolean;
begin
  LDenied := False;
  try
    TDAIOTA.RequireNoReparseWritePath(APath);
  except
    on E: EDAIAccessDenied do
      LDenied := E.Message.Contains('Reparse');
  end;
  Check(LDenied, 'write path rejects reparse point without changing read-only classification');
end;

procedure ReparseFixture(const ALink, ATarget: string);
var
  LDenied, LUsedEditor: Boolean;
  LExistingFile, LNewFile: string;
  LResult: TJSONObject;
begin
  Check(TDirectory.Exists(ALink) and TDirectory.Exists(ATarget), 'native junction fixture is present');
  LExistingFile := TPath.Combine(ALink, 'Existing.pas');
  LNewFile := TPath.Combine(ALink, 'Missing\Nested\New.pas');
  TDAISettings.Instance.CustomReadDirectories.Add(ATarget);
  Check(TDAIOTA.IsReadOnlyReferenceFile(TPath.Combine(ATarget, 'Existing.pas')), 'fixture target is a read-only reference');
  Check(not TDAIOTA.IsReadOnlyReferenceFile(LExistingFile), 'read-only classification remains lexical and grants no extra read rights');
  DeniedReparsePath(ALink);
  DeniedReparsePath(LExistingFile);
  DeniedReparsePath(LNewFile);
  DeniedCreator(TPath.Combine(ALink, 'MissingProject'), 'console', True);
  DeniedCreator(TPath.Combine(ALink, 'MissingUnsavedProject'), 'vcl', False);
  LResult := nil;
  LDenied := False;
  try
    try
      LResult := TDAIFileService.WriteFile(LExistingFile, 'modified', '', True, LUsedEditor);
    except
      on E: EDAIAccessDenied do
        LDenied := E.Message.Contains('Reparse');
    end;
  finally
    LResult.Free;
  end;
  Check(LDenied, 'file_write rejects the alias before reading buffers or checking workspace membership');
  Check(not LUsedEditor, 'rejected alias never reaches an editor buffer');
  Check(TFile.ReadAllText(TPath.Combine(ATarget, 'Existing.pas')) = 'fixture original', 'reference fixture content is unchanged');
  Check(not TDirectory.Exists(TPath.Combine(ATarget, 'Missing')), 'missing parent directories remain uncreated');
  TDAIOTA.RequireNoReparseWritePath(TPath.Combine(ATarget, 'Missing\Direct.pas'));
  Check(True, 'ordinary nonexistent path passes reparse-only guard independently of reference policy');
end;

var
  LFixtureRoot, LCustomRoot: string;
begin
  try
    Check(BorlandIDEServices = nil, 'contract test runs without a live IDE service host');
    LFixtureRoot := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'virtual-bds-not-created');
    Check(not TDirectory.Exists(LFixtureRoot), 'fixture BDS directory is virtual');
    if not SetEnvironmentVariable('BDS', PChar(LFixtureRoot)) then
      RaiseLastOSError;
    LCustomRoot := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'virtual-custom-readonly');
    TDAISettings.Instance.CustomReadDirectories.Add(LCustomRoot);
    DeniedCreator('%BDS%\source\NewConsole', 'console', True);
    DeniedCreator('%BDS%\source\NewConsoleUnsaved', 'console', False);
    DeniedCreator('%BDS%/source/NewVCL', 'vcl', True);
    DeniedCreator('%BDS%\source\NewVCLUnsaved', 'vcl', False);
    DeniedCreator(TPath.Combine(LCustomRoot, 'Nested\NewProject'), 'console', True);
    DeniedCreator(TPath.Combine(LCustomRoot, 'Nested\NewUnsavedProject'), 'vcl', False);
    WritableCreator(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'virtual-writable-saved'), True);
    WritableCreator(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'virtual-writable-unsaved'), False);
    Check(ParamCount = 2, 'test runner supplied only the isolated junction fixture');
    ReparseFixture(ParamStr(1), ParamStr(2));
    Check(not TDirectory.Exists(LFixtureRoot), 'all policy tests leave the virtual BDS tree untouched');
    Writeln('OK: ', CheckCount, ' native readonly creator checks (', SizeOf(Pointer) * 8, '-bit)');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
