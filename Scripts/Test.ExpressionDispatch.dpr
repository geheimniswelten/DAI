program Test.ExpressionDispatch;
{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}
uses
  System.JSON, System.SysUtils, System.Classes,
  DAI.ExpressionDispatch.ProductionBranch, DAI.ExpressionDispatch.TestState,
  h5u.DAI.OTA.CursorExpression, h5u.DAI.OTA.Evaluation, h5u.DAI.OTA.ExpressionUI,
  h5u.DAI.Permissions.Manager, h5u.DAI.Types;
const
  CToolNames: array[0..4] of string = ('debugger_cursor_expression', 'debugger_evaluate', 'debugger_modify',
    'debugger_evaluation_status', 'debugger_expression_ui');
var
  Checks: Integer;
  Context: TDAIRequestContext;
procedure Check(const ACondition: Boolean; const AMessage: string);
begin Inc(Checks); if not ACondition then raise EInvalidOperation.Create('Assertion failed: ' + AMessage); end;
procedure Reset;
begin
  ResetState; TDAIPermissionManager.Instance.Reset;
  TDAICursorExpressionService.Reset; TDAIEvaluationService.Reset; TDAIExpressionUIService.Reset;
  Context.ThreadId := 'expression-thread'; Context.TransportSessionId := 'expression-transport';
  Context.ClientName := 'expression-client'; Context.ProjectKey := 'C:\CapturedActive\Other.dproj';
end;
function Arguments(const ATool: string; const AUseCursor: Boolean = False): TJSONObject;
begin
  Result := TJSONObject.Create;
  if (ATool = 'debugger_evaluate') or (ATool = 'debugger_modify') then
  begin
    if AUseCursor then Result.AddPair('use_cursor', TJSONBool.Create(True)) else Result.AddPair('expression', 'Counter');
    if ATool = 'debugger_modify' then Result.AddPair('value', 'Counter + 1');
  end
  else if ATool = 'debugger_expression_ui' then Result.AddPair('action', 'watch_at_cursor')
  else if ATool = 'debugger_evaluation_status' then Result.AddPair('request_id', 'exact-status-id');
end;
procedure Replace(const AArguments: TJSONObject; const AName: string; const AValue: TJSONValue);
begin AArguments.RemovePair(AName).Free; AArguments.AddPair(AName, AValue); end;
procedure NoMutations;
begin
  Check(TDAIEvaluationService.EvaluateCalls = 0, 'no evaluator call');
  Check(TDAIEvaluationService.ModifyCalls = 0, 'no value assignment');
  Check(TDAIExpressionUIService.InvokeCalls = 0, 'no native IDE action');
end;
procedure EventsEqual(const AExpected: TArray<string>);
var I: Integer;
begin
  Check(Length(Events) = Length(AExpected), 'event count');
  for I := 0 to High(AExpected) do Check(Events[I] = AExpected[I], 'event order: ' + AExpected[I]);
end;
procedure Permission(const AIndex: Integer; const ACategory: TDAIPermissionCategory;
  const AResource, AProject, AOperation: string);
var LRequest: TPermissionRequest;
begin
  LRequest := TDAIPermissionManager.Instance.Requests[AIndex];
  Check(LRequest.Category = ACategory, 'permission category'); Check(LRequest.Resource = AResource, 'actual permission resource');
  Check(LRequest.Operation = AOperation, 'permission operation'); Check(LRequest.Context.ProjectKey = AProject, 'owning project context');
  Check(LRequest.Context.ThreadId = Context.ThreadId, 'thread context');
  Check(LRequest.Context.TransportSessionId = Context.TransportSessionId, 'transport context');
  Check(LRequest.Context.ClientName = Context.ClientName, 'client context');
end;
procedure Invalid(const ATool: string; const AArguments: TJSONObject; const ABeforePermission: Boolean = True);
var LRejected: Boolean; LResult: TJSONObject;
begin
  LRejected := False;
  try LResult := DispatchExpression(ATool, AArguments, Context); LResult.Free;
  except on E: Exception do LRejected := True; end;
  Check(LRejected, 'invalid arguments were accepted: ' + ATool); NoMutations;
  if ABeforePermission then
  begin
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'parse error prompted permission');
    Check(TDAIEvaluationService.PrepareCalls = 0, 'parse error resolved debug target');
    Check(TDAIExpressionUIService.PrepareCalls = 0, 'parse error prepared native action');
  end;
end;
procedure TestEvaluation(const AModify, AUseCursor: Boolean; const AEffects: string; const AExplicit: Boolean);
var
  LTool, LExpression, LFile: string;
  LArgs, LResult: TJSONObject;
  LRequest: TDAIEvaluationRequest;
  LPermissions, LExecuteIndex: Integer;
begin
  Reset; LTool := 'debugger_evaluate'; if AModify then LTool := 'debugger_modify';
  LArgs := Arguments(LTool, AUseCursor); LResult := nil;
  try
    LArgs.AddPair('side_effects', AEffects);
    if AExplicit then
    begin
      LArgs.AddPair('process_id', TJSONNumber.Create(Int64(High(Cardinal))));
      LArgs.AddPair('thread_id', TJSONNumber.Create(99)); LArgs.AddPair('format_specifiers', 'H');
      LArgs.AddPair('maximum_characters', TJSONNumber.Create(65536)); LArgs.AddPair('timeout_ms', TJSONNumber.Create(30000));
      if not AUseCursor then begin LArgs.AddPair('source_file', CSourceFile); LArgs.AddPair('line', TJSONNumber.Create(42)); end;
    end;
    SwitchDebugDuringPermission := True;
    LResult := DispatchExpression(UpperCase(LTool), LArgs, Context);
    LRequest := TDAIEvaluationService.LastRequest;
    Check(TDAIEvaluationService.PrepareCalls = 1, 'one captured debug target');
    Check(TDAIEvaluationService.PreparePermissionCount = 0, 'target captured before permission dialog');
    if AExplicit then
    begin
      Check(LRequest.ProcessId = High(Cardinal), 'full unsigned process id preserved');
      Check(LRequest.ThreadId = 99, 'explicit thread preserved'); Check(LRequest.FormatSpecifiers = 'H', 'format forwarded');
      Check(LRequest.MaximumCharacters = 65536, 'maximum forwarded'); Check(LRequest.TimeoutMs = 30000, 'timeout forwarded');
    end
    else
    begin
      Check(LRequest.ProcessId = 4242, 'default process captured before dialog changed context');
      Check(LRequest.ThreadId = 33, 'default thread captured before dialog changed context');
      Check(LRequest.MaximumCharacters = 4096, 'default maximum'); Check(LRequest.TimeoutMs = 5000, 'default timeout');
      Check(LRequest.FormatSpecifiers = '', 'default format');
    end;
    LExpression := 'Counter'; LFile := '';
    if AUseCursor then
    begin
      LExpression := CursorExpression; LFile := CSourceFile;
      Check(TDAICursorExpressionService.ReadCalls = 1, 'cursor read once');
      Check(TDAICursorExpressionService.ReadPermissionCount = 2, 'cursor source read after global and source permissions');
      Check(LastExpectedFile = CSourceFile, 'cursor file authorization bound to reader');
      Check(LRequest.Line = 71, 'cursor lexical line forwarded');
      Check(LResult.GetValue('cursor') = TDAICursorExpressionService.LastResponse, 'actual cursor provenance object attached');
    end
    else if AExplicit then
    begin
      LFile := CSourceFile; Check(LRequest.Line = 42, 'explicit lexical scope line');
      Check(Length(ContextFiles) = 0, 'lexical source_file does not infer debuggee rights from the source project');
    end;
    Check(LRequest.Expression = LExpression, 'exact expression forwarded'); Check(LRequest.SourceFile = LFile, 'source scope forwarded');
    Check(LRequest.SideEffects = LowerCase(Trim(AEffects)), 'effects normalized');
    LPermissions := 1; if AUseCursor then Inc(LPermissions);
    LExecuteIndex := LPermissions;
    if AModify or (LRequest.SideEffects <> 'none') then Inc(LPermissions);
    Check(Length(TDAIPermissionManager.Instance.Requests) = LPermissions, 'only required permissions');
    Permission(0, pcReadAccess, Format('Prozess %u / Thread %u', [LRequest.ProcessId, LRequest.ThreadId]), '',
      'Debuggerausdruck und seinen Wert lesen');
    if AUseCursor then Permission(1, pcReadAccess, CSourceFile, COwnerProject, 'Ausdruck im aktiven Quelleditor lesen');
    if AModify then
    begin
      Permission(LExecuteIndex, pcExecute, LExpression, '', 'Wert im angehaltenen Debuggerprozess zuweisen');
      Check(TDAIEvaluationService.ModifyCalls = 1, 'one modify'); Check(TDAIEvaluationService.EvaluateCalls = 0, 'no separate evaluation');
      Check(TDAIEvaluationService.LastValue = 'Counter + 1', 'new value forwarded exactly');
    end
    else
    begin
      Check(TDAIEvaluationService.EvaluateCalls = 1, 'one evaluation'); Check(TDAIEvaluationService.ModifyCalls = 0, 'no modification');
      if LRequest.SideEffects <> 'none' then
        Permission(LExecuteIndex, pcExecute, LExpression, '', 'Debuggerausdruck mit möglichen Seiteneffekten auswerten');
    end;
    Check(TDAIEvaluationService.FinalPermissionCount = LPermissions, 'all required permissions precede SDK call');
    Check(LResult = TDAIEvaluationService.LastResponse, 'SDK response returned unchanged');
    Check(LResult.GetValue('result_value') is TJSONNull, 'unknown result preserved');
    Check(LResult.GetValue<string>('status') = 'pending', 'deferred status preserved');
    Check(not LResult.GetValue<Boolean>('modified'), 'false modification result preserved');
    Check(Events[0] = 'evaluation:prepare', 'capture precedes any permission');
  finally LResult.Free; LArgs.Free; end;
end;
procedure TestCursor;
var LResult: TJSONObject;
begin
  Reset; LResult := DispatchExpression('debugger_cursor_expression', nil, Context);
  try
    Check(LResult = TDAICursorExpressionService.LastResponse, 'cursor response returned unchanged');
    EventsEqual(['cursor:metadata', 'permission:read', 'cursor:read']);
    Permission(0, pcReadAccess, CSourceFile, COwnerProject, 'Ausdruck im aktiven Quelleditor lesen');
    Check((Length(ContextFiles) = 1) and (ContextFiles[0] = CSourceFile), 'actual cursor owner lookup');
    Check(LastExpectedFile = CSourceFile, 'authorized file supplied to cursor reader'); NoMutations;
  finally LResult.Free; end;
  Reset; CurrentFile := ''; LResult := DispatchExpression('debugger_cursor_expression', nil, Context);
  try
    Check(not LResult.GetValue<Boolean>('available'), 'no editor unavailable');
    Check(LResult.GetValue<string>('reason_code') = 'no_active_source_editor', 'no editor reason');
    Check(TDAICursorExpressionService.ReadCalls = 0, 'no unbound source read');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'no authorization for empty file'); NoMutations;
  finally LResult.Free; end;
end;
procedure TestUI(const AAction: string);
var LArgs, LResult: TJSONObject;
begin
  Reset; LArgs := Arguments('debugger_expression_ui'); LResult := nil;
  try
    Replace(LArgs, 'action', TJSONString.Create('  ' + UpperCase(AAction) + '  '));
    LResult := DispatchExpression('debugger_expression_ui', LArgs, Context);
    EventsEqual(['ui:metadata', 'permission:read', 'ui:prepare', 'permission:read', 'permission:edit_inside_ide', 'permission:execute', 'ui:invoke']);
    Check(TDAIExpressionUIService.PreparePermissionCount = 1, 'prepare reads source only after read permission');
    Check(TDAIExpressionUIService.FinalPermissionCount = 4, 'source/global read, IDE edit and global execution precede native action');
    Check(TDAIExpressionUIService.LastAction = AAction, 'native action normalized');
    Check(TDAIExpressionUIService.LastRequest.FileName = CSourceFile, 'exact native source target');
    Check(TDAIExpressionUIService.LastRequest.SourceSha256 = 'exact-source-hash', 'prepared source hash retained');
    Check(TDAIExpressionUIService.LastRequest.Cursor.Line = 12, 'prepared cursor retained');
    Check(LastExpectedFile = CSourceFile, 'authorized file bound before prepare source read');
    Permission(0, pcReadAccess, CSourceFile, COwnerProject, 'Ziel der nativen Debuggeraktion lesen');
    Permission(1, pcReadAccess, CSourceFile, '', 'Globalen Debuggerzugriff für native Ausdrucksaktion lesen');
    Permission(2, pcEditInsideIDE, CSourceFile, COwnerProject, 'Native Debuggeraktion im Editor aufrufen: ' + AAction);
    Permission(3, pcExecute, CSourceFile, '', 'Native Debuggeraktion ausführen: ' + AAction);
    Check(LResult = TDAIExpressionUIService.LastResponse, 'native final JSON returned unchanged');
    Check(not LResult.GetValue<Boolean>('action_invoked'), 'pending native result preserved');
  finally LResult.Free; LArgs.Free; end;
end;
procedure TestStatus(const AUI: Boolean);
var LTool: string; LArgs, LResult: TJSONObject;
begin
  Reset; LTool := 'debugger_evaluation_status'; if AUI then LTool := 'debugger_expression_ui';
  LArgs := TJSONObject.Create; LResult := nil;
  try
    LArgs.AddPair('request_id', 'exact-status-id'); LResult := DispatchExpression(LTool, LArgs, Context);
    if AUI then
    begin
      EventsEqual(['permission:read', 'ui:status']); Check(LResult = TDAIExpressionUIService.LastResponse, 'UI status response');
      Check(TDAIExpressionUIService.LastRequestId = 'exact-status-id', 'UI exact id');
      Permission(0, pcReadAccess, 'exact-status-id', '', 'Status der nativen Debuggeraktion lesen');
    end
    else
    begin
      EventsEqual(['permission:read', 'evaluation:status']); Check(LResult = TDAIEvaluationService.LastResponse, 'evaluation status response');
      Check(TDAIEvaluationService.LastRequestId = 'exact-status-id', 'evaluation exact id');
      Permission(0, pcReadAccess, 'exact-status-id', '', 'Status und Ergebnis einer Debuggerauswertung lesen');
    end;
    Check(TDAIEvaluationService.PrepareCalls = 0, 'status does not capture debugger target');
    Check(TDAICursorExpressionService.MetadataCalls = 0, 'status does not query editor'); NoMutations;
  finally LResult.Free; LArgs.Free; end;
end;
procedure TestDenials;
var LTool: string; LArgs, LResult: TJSONObject; I, LCount: Integer; LRejected: Boolean;
begin
  for LTool in CToolNames do
  begin
    LCount := 1; if (LTool = 'debugger_evaluate') or (LTool = 'debugger_modify') then LCount := 2;
    if LTool = 'debugger_expression_ui' then LCount := 4;
    for I := 0 to LCount - 1 do
    begin
      Reset; LArgs := Arguments(LTool); LResult := nil;
      try
        if LTool = 'debugger_evaluate' then LArgs.AddPair('side_effects', 'properties');
        TDAIPermissionManager.Instance.DeniedRequestIndex := I; LRejected := False;
        try LResult := DispatchExpression(LTool, LArgs, Context);
        except on E: EAbort do LRejected := True; end;
        Check(LRejected, 'permission denial propagated'); Check(Length(TDAIPermissionManager.Instance.Requests) = I + 1, 'stop after denial');
        NoMutations;
        Check(TDAIEvaluationService.StatusCalls = 0, 'denied status not read');
        Check(TDAIExpressionUIService.StatusCalls = 0, 'denied UI status not read');
        if I = 0 then Check(TDAICursorExpressionService.ReadCalls = 0, 'source not read after read denial');
        if LTool = 'debugger_expression_ui' then
        begin
          if I = 0 then Check(TDAIExpressionUIService.PrepareCalls = 0, 'UI not prepared before read grant')
          else Check(TDAIExpressionUIService.PrepareCalls = 1, 'authorized preparation precedes edit grant');
        end;
      finally LResult.Free; LArgs.Free; end;
    end;
  end;
  for LTool in TArray<string>.Create('debugger_evaluate', 'debugger_modify') do
    for I := 0 to 2 do
    begin
      Reset; LArgs := Arguments(LTool, True); LResult := nil;
      try
        if LTool = 'debugger_evaluate' then LArgs.AddPair('side_effects', 'all');
        TDAIPermissionManager.Instance.DeniedRequestIndex := I; LRejected := False;
        try LResult := DispatchExpression(LTool, LArgs, Context);
        except on E: EAbort do LRejected := True; end;
        Check(LRejected, 'cursor global/source/execute denial propagated'); NoMutations;
        Check(Length(TDAIPermissionManager.Instance.Requests) = I + 1, 'cursor stops after denied grant');
        if I < 2 then Check(TDAICursorExpressionService.ReadCalls = 0, 'cursor source not read before both read grants')
        else Check(TDAICursorExpressionService.ReadCalls = 1, 'authorized cursor source read before execute denial');
      finally LResult.Free; LArgs.Free; end;
    end;
  for LTool in TArray<string>.Create('add_watch', 'watch_at_cursor', 'evaluate_modify', 'inspect_at_cursor') do
    for I := 0 to 3 do
    begin
      Reset; LArgs := Arguments('debugger_expression_ui'); LResult := nil;
      try
        Replace(LArgs, 'action', TJSONString.Create(LTool));
        TDAIPermissionManager.Instance.DeniedRequestIndex := I; LRejected := False;
        try LResult := DispatchExpression('debugger_expression_ui', LArgs, Context);
        except on E: EAbort do LRejected := True; end;
        Check(LRejected, 'native source/global read/edit/global execute denial propagated'); NoMutations;
        Check(Length(TDAIPermissionManager.Instance.Requests) = I + 1, 'native debugger action stops after denied grant');
      finally LResult.Free; LArgs.Free; end;
    end;
end;
procedure TestUnavailableAndRaces;
var LTool: string; LArgs, LResult: TJSONObject;
begin
  for LTool in TArray<string>.Create('debugger_evaluate', 'debugger_modify') do
  begin
    Reset; CursorAvailable := False; LArgs := Arguments(LTool, True); LResult := nil;
    try
      LResult := DispatchExpression(LTool, LArgs, Context); Check(not LResult.GetValue<Boolean>('available'), 'cursor unavailable');
      Check(LResult = TDAICursorExpressionService.LastResponse, 'unavailable cursor response forwarded');
      Check(Length(TDAIPermissionManager.Instance.Requests) = 2, 'unavailable cursor does not request execution'); NoMutations;
    finally LResult.Free; LArgs.Free; end;
    Reset; CurrentFile := ''; LArgs := Arguments(LTool, True);
    try Invalid(LTool, LArgs, False); Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'no empty cursor authorization');
    finally LArgs.Free; end;
    Reset; SwitchFileDuringPermission := True; LArgs := Arguments(LTool, True);
    try
      Invalid(LTool, LArgs, False); Check(LastExpectedFile = CSourceFile, 'cursor permission race keeps old authorized path');
      Check(TDAICursorExpressionService.ReadCalls = 0, 'permission race does not read changed source');
    finally LArgs.Free; end;
  end;
  Reset; CurrentFile := ''; LArgs := Arguments('debugger_expression_ui');
  try Invalid('debugger_expression_ui', LArgs, False); Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'no empty UI authorization');
  finally LArgs.Free; end;
  Reset; SwitchFileDuringPermission := True; LArgs := Arguments('debugger_expression_ui');
  try
    Invalid('debugger_expression_ui', LArgs, False); Check(LastExpectedFile = CSourceFile, 'UI source bound through permission race');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'UI prepare mismatch precedes edit/execute grants');
  finally LArgs.Free; end;
end;
procedure TestProjectCannotAuthorizeDebugger;
var LTool: string; LArgs, LResult: TJSONObject; LRead, LCursor, LRejected: Boolean; I: Integer; LLast: TPermissionRequest;
begin
  for LRead in TArray<Boolean>.Create(True, False) do
    for LCursor in TArray<Boolean>.Create(False, True) do
      for LTool in TArray<string>.Create('debugger_evaluate', 'debugger_modify') do
      begin
        Reset; LArgs := Arguments(LTool, LCursor); LResult := nil;
        try
          if LTool = 'debugger_evaluate' then LArgs.AddPair('side_effects', 'properties');
          if not LCursor then
          begin LArgs.AddPair('source_file', CSourceFile); LArgs.AddPair('line', TJSONNumber.Create(71)); end;
          TDAIPermissionManager.Instance.RejectGlobalRead := LRead;
          TDAIPermissionManager.Instance.RejectGlobalExecute := not LRead;
          LRejected := False;
          try LResult := DispatchExpression(LTool, LArgs, Context);
          except on E: EAbort do LRejected := True; end;
          Check(LRejected, 'project grants must not authorize debuggee read/execute'); NoMutations;
          LLast := TDAIPermissionManager.Instance.Requests[High(TDAIPermissionManager.Instance.Requests)];
          Check(LLast.Context.ProjectKey = '', 'rejected debuggee permission must be explicitly global');
          if LRead then Check(LLast.Category = pcReadAccess, 'global value read rejected')
          else Check(LLast.Category = pcExecute, 'global debuggee execution rejected');
          if LCursor and not LRead then
          begin
            Check(TDAICursorExpressionService.ReadCalls = 1, 'owning-project source grant permits cursor source read');
            Check(TDAIPermissionManager.Instance.Requests[1].Context.ProjectKey = COwnerProject, 'cursor source own project');
          end
          else Check(TDAICursorExpressionService.ReadCalls = 0, 'lexical scope does not imply source reads');
        finally LResult.Free; LArgs.Free; end;
      end;
  for LTool in TArray<string>.Create('debugger_evaluation_status', 'debugger_expression_ui') do
  begin
    Reset; LArgs := TJSONObject.Create; LResult := nil;
    try
      LArgs.AddPair('request_id', 'other-debugger-request'); TDAIPermissionManager.Instance.RejectGlobalRead := True;
      LRejected := False;
      try LResult := DispatchExpression(LTool, LArgs, Context);
      except on E: EAbort do LRejected := True; end;
      Check(LRejected, 'active project grant must not disclose another debuggee result/status');
      Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'status has only global read request');
      Check(TDAIPermissionManager.Instance.Requests[0].Context.ProjectKey = '', 'status explicitly global');
      Check(TDAIEvaluationService.StatusCalls = 0, 'global-denied evaluator result not read');
      Check(TDAIExpressionUIService.StatusCalls = 0, 'global-denied UI result not read'); NoMutations;
    finally LResult.Free; LArgs.Free; end;
  end;
  for LTool in TArray<string>.Create('add_watch', 'watch_at_cursor', 'evaluate_modify', 'inspect_at_cursor') do
    for I := 0 to 1 do
    begin
      Reset; LArgs := Arguments('debugger_expression_ui'); LResult := nil;
      try
        Replace(LArgs, 'action', TJSONString.Create(LTool));
        TDAIPermissionManager.Instance.RejectGlobalRead := I = 0;
        TDAIPermissionManager.Instance.RejectGlobalExecute := I = 1; LRejected := False;
        try LResult := DispatchExpression('debugger_expression_ui', LArgs, Context);
        except on E: EAbort do LRejected := True; end;
        Check(LRejected, 'editor project grant must not open native debugger evaluator/inspector'); NoMutations;
        LLast := TDAIPermissionManager.Instance.Requests[High(TDAIPermissionManager.Instance.Requests)];
        Check(LLast.Context.ProjectKey = '', 'native evaluator execution/read must be global');
      finally LResult.Free; LArgs.Free; end;
    end;
end;
procedure TestParsing;
const
  CStringNames: array[0..2] of string = ('expression', 'side_effects', 'format_specifiers');
  CIntegerNames: array[0..3] of string = ('process_id', 'thread_id', 'maximum_characters', 'timeout_ms');
  CWrongJSON: array[0..4] of string = ('null', 'false', '42', '[]', '{}');
var LTool, LName, LJSON, LExtra: string; LArgs: TJSONObject; I: Integer;
begin
  for LTool in TArray<string>.Create('debugger_evaluate', 'debugger_modify') do
  begin
    Reset; Invalid(LTool, nil);
    for LName in CStringNames do for LJSON in CWrongJSON do
    begin
      Reset; LArgs := Arguments(LTool);
      try Replace(LArgs, LName, TJSONObject.ParseJSONValue(LJSON)); Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    for LName in CIntegerNames do for LJSON in TArray<string>.Create('null', 'false', '"12"', '1.5', '[]', '{}', '-1', '4294967296') do
    begin
      Reset; LArgs := Arguments(LTool);
      try Replace(LArgs, LName, TJSONObject.ParseJSONValue(LJSON)); Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    for LJSON in TArray<string>.Create('null', '"true"', '1', '[]', '{}') do
    begin
      Reset; LArgs := Arguments(LTool);
      try Replace(LArgs, 'use_cursor', TJSONObject.ParseJSONValue(LJSON)); Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    for LExtra in TArray<string>.Create('expression', 'source_file', 'line') do
    begin
      Reset; LArgs := Arguments(LTool, True);
      try LArgs.AddPair(LExtra, 'conflict'); Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    for LJSON in TArray<string>.Create('""', '"   "') do
    begin
      Reset; LArgs := Arguments(LTool);
      try Replace(LArgs, 'expression', TJSONObject.ParseJSONValue(LJSON)); Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    Reset; LArgs := Arguments(LTool); LArgs.AddPair('source_file', CSourceFile);
    try Invalid(LTool, LArgs); finally LArgs.Free; end;
    Reset; LArgs := Arguments(LTool); LArgs.AddPair('line', TJSONNumber.Create(1));
    try Invalid(LTool, LArgs); finally LArgs.Free; end;
    for LJSON in CWrongJSON do
    begin
      Reset; LArgs := Arguments(LTool); LArgs.AddPair('source_file', TJSONObject.ParseJSONValue(LJSON)); LArgs.AddPair('line', TJSONNumber.Create(1));
      try Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    for LJSON in TArray<string>.Create('null', '"1"', '0', '-1', '2147483648', '1.5') do
    begin
      Reset; LArgs := Arguments(LTool); LArgs.AddPair('source_file', CSourceFile); LArgs.AddPair('line', TJSONObject.ParseJSONValue(LJSON));
      try Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    Reset; LArgs := Arguments(LTool); LArgs.AddPair('side_effects', 'unknown');
    try Invalid(LTool, LArgs); finally LArgs.Free; end;
  end;
  for I := 0 to 1 do
  begin
    Reset; LArgs := Arguments('debugger_evaluate');
    try
      if I = 0 then LArgs.AddPair('maximum_characters', TJSONNumber.Create(0)) else LArgs.AddPair('maximum_characters', TJSONNumber.Create(65537));
      Invalid('debugger_evaluate', LArgs);
    finally LArgs.Free; end;
    Reset; LArgs := Arguments('debugger_evaluate');
    try
      if I = 0 then LArgs.AddPair('timeout_ms', TJSONNumber.Create(99)) else LArgs.AddPair('timeout_ms', TJSONNumber.Create(30001));
      Invalid('debugger_evaluate', LArgs);
    finally LArgs.Free; end;
  end;
  for LJSON in TArray<string>.Create('null', 'false', '2', '[]', '{}', '""', '"   "') do
  begin
    Reset; LArgs := Arguments('debugger_modify');
    try Replace(LArgs, 'value', TJSONObject.ParseJSONValue(LJSON)); Invalid('debugger_modify', LArgs); finally LArgs.Free; end;
  end;
  Reset; LArgs := Arguments('debugger_modify'); LArgs.RemovePair('value').Free;
  try Invalid('debugger_modify', LArgs); finally LArgs.Free; end;
  for LJSON in TArray<string>.Create('all', 'properties') do
  begin
    Reset; LArgs := Arguments('debugger_modify'); LArgs.AddPair('side_effects', LJSON);
    try Invalid('debugger_modify', LArgs); finally LArgs.Free; end;
  end;
  for LTool in TArray<string>.Create('debugger_evaluation_status', 'debugger_expression_ui') do
  begin
    Reset; Invalid(LTool, nil);
    for LJSON in TArray<string>.Create('null', 'false', '2', '[]', '{}', '""', '"   "') do
    begin
      Reset; LArgs := TJSONObject.Create; LArgs.AddPair('request_id', TJSONObject.ParseJSONValue(LJSON));
      try Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
    for LExtra in TArray<string>.Create('action', 'expression', 'use_cursor', 'source_file', 'line', 'value') do
    begin
      Reset; LArgs := TJSONObject.Create; LArgs.AddPair('request_id', 'actual-id'); LArgs.AddPair(LExtra, 'extra');
      try Invalid(LTool, LArgs); finally LArgs.Free; end;
    end;
  end;
  for LJSON in TArray<string>.Create('null', 'false', '2', '[]', '{}', '""', '"   "') do
  begin
    Reset; LArgs := Arguments('debugger_expression_ui');
    try Replace(LArgs, 'action', TJSONObject.ParseJSONValue(LJSON)); Invalid('debugger_expression_ui', LArgs); finally LArgs.Free; end;
  end;
end;
function Schema(const ATools: TJSONArray; const AName: string): TJSONObject;
var LTool: TJSONValue;
begin
  Result := nil;
  for LTool in ATools do if LTool.GetValue<string>('name') = AName then Exit(LTool as TJSONObject);
  Check(False, 'schema missing: ' + AName);
end;
procedure PropertyType(const ASchema: TJSONObject; const AName, AType: string);
var LProperties, LProperty: TJSONObject;
begin
  LProperties := ASchema.GetValue<TJSONObject>('properties'); Check(LProperties <> nil, 'schema properties');
  LProperty := LProperties.GetValue<TJSONObject>(AName); Check(LProperty <> nil, 'schema property ' + AName);
  Check(LProperty.GetValue<string>('type') = AType, 'schema property type ' + AName);
end;
procedure TestSchemas;
var LTools: TJSONArray; LTool, LSchema, LProperty: TJSONObject; LName, LPropertyName: string; LRequired, LAlternatives: TJSONArray;
begin
  LTools := ListExpressionSchemas;
  try
    Check(LTools.Count = 5, 'exactly five tools');
    for LName in CToolNames do
    begin
      LTool := Schema(LTools, LName); LSchema := LTool.GetValue<TJSONObject>('inputSchema');
      Check(LSchema.GetValue<string>('type') = 'object', 'object schema');
      Check(not LSchema.GetValue<Boolean>('additionalProperties'), 'strict schema additional fields');
      Check(LTool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint') =
        ((LName = 'debugger_cursor_expression') or (LName = 'debugger_evaluation_status')), 'readonly annotation');
      if (LName = 'debugger_evaluate') or (LName = 'debugger_modify') then
      begin
        for LPropertyName in TArray<string>.Create('expression', 'side_effects', 'format_specifiers', 'source_file') do
          PropertyType(LSchema, LPropertyName, 'string');
        for LPropertyName in TArray<string>.Create('process_id', 'thread_id', 'line', 'maximum_characters', 'timeout_ms') do
          PropertyType(LSchema, LPropertyName, 'integer');
        PropertyType(LSchema, 'use_cursor', 'boolean'); LAlternatives := LSchema.GetValue<TJSONArray>('anyOf');
        Check(LAlternatives.Count = 2, 'expression or cursor required');
        Check(LAlternatives.Items[0].GetValue<TJSONArray>('required').Items[0].Value = 'expression', 'explicit expression alternative');
        Check(LAlternatives.Items[1].GetValue<TJSONObject>('properties').GetValue<TJSONObject>('use_cursor').GetValue<Boolean>('const'), 'cursor must true');
        LProperty := LSchema.GetValue<TJSONObject>('properties').GetValue<TJSONObject>('process_id');
        Check(LProperty.GetValue<Int64>('maximum') = Int64(High(Cardinal)), 'schema full UInt32 ID');
        LProperty := LSchema.GetValue<TJSONObject>('properties').GetValue<TJSONObject>('maximum_characters');
        Check(LProperty.GetValue<Integer>('default') = 4096, 'schema maximum default');
      end;
    end;
    LSchema := Schema(LTools, 'debugger_modify').GetValue<TJSONObject>('inputSchema'); PropertyType(LSchema, 'value', 'string');
    LRequired := LSchema.GetValue<TJSONArray>('required'); Check(LRequired.Items[0].Value = 'value', 'modify value required');
    LProperty := LSchema.GetValue<TJSONObject>('properties').GetValue<TJSONObject>('side_effects');
    Check((LProperty.GetValue<TJSONArray>('enum').Count = 1) and
      (LProperty.GetValue<TJSONArray>('enum').Items[0].Value = 'none'), 'modify cannot request evaluation side effects');
    LSchema := Schema(LTools, 'debugger_evaluation_status').GetValue<TJSONObject>('inputSchema'); PropertyType(LSchema, 'request_id', 'string');
    Check(LSchema.GetValue<TJSONArray>('required').Items[0].Value = 'request_id', 'status id required');
    LSchema := Schema(LTools, 'debugger_expression_ui').GetValue<TJSONObject>('inputSchema');
    PropertyType(LSchema, 'action', 'string'); PropertyType(LSchema, 'request_id', 'string');
    Check(LSchema.GetValue<TJSONArray>('oneOf').Count = 2, 'native action or status alternatives');
    Check(LSchema.GetValue<TJSONObject>('properties').GetValue<TJSONObject>('action').GetValue<TJSONArray>('enum').Count = 4, 'four native actions');
  finally LTools.Free; end;
end;
begin
  try
    TestCursor; TestEvaluation(False, False, 'none', False); TestEvaluation(False, False, '  PROPERTIES  ', True);
    TestEvaluation(False, True, 'all', False); TestEvaluation(False, True, 'none', True);
    TestEvaluation(True, False, 'none', True); TestEvaluation(True, True, 'none', False);
    TestUI('add_watch'); TestUI('watch_at_cursor'); TestUI('evaluate_modify'); TestUI('inspect_at_cursor');
    TestStatus(False); TestStatus(True); TestDenials; TestUnavailableAndRaces; TestProjectCannotAuthorizeDebugger; TestParsing; TestSchemas;
    Writeln('PASS ExpressionDispatch: ', Checks, ' checks against actual production helpers, branches, schemas and request records.');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
