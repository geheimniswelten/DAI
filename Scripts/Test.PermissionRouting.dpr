program TestPermissionRouting;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.JSON,
  System.SysUtils,
  DAI.PermissionRouting.ProductionBranch,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Projects,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Settings,
  h5u.DAI.Types;

var
  CheckCount: Integer;
  Context: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure CheckRequest(const AGlobal: Boolean; const AResource: string);
var
  LRequest: TPermissionRequest;
begin
  Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'Exactly one permission category protects the operation');
  LRequest := TDAIPermissionManager.Instance.Requests[0];
  Check(LRequest.Category = pcProjectWrite, 'Source and project writes use the same category');
  Check(LRequest.Resource = AResource, 'Permission prompt identifies the actual target');
  if AGlobal then
    Check(LRequest.Context.ProjectKey = '', 'Create/open explicitly use the global project-write setting')
  else
    Check(LRequest.Context.ProjectKey = Context.ProjectKey, 'File writes retain their resolved owner-project context');
  Check(LRequest.Context.ThreadId = Context.ThreadId, 'Scope changes preserve the chat identity');
  Check(LRequest.Context.TransportSessionId = Context.TransportSessionId, 'Scope changes preserve the MCP session identity');
  Check(LRequest.Context.ClientName = Context.ClientName, 'Scope changes preserve the client identity');
end;

procedure CheckFileWrite(const AEditorOpen, AAllowed, ASave: Boolean; const AFile: string; const ALocalized: Boolean = False);
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
  LTool: string;
begin
  TDAIPermissionManager.Instance.Reset(not AAllowed, AAllowed);
  TDAIFileService.Reset;
  TDAIFileService.EditorOpen := AEditorOpen;
  LArguments := TJSONObject.Create;
  LResult := nil;
  LDenied := False;
  try
    LArguments.AddPair('file', AFile);
    LTool := 'FILE_WRITE';
    if ALocalized then
    begin
      LTool := 'FILE_EDIT';
      LArguments.AddPair('edits', TJSONObject.ParseJSONValue('[{"old_text":"old","new_text":"new"}]'));
    end
    else
      LArguments.AddPair('content', 'complete source text');
    LArguments.AddPair('expected_sha256', 'synthetic-full-content-hash');
    LArguments.AddPair('save', TJSONBool.Create(ASave));
    try
      LResult := DispatchProjectMutation(LTool, LArguments, Context);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(LDenied = not AAllowed, 'Editor state and save choice never change the permission scope');
    CheckRequest(False, AFile);
    Check(TDAIFileService.WriteCalls = Ord(AAllowed), 'Denied writes never reach the writer service');
    if AAllowed then
    begin
      Check(TDAIFileService.PermissionCountAtWrite = 1, 'Permission precedes the file service');
      Check(TDAIFileService.LastFile = AFile, 'File path is forwarded without reclassification');
      if ALocalized then
        Check(TDAIFileService.LastContent = '[{"old_text":"old","new_text":"new"}]', 'Patch array reaches the guarded edit service')
      else
        Check(TDAIFileService.LastContent = 'complete source text', 'Complete content is forwarded');
      Check(TDAIFileService.LastHash = 'synthetic-full-content-hash', 'Conflict-check hash is preserved');
      Check(TDAIFileService.LastSave = ASave, 'The writer retains editor/disk save semantics');
      if AEditorOpen then
        Check(LResult.GetValue<string>('target') = 'editor_buffer', 'Open file reaches the editor route')
      else
        Check(LResult.GetValue<string>('target') = 'disk', 'Closed file reaches the disk route');
    end;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure CheckFileEditArgumentTypes;
const
  CArguments: array[0..6] of string = (
    '{}',
    '{"file":123,"expected_sha256":"hash","edits":[]}',
    '{"file":"C:\\SyntheticDAITest\\Unit1.pas","edits":[]}',
    '{"file":"C:\\SyntheticDAITest\\Unit1.pas","expected_sha256":123,"edits":[]}',
    '{"file":"C:\\SyntheticDAITest\\Unit1.pas","expected_sha256":null,"edits":[]}',
    '{"file":"C:\\SyntheticDAITest\\Unit1.pas","expected_sha256":"hash","edits":[],"save":"false"}',
    '{"file":"C:\\SyntheticDAITest\\Unit1.pas","expected_sha256":"hash","edits":[],"save":0}');
var
  LJson: string;
  LArguments, LResult: TJSONObject;
  LRejected: Boolean;
begin
  for LJson in CArguments do
  begin
    TDAIFileService.Reset;
    TDAIPermissionManager.Instance.Reset(True, True);
    LArguments := TJSONObject(TJSONObject.ParseJSONValue(LJson));
    try
      LRejected := False;
      try
        LResult := DispatchProjectMutation('file_edit', LArguments, Context);
        LResult.Free;
      except
        on E: EArgumentException do LRejected := True;
      end;
      Check(LRejected and (TDAIFileService.WriteCalls = 0), 'Invalid explicit file-edit argument types never reach mutation service');
    finally
      LArguments.Free;
    end;
  end;
end;

procedure CheckProjectMutation(const ACreate, AGlobalAllowed, AProjectAllowed, ASave, ACloseOthers: Boolean);
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
  LTool: string;
begin
  TDAIPermissionManager.Instance.Reset(AGlobalAllowed, AProjectAllowed);
  TDAIProjectService.Reset;
  LArguments := TJSONObject.Create;
  LResult := nil;
  LDenied := False;
  try
    if ACreate then
    begin
      LTool := 'project_create';
      LArguments.AddPair('name', 'NewProject');
      LArguments.AddPair('directory', 'C:\SyntheticDAITest\NewProject');
      LArguments.AddPair('project_kind', 'vcl');
      LArguments.AddPair('save', TJSONBool.Create(ASave));
    end
    else
    begin
      LTool := 'project_open';
      LArguments.AddPair('file', 'C:\SyntheticDAITest\OtherProject.dproj');
    end;
    LArguments.AddPair('close_others', TJSONBool.Create(ACloseOthers));
    try
      LResult := DispatchProjectMutation(LTool, LArguments, Context);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(LDenied = not AGlobalAllowed, 'Current project grants never authorize creating/opening another project');
    if ACreate then
      CheckRequest(True, 'C:\SyntheticDAITest\NewProject')
    else
      CheckRequest(True, 'C:\SyntheticDAITest\OtherProject.dproj');
    Check(TDAIProjectService.CreateCalls = Ord(ACreate and AGlobalAllowed), 'Create service requires its global grant');
    Check(TDAIProjectService.OpenCalls = Ord(not ACreate and AGlobalAllowed), 'Open service requires its global grant');
    if AGlobalAllowed then
    begin
      Check(TDAIProjectService.PermissionCountAtCall = 1, 'Global authorization precedes project operations');
      Check(TDAIProjectService.LastCloseOthers = ACloseOthers, 'Workspace replacement intent is preserved');
      if ACreate then
      begin
        Check(TDAIProjectService.LastName = 'NewProject', 'New project name is preserved');
        Check(TDAIProjectService.LastDirectory = 'C:\SyntheticDAITest\NewProject', 'New project directory is preserved');
        Check(TDAIProjectService.LastKind = 'vcl', 'Native project kind is preserved');
        Check(TDAIProjectService.LastSave = ASave, 'Saved and unsaved creation require the same global grant');
      end
      else
        Check(TDAIProjectService.LastFile = 'C:\SyntheticDAITest\OtherProject.dproj', 'Open target is preserved');
    end;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure CheckFileRead(const ATool, AFile: string; const AEditorOpen, AProjectAllowed, ACustomAlways, ATrusted: Boolean);
var
  LArguments, LResult: TJSONObject;
  LDenied, LExpectedAllowed: Boolean;
  LRequest: TPermissionRequest;
begin
  TDAIPermissionManager.Instance.Reset(False, AProjectAllowed);
  TDAIFileService.Reset;
  TDAIFileService.EditorOpen := AEditorOpen;
  TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed := ACustomAlways;
  LArguments := TJSONObject.Create;
  LResult := nil;
  LDenied := False;
  LExpectedAllowed := ATrusted or AProjectAllowed;
  try
    LArguments.AddPair('file', AFile);
    LArguments.AddPair('maximum_characters', TJSONNumber.Create(1234));
    LArguments.AddPair('interfaces_only', TJSONBool.Create(False));
    try
      LResult := DispatchProjectMutation(ATool, LArguments, Context);
    except
      on E: EAbort do LDenied := True;
    end;
    Check(LDenied = not LExpectedAllowed, 'File reading independently checks trusted source roots after project permission denies');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'Exactly one effective read category is needed');
    LRequest := TDAIPermissionManager.Instance.Requests[0];
    if ATrusted then
      Check(LRequest.Category = pcReferenceRead, 'SDK/GetIt and explicitly allowed reference reading wins over a project denial')
    else
      Check(LRequest.Category = pcProjectRead, 'Other opened files and non-exempt custom roots require project reading');
    Check(TDAIFileService.ReadCalls = Ord(LExpectedAllowed), 'Denied reads do not reach file contents');
    if LExpectedAllowed then
    begin
      Check(TDAIFileService.PermissionCountAtRead = 1, 'Permission precedes any source read');
      Check(TDAIFileService.LastFile = AFile, 'Read target is forwarded unchanged');
      Check((TDAIFileService.LastMaximumCharacters = 1234) and not TDAIFileService.LastInterfacesOnly, 'Content options survive permission classification');
      if AEditorOpen then
        Check(LResult.GetValue<string>('source') = 'editor_buffer', 'Opened references keep the current editor content route')
      else
        Check(LResult.GetValue<string>('source') = 'disk', 'Closed references keep the disk content route');
    end;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure CheckSourceReadPermissions;
var
  LTool: string;
  LOpen, LProjectAllowed, LCustomAlways: Boolean;
begin
  for LTool in ['file_read', 'reference_file_read'] do
    for LOpen := False to True do
      for LProjectAllowed := False to True do
      begin
        CheckFileRead(LTool, 'C:\Delphi\Source\System.pas', LOpen, LProjectAllowed, False, True);
        CheckFileRead(LTool, 'C:\GetIt\ThirdParty\Unit1.pas', LOpen, LProjectAllowed, False, True);
        for LCustomAlways := False to True do
          CheckFileRead(LTool, 'C:\AdditionalRefs\Unit1.pas', LOpen, LProjectAllowed, LCustomAlways, LCustomAlways);
      end;
  for LProjectAllowed := False to True do
  begin
    CheckFileRead('file_read', 'C:\Foreign\Other.pas', True, LProjectAllowed, False, False);
    CheckFileRead('file_read', 'C:\SyntheticDAITest\Unit1.pas', True, LProjectAllowed, False, False);
  end;
  TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed := False;
end;

procedure CheckContextValidation;
var
  LArguments: TJSONObject;
  LResolved: TDAIRequestContext;
  LRejected: Boolean;
  LTools: TJSONArray;
  LTool: TJSONValue;
  LSchema, LProperties: TJSONObject;
  LPair: TJSONPair;
  LName: string;
begin
  LArguments := TJSONObject.Create;
  try
    LArguments.AddPair('file', 'C:\SyntheticDAITest\Denied\Unit1.pas');
    LResolved := ResolveValidatedArguments('file_read', LArguments, Context);
    Check(LResolved.ProjectKey = 'C:\SyntheticDAITest\Denied\Other.dproj', 'Valid file reads resolve the real owner project');
    LArguments.AddPair('project', Context.ProjectKey);
    for LName in ['file_read', 'file_write', 'file_edit', 'form_designer_inspect'] do
    begin
      TDAIOTA.ResolveCalls := 0;
      LRejected := False;
      try
        ResolveValidatedArguments(LName, LArguments, Context);
      except
        on E: EArgumentException do LRejected := Pos('project', E.Message) > 0;
      end;
      Check(LRejected, 'An undeclared project selector cannot replace the actual file owner: ' + LName);
      Check(TDAIOTA.ResolveCalls = 0, 'Unknown selectors are rejected before resolving permission ownership');
    end;
  finally
    LArguments.Free;
  end;
  LArguments := TJSONObject.Create;
  try
    LArguments.AddPair('project', 'C:\SyntheticDAITest\Denied\Other.dproj');
    LResolved := ResolveValidatedArguments('project_option_set', LArguments, Context);
    Check(LResolved.ProjectKey = 'C:\SyntheticDAITest\Denied\Other.dproj', 'Valid project-option selectors retain the declared project target');
    LArguments.AddPair('file', 'C:\SyntheticDAITest\Unit1.pas');
    TDAIOTA.ResolveCalls := 0;
    LRejected := False;
    try
      ResolveValidatedArguments('project_option_set', LArguments, Context);
    except
      on E: EArgumentException do LRejected := Pos('file', E.Message) > 0;
    end;
    Check(LRejected and (TDAIOTA.ResolveCalls = 0), 'An undeclared file selector cannot replace a project-option target');
  finally
    LArguments.Free;
  end;
  LArguments := TJSONObject.Create;
  try
    LArguments.AddPair('directory', 'C:\SyntheticDAITest\Denied');
    LResolved := ResolveValidatedArguments('directory_files_list', LArguments, Context);
    Check(LResolved.ProjectKey = 'C:\SyntheticDAITest\Denied\Other.dproj', 'Valid directory searches retain their resolved project owner');
  finally
    LArguments.Free;
  end;
  // Every published property is accepted without adding a second hand-written
  // allowlist. Type/value validation remains with the existing tool parsers.
  LTools := TDAIMCPTools.ListTools;
  try
    Check(LTools.Count > 70, 'Regression uses the complete production catalog');
    for LTool in LTools do
    begin
      LName := TJSONObject(LTool).GetValue<string>('name');
      LSchema := TJSONObject(LTool).GetValue<TJSONObject>('inputSchema');
      LProperties := LSchema.GetValue<TJSONObject>('properties', nil);
      LArguments := TJSONObject.Create;
      try
        if Assigned(LProperties) then
          for LPair in LProperties do
            LArguments.AddPair(LPair.JsonString.Value, TJSONNull.Create);
        ResolveValidatedArguments(LName, LArguments, Context);
        Check(True, 'Published property names are accepted: ' + LName);
        LArguments.AddPair('__undeclared_selector__', 'unexpected');
        LRejected := False;
        try
          ResolveValidatedArguments(LName, LArguments, Context);
        except
          on E: EArgumentException do LRejected := Pos('__undeclared_selector__', E.Message) > 0;
        end;
        Check(LRejected, 'Every tool rejects unknown property names: ' + LName);
      finally
        LArguments.Free;
      end;
    end;
  finally
    LTools.Free;
  end;
end;

const
  CExtensions: array[0..2] of string = ('.pas', '.dfm', '.dproj');
var
  LOpen, LAllowed, LSave, LCreate, LGlobalAllowed, LProjectAllowed, LCloseOthers: Boolean;
  LExtension: string;
begin
  try
    Context.ProjectKey := 'C:\SyntheticDAITest\Current.dproj';
    Context.ThreadId := 'isolated-project-chat';
    Context.TransportSessionId := 'isolated-project-session';
    Context.ClientName := 'isolated-permission-test';
    CheckContextValidation;
    CheckFileEditArgumentTypes;
    CheckSourceReadPermissions;
    for LExtension in CExtensions do
      for LOpen := False to True do
        for LAllowed := False to True do
          for LSave := False to True do
          begin
            CheckFileWrite(LOpen, LAllowed, LSave, 'C:\SyntheticDAITest\Unit1' + LExtension);
            CheckFileWrite(LOpen, LAllowed, LSave, 'C:\SyntheticDAITest\Unit1' + LExtension, True);
          end;
    for LCreate := False to True do
      for LGlobalAllowed := False to True do
        for LProjectAllowed := False to True do
          for LSave := False to True do
            for LCloseOthers := False to True do
              CheckProjectMutation(LCreate, LGlobalAllowed, LProjectAllowed, LSave, LCloseOthers);
    Writeln('PASS PermissionRouting: ', CheckCount, ' production-branch checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
