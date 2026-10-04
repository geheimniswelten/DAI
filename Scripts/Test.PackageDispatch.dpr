program Test.PackageDispatch;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.JSON,
  System.SysUtils,
  DAI.PackageDispatch.ProductionBranch,
  h5u.DAI.OTA.Packages,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Types;

const
  CTools: array[0..2] of string = ('package_install', 'package_uninstall', 'package_is_installed');
  CActions: array[0..2] of string = ('install', 'uninstall', 'status');
  CProject = 'C:\IsolatedPackageDispatch\Project\Exact.dproj';
  CBpl = 'C:\IsolatedPackageDispatch\Build\Debug\Win32\Exact370.bpl';
  CRequestedProject = 'Exact Project';
  CRequestedFile = 'C:\IsolatedPackageDispatch\Direct\Selected370.bpl';

var
  GChecks: Integer;
  GContext: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + ADescription);
end;

procedure Reset(const ASelector: Integer = 0; const ASameContext: Boolean = False);
begin
  TDAIPermissionManager.Instance.Reset;
  TDAIPackageService.Reset;
  TDAIPackageService.Target.FileName := CBpl;
  if ASelector <> 2 then
    TDAIPackageService.Target.ProjectFile := CProject;
  TDAIPackageService.Target.Configuration := 'Debug';
  TDAIPackageService.Target.Platform := 'Win32';
  GContext.ThreadId := 'package-dispatch-thread';
  GContext.TransportSessionId := 'package-dispatch-transport';
  GContext.ClientName := 'package-dispatch-client';
  GContext.ProjectKey := 'C:\IsolatedPackageDispatch\CapturedActive.dproj';
  if ASameContext then
    if ASelector = 2 then
      GContext.ProjectKey := LowerCase(CBpl)
    else
      GContext.ProjectKey := LowerCase(CProject);
end;

function Arguments(const ASelector: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  case ASelector of
    1: Result.AddPair('project', CRequestedProject);
    2: Result.AddPair('file', CRequestedFile);
  end;
end;

function TargetContext(const ASelector: Integer): string;
begin
  if ASelector = 2 then
    Result := CBpl
  else
    Result := CProject;
end;

procedure CheckNoFinalCalls;
begin
  Check(TDAIPackageService.StatusCalls = 0, 'no status service call');
  Check(TDAIPackageService.InstallCalls = 0, 'no install service call');
  Check(TDAIPackageService.UninstallCalls = 0, 'no uninstall service call');
end;

procedure CheckPermissionRequests(const ATool, ASelector, AReadCount: Integer; const ACount: Integer);
var
  LIndex: Integer;
  LRequest: TPermissionRequest;
begin
  Check(Length(TDAIPermissionManager.Instance.Requests) = ACount, 'expected number of permission requests');
  for LIndex := 0 to ACount - 1 do
  begin
    LRequest := TDAIPermissionManager.Instance.Requests[LIndex];
    Check(LRequest.Context.ThreadId = GContext.ThreadId, 'thread retained');
    Check(LRequest.Context.TransportSessionId = GContext.TransportSessionId, 'transport retained');
    Check(LRequest.Context.ClientName = GContext.ClientName, 'client retained');
    if LIndex = 0 then
    begin
      Check(LRequest.Context.ProjectKey = GContext.ProjectKey, 'first read uses captured context');
      if ASelector = 2 then
        Check(LRequest.Resource = CRequestedFile, 'initial read uses exact explicit file')
      else
        Check(LRequest.Resource = '', 'initial read has no explicit file');
    end
    else
    begin
      Check(LRequest.Context.ProjectKey = TargetContext(ASelector), 'subsequent permission uses resolved target context');
      Check(LRequest.Resource = CBpl, 'subsequent permission uses actual full target BPL');
    end;
    if LIndex < AReadCount then
    begin
      Check(LRequest.Category = pcReadAccess, 'target lookup and status require read');
      Check(LRequest.Operation = 'Package-Ziel und Installationsstatus lesen', 'read operation identifies package lookup');
    end
    else if LIndex = AReadCount then
    begin
      Check(LRequest.Category = pcEditInsideIDE, 'mutation requires IDE edit');
      if ATool = 0 then
        Check(LRequest.Operation = 'Package in dieser IDE installieren', 'install edit operation')
      else
        Check(LRequest.Operation = 'Package aus dieser IDE deinstallieren', 'uninstall edit operation');
    end
    else
    begin
      Check(LRequest.Category = pcExecute, 'mutation requires code execution');
      if ATool = 0 then
        Check(LRequest.Operation = 'Package-Code in dieser IDE laden', 'install execution operation')
      else
        Check(LRequest.Operation = 'Package-Code in dieser IDE entladen', 'uninstall execution operation');
    end;
  end;
end;

procedure TestAllowed(const ATool, ASelector: Integer; const ASameContext, ASdkSucceeded: Boolean);
var
  LArguments, LResult: TJSONObject;
  LReadCount, LCount: Integer;
begin
  Reset(ASelector, ASameContext);
  TDAIPackageService.SdkSucceeded := ASdkSucceeded;
  LArguments := Arguments(ASelector);
  LResult := nil;
  try
    LResult := DispatchPackage(UpperCase(CTools[ATool]), LArguments, GContext);
    LReadCount := 2 - Ord(ASameContext);
    LCount := LReadCount;
    if ATool <> 2 then
      Inc(LCount, 2);
    CheckPermissionRequests(ATool, ASelector, LReadCount, LCount);
    Check(TDAIPackageService.PrepareCalls = 1, 'target prepared once');
    Check(TDAIPackageService.PreparePermissionCount = 1, 'initial read permission precedes target preparation');
    if ASelector = 1 then
      Check(TDAIPackageService.LastProject = CRequestedProject, 'project selector forwarded exactly')
    else
      Check(TDAIPackageService.LastProject = '', 'default/direct file has no project selector');
    if ASelector = 2 then
      Check(TDAIPackageService.LastFile = CRequestedFile, 'file selector forwarded exactly')
    else
      Check(TDAIPackageService.LastFile = '', 'default/project has no direct file selector');
    Check(TDAIPackageService.StatusCalls = Ord(ATool = 2), 'status final service only for status');
    Check(TDAIPackageService.InstallCalls = Ord(ATool = 0), 'install final service only for install');
    Check(TDAIPackageService.UninstallCalls = Ord(ATool = 1), 'uninstall final service only for uninstall');
    Check(LResult.GetValue<string>('service_response') = 'final-package-service-response', 'final response preserved');
    Check(LResult.GetValue<string>('action') = CActions[ATool], 'correct final action response');
    Check(LResult.GetValue<Boolean>('sdk_succeeded') = ASdkSucceeded, 'SDK false/true preserved without fabricated success');
    Check(LResult.GetValue('registered') is TJSONNull, 'unknown registration remains null');
    Check(LResult.GetValue<string>('package_file') = CBpl, 'response uses actual target');
    Check(TDAIPackageService.LastTarget.ProjectFile = TDAIPackageService.Target.ProjectFile, 'target project preserved');
    Check(TDAIPackageService.LastTarget.Configuration = 'Debug', 'target config preserved');
    Check(TDAIPackageService.LastTarget.Platform = 'Win32', 'target platform preserved');
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestDenied(const ATool, ADeniedIndex: Integer);
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
begin
  Reset(2);
  TDAIPermissionManager.Instance.DeniedRequestIndex := ADeniedIndex;
  LArguments := Arguments(2);
  LResult := nil;
  LDenied := False;
  try
    try
      LResult := DispatchPackage(CTools[ATool], LArguments, GContext);
    except
      on E: EAbort do LDenied := True;
    end;
    Check(LDenied, 'every denied permission aborts request');
    Check(not Assigned(LResult), 'permission denial never returns success');
    CheckPermissionRequests(ATool, 2, 2, ADeniedIndex + 1);
    Check(TDAIPackageService.PrepareCalls = Ord(ADeniedIndex > 0), 'initial read denial blocks lookup');
    CheckNoFinalCalls;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

function InvalidValue(const AIndex: Integer): TJSONValue;
begin
  case AIndex of
    0: Result := TJSONNull.Create;
    1: Result := TJSONNumber.Create(42);
    2: Result := TJSONBool.Create(False);
    3: Result := TJSONArray.Create;
  else
    Result := TJSONObject.Create;
  end;
end;

procedure TestInvalid(const ATool, AVariant: Integer; const AName: string);
var
  LArguments, LResult: TJSONObject;
  LRejected: Boolean;
begin
  Reset;
  LArguments := TJSONObject.Create;
  LResult := nil;
  LRejected := False;
  try
    if AVariant = 5 then
    begin
      LArguments.AddPair('project', CRequestedProject);
      LArguments.AddPair('file', CRequestedFile);
    end
    else
      LArguments.AddPair(AName, InvalidValue(AVariant));
    try
      LResult := DispatchPackage(CTools[ATool], LArguments, GContext);
    except
      on E: EArgumentException do LRejected := True;
    end;
    Check(LRejected, 'invalid selector or simultaneous project/file rejected');
    Check(not Assigned(LResult), 'invalid arguments have no success result');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'invalid arguments rejected before permission');
    Check(TDAIPackageService.PrepareCalls = 0, 'invalid arguments never prepare target');
    CheckNoFinalCalls;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestSchemas;
var
  LCatalog: TJSONArray;
  LIndex: Integer;
  LTool, LSchema, LProperties: TJSONObject;
  LRequired: TJSONValue;
begin
  LCatalog := ListPackageSchemas;
  try
    Check(LCatalog.Count = 3, 'all three production schemas extracted');
    for LIndex := 0 to 2 do
    begin
      LTool := TJSONObject(LCatalog.Items[LIndex]);
      Check(LTool.GetValue<string>('name') = CTools[LIndex], 'expected package tool name');
      Check(LTool.GetValue<string>('description') <> '', 'tool description exists');
      Check(LTool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint') = (LIndex = 2), 'status-only readOnly annotation');
      LSchema := LTool.GetValue<TJSONObject>('inputSchema');
      Check(LSchema.GetValue<string>('type') = 'object', 'object schema');
      Check(not LSchema.GetValue<Boolean>('additionalProperties'), 'schema rejects unknown arguments');
      LProperties := LSchema.GetValue<TJSONObject>('properties');
      Check(LProperties.Count = 2, 'schema contains only two selectors');
      Check(LProperties.GetValue<TJSONObject>('project').GetValue<string>('type') = 'string', 'project selector string');
      Check(LProperties.GetValue<TJSONObject>('file').GetValue<string>('type') = 'string', 'file selector string');
      Check(not Assigned(LProperties.GetValue('build_first')), 'no implicit compilation argument');
      LRequired := LSchema.GetValue('required');
      if Assigned(LRequired) then
        Check((LRequired is TJSONArray) and (TJSONArray(LRequired).Count = 0), 'selectors optional for active package');
    end;
  finally
    LCatalog.Free;
  end;
end;

procedure TestNoTarget;
var
  LResult: TJSONObject;
begin
  Reset;
  TDAIPackageService.RejectPrepare := True;
  LResult := nil;
  try
    try
      LResult := DispatchPackage('package_install', nil, GContext);
      Check(False, 'missing package target rejected');
    except
      on E: EArgumentException do Check(True, 'missing package target rejected');
    end;
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'missing target stops before edit/execute');
    CheckNoFinalCalls;
  finally
    LResult.Free;
  end;
end;

procedure RunTests;
var
  LTool, LSelector, LIndex: Integer;
  LSame, LSdk: Boolean;
  LResult: TJSONObject;
begin
  for LTool := 0 to 2 do
  begin
    for LSelector := 0 to 2 do
      for LSame := False to True do
        for LSdk := False to True do
          TestAllowed(LTool, LSelector, LSame, LSdk);
    for LIndex := 0 to 1 do
      TestDenied(LTool, LIndex);
    if LTool <> 2 then
      for LIndex := 2 to 3 do
        TestDenied(LTool, LIndex);
    for LIndex := 0 to 4 do
    begin
      TestInvalid(LTool, LIndex, 'project');
      TestInvalid(LTool, LIndex, 'file');
    end;
    TestInvalid(LTool, 5, '');
  end;
  TestSchemas;
  TestNoTarget;
  Reset;
  LResult := DispatchPackage('package_is_installed', nil, GContext);
  try
    Check(TDAIPackageService.LastProject = '', 'nil arguments select active package');
    Check(TDAIPackageService.LastFile = '', 'nil arguments do not invent a filename');
    Check(TDAIPackageService.StatusCalls = 1, 'nil-argument status reaches read-only service');
  finally
    LResult.Free;
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS PackageDispatch: ', GChecks, ' assertions');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
