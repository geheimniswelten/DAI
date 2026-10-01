program TestBuild;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SyncObjs,
  System.SysUtils,
  ToolsAPI,
  DAI.Build.Fixture,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.Helpers;

type
  TCapturedBuild = record
    Mode: TOTACompileMode;
    Wait: Boolean;
    ClearMessages: Boolean;
  end;

  TTestBuilder = class(TInterfacedObject, IOTAProjectBuilder)
  public
    Calls: TArray<TCapturedBuild>;
    Succeeded: Boolean;
    Finished: Boolean;
    Entered: TEvent;
    ReleaseBuild: TEvent;
    function GetShouldBuild: Boolean;
    function BuildProject(CompileMode: TOTACompileMode; Wait: Boolean): Boolean; overload;
    function BuildProject(CompileMode: TOTACompileMode; Wait, ClearMessages: Boolean): Boolean; overload;
    function AddCompileNotifier(const Notifier: IOTAProjectCompileNotifier): Integer;
    procedure RemoveCompileNotifier(NotifierIndex: Integer);
  end;

var
  CheckCount: Integer;
  FixtureRoot: string;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function TTestBuilder.GetShouldBuild: Boolean;
begin
  Result := True;
end;

function TTestBuilder.BuildProject(CompileMode: TOTACompileMode; Wait: Boolean): Boolean;
begin
  raise EInvalidOperation.Create('The legacy two-argument builder must not be selected.');
end;

function TTestBuilder.BuildProject(CompileMode: TOTACompileMode; Wait, ClearMessages: Boolean): Boolean;
var
  LCall: TCapturedBuild;
begin
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('BuildProject must be invoked inside the IDE dispatcher.');
  LCall.Mode := CompileMode;
  LCall.Wait := Wait;
  LCall.ClearMessages := ClearMessages;
  Calls := Calls + [LCall];
  if Assigned(Entered) then
  begin
    Entered.SetEvent;
    if not Assigned(ReleaseBuild) or (ReleaseBuild.WaitFor(5000) <> wrSignaled) then
      raise EInvalidOperation.Create('Synthetic builder completion was never released.');
  end;
  Finished := True;
  Result := Succeeded;
end;

function TTestBuilder.AddCompileNotifier(const Notifier: IOTAProjectCompileNotifier): Integer;
begin
  raise EInvalidOperation.Create('Synchronous build must not register a compile notifier.');
end;

procedure TTestBuilder.RemoveCompileNotifier(NotifierIndex: Integer);
begin
  raise EInvalidOperation.Create('Synchronous build must not unregister a compile notifier.');
end;

function NewProject(const AName: string; const ABuilder: IOTAProjectBuilder): IOTAProject;
var
  LProject: TTestProject;
begin
  LProject := TTestProject.Create;
  LProject.FileNameValue := TPath.Combine(FixtureRoot, AName + '.dpr');
  LProject.BuilderValue := ABuilder;
  Result := LProject;
end;

function NewGroup: IOTAProjectGroup;
var
  LGroup: TTestGroup;
begin
  LGroup := TTestGroup.Create;
  LGroup.FileNameValue := TPath.Combine(FixtureRoot, 'Fixture.groupproj');
  Result := LGroup;
end;

procedure ResetFixture;
begin
  TDAIOTA.TestProjects := nil;
  TDAIOTA.LastSelectedProject := nil;
  TDAIOTA.TestGroup := NewGroup;
  TDAIOTA.WritePreflightCount := 0;
  Check(TDAIOTA.DispatchDepth = 0, 'previous build released the IDE dispatch scope');
end;

procedure SingleProjectCases;
var
  LBuilder: TTestBuilder;
  LBuilderInterface: IOTAProjectBuilder;
  LClear, LFullBuild, LSuccess: Boolean;
  LExpectedMode: TOTACompileMode;
  LJson: TJSONObject;
  LProject: IOTAProject;
begin
  for LFullBuild in [False, True] do
    for LClear in [False, True] do
      for LSuccess in [False, True] do
      begin
        ResetFixture;
        LBuilder := TTestBuilder.Create;
        LBuilderInterface := LBuilder;
        LBuilder.Succeeded := LSuccess;
        LProject := NewProject('Single', LBuilderInterface);
        TDAIOTA.TestProjects := [LProject];
        LJson := TDAIBuildService.CompileProject(LProject.FileName, LFullBuild, LClear);
        try
          LExpectedMode := cmOTAMake;
          if LFullBuild then
            LExpectedMode := cmOTABuild;
          Check(Length(LBuilder.Calls) = 1, 'one three-argument builder invocation per project');
          Check(LBuilder.Calls[0].Mode = LExpectedMode, 'make/build selects the requested native compiler mode');
          Check(not LBuilder.Calls[0].Wait, 'successful build acknowledgement is not requested');
          Check(LBuilder.Calls[0].ClearMessages = LClear, 'ClearMessages is preserved');
          Check(LBuilder.Finished, 'JSON is returned only after the builder returns');
          Check(LJson.GetValue<Boolean>('succeeded') = LSuccess, 'native success and failure result is preserved');
          Check(LJson.GetValue<string>('mode') = IfThen(LFullBuild, 'build', 'make'), 'JSON compile mode is preserved');
          Check(LJson.GetValue<string>('project') = LProject.FileName, 'JSON identifies the compiled project');
          Check(TDAIOTA.LastSelectedProject = LProject, 'the requested project is selected before compilation');
          Check(TDAIOTA.WritePreflightCount > 0, 'production write preflight still runs');
        finally
          LJson.Free;
        end;
      end;
end;

procedure GroupCase(const AFullBuild, AClearMessages, ASecondSucceeds: Boolean);
var
  LBuilders: array[0..2] of TTestBuilder;
  LBuilderInterfaces: array[0..2] of IOTAProjectBuilder;
  LExpectedCount, LIndex: Integer;
  LExpectedMode: TOTACompileMode;
  LItems: TJSONArray;
  LJson: TJSONObject;
  LProjectList: TArray<IOTAProject>;
begin
  ResetFixture;
  SetLength(LProjectList, 3);
  for LIndex := 0 to 2 do
  begin
    LBuilders[LIndex] := TTestBuilder.Create;
    LBuilderInterfaces[LIndex] := LBuilders[LIndex];
    LBuilders[LIndex].Succeeded := True;
    LProjectList[LIndex] := NewProject('Group' + LIndex.ToString, LBuilderInterfaces[LIndex]);
  end;
  LBuilders[1].Succeeded := ASecondSucceeds;
  TDAIOTA.TestProjects := LProjectList;
  LExpectedCount := 2;
  if ASecondSucceeds then
    LExpectedCount := 3;
  LExpectedMode := cmOTAMake;
  if AFullBuild then
    LExpectedMode := cmOTABuild;
  LJson := TDAIBuildService.CompileProjectGroup(AFullBuild, AClearMessages);
  try
    LItems := LJson.GetValue<TJSONArray>('projects');
    Check(LItems.Count = LExpectedCount, 'group stops after native failure and includes only attempted projects');
    Check(LJson.GetValue<Boolean>('succeeded') = ASecondSucceeds, 'group aggregates actual native results');
    for LIndex := 0 to LExpectedCount - 1 do
    begin
      Check(Length(LBuilders[LIndex].Calls) = 1, 'group invokes each attempted builder once');
      Check(not LBuilders[LIndex].Calls[0].Wait, 'group does not request a success acknowledgement');
      Check(LBuilders[LIndex].Calls[0].Mode = LExpectedMode, 'group forwards make/build mode');
      Check(LBuilders[LIndex].Calls[0].ClearMessages = (AClearMessages and (LIndex = 0)), 'only the first group project clears messages');
      Check(LBuilders[LIndex].Finished, 'each group result is returned after its builder completes');
      Check((LItems.Items[LIndex] as TJSONObject).GetValue<string>('project') = LProjectList[LIndex].FileName, 'group result preserves order');
    end;
    Check(TDAIOTA.LastSelectedProject = LProjectList[LExpectedCount - 1], 'group finishes with its last attempted project selected');
    if not ASecondSucceeds then
      Check(Length(LBuilders[2].Calls) = 0, 'later group project is never built after failure');
  finally
    LJson.Free;
  end;
end;

procedure MissingBuilderCases;
var
  LDenied: Boolean;
  LJson: TJSONObject;
  LProject: IOTAProject;
begin
  ResetFixture;
  LDenied := False;
  try
    LJson := TDAIBuildService.CompileProject('missing-project', False, True);
    LJson.Free;
  except
    on E: EArgumentException do
      LDenied := True;
  end;
  Check(LDenied, 'missing project fails clearly before compilation');
  LProject := NewProject('NoBuilder', nil);
  TDAIOTA.TestProjects := [LProject];
  LJson := TDAIBuildService.CompileProject(LProject.FileName, False, True);
  try
    Check(not LJson.GetValue<Boolean>('succeeded'), 'missing native builder returns failure');
  finally
    LJson.Free;
  end;
end;

procedure BlockingBuilderCase;
var
  LBuilder: TTestBuilder;
  LBuilderInterface: IOTAProjectBuilder;
  LCompleted: TEvent;
  LEntered: TEvent;
  LFailure: string;
  LJson: TJSONObject;
  LProject: IOTAProject;
  LRelease: TEvent;
  LWorker: TThread;
begin
  ResetFixture;
  LBuilder := TTestBuilder.Create;
  LBuilderInterface := LBuilder;
  LBuilder.Succeeded := True;
  LProject := NewProject('Blocking', LBuilderInterface);
  TDAIOTA.TestProjects := [LProject];
  LEntered := TEvent.Create(nil, True, False, '');
  LRelease := TEvent.Create(nil, True, False, '');
  LCompleted := TEvent.Create(nil, True, False, '');
  LBuilder.Entered := LEntered;
  LBuilder.ReleaseBuild := LRelease;
  LJson := nil;
  LFailure := '';
  LWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        LJson := TDAIBuildService.CompileProject(LProject.FileName, False, False);
      except
        on E: Exception do
          LFailure := E.ClassName + ': ' + E.Message;
      end;
      LCompleted.SetEvent;
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    Check(LEntered.WaitFor(2000) = wrSignaled, 'real Build service reaches the blocked native builder');
    Check(LCompleted.WaitFor(0) = wrTimeout, 'Wait=False does not make DAI return before the native builder returns');
    Check(not LBuilder.Finished, 'blocked native builder has not completed');
    LRelease.SetEvent;
    Check(LCompleted.WaitFor(2000) = wrSignaled, 'DAI returns after releasing native builder completion');
    LWorker.WaitFor;
    Check(LFailure = '', 'blocked build finishes without an exception: ' + LFailure);
    Check(Assigned(LJson) and LJson.GetValue<Boolean>('succeeded'), 'blocking builder final success is preserved');
    Check(LBuilder.Finished, 'native completion precedes returned result');
    Check(not LBuilder.Calls[0].Wait, 'blocking build still suppresses the success acknowledgement');
  finally
    LRelease.SetEvent;
    LWorker.WaitFor;
    LWorker.Free;
    LJson.Free;
    LBuilder.Entered := nil;
    LBuilder.ReleaseBuild := nil;
    LCompleted.Free;
    LRelease.Free;
    LEntered.Free;
  end;
end;

var
  LClear, LFullBuild, LSecondSucceeds: Boolean;
begin
  try
    Check(BorlandIDEServices = nil, 'isolated Build tests run without a live IDE host');
    FixtureRoot := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'VirtualWorkspaceNotCreated');
    Check(not TDirectory.Exists(FixtureRoot), 'synthetic workspace has no files to save or compile');
    SingleProjectCases;
    for LFullBuild in [False, True] do
      for LClear in [False, True] do
        for LSecondSucceeds in [False, True] do
          GroupCase(LFullBuild, LClear, LSecondSucceeds);
    MissingBuilderCases;
    BlockingBuilderCase;
    TDAIOTA.TestProjects := nil;
    TDAIOTA.TestGroup := nil;
    TDAIOTA.LastSelectedProject := nil;
    Check(not TDirectory.Exists(FixtureRoot), 'Build contract tests never create output or source files');
    Writeln('OK: ', CheckCount, ' native Build checks (', SizeOf(Pointer) * 8, '-bit)');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
