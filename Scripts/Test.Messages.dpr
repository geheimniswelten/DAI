program Test.Messages;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Tabs,
  Winapi.Windows,
  IDEVirtualTrees,
  ForeignVirtualTrees,
  h5u.DAI.OTA.Messages;

type
  TMessageViewForm = class(TForm);
  TDebugLogView = class(TForm);

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + AMessage);
end;

procedure CheckRejected(const ASource: string; const ALastCount, AIndex, ACharacters: Integer);
var
  LRejected: Boolean;
  LResult: TJSONObject;
begin
  LRejected := False;
  LResult := nil;
  try
    try
      LResult := TDAIMessageService.Read(ASource, ALastCount, AIndex, ACharacters);
    except
      on E: EArgumentException do
        LRejected := True;
    end;
    Check(LRejected, 'invalid parameters are rejected');
  finally
    LResult.Free;
  end;
end;

procedure CheckUnavailable(const ASource: string; const AReason: string);
var
  LResult: TJSONObject;
begin
  LResult := TDAIMessageService.Read(ASource);
  try
    Check(not LResult.GetValue<Boolean>('available'), AReason + ': unavailable');
    Check(not LResult.GetValue<Boolean>('success'), AReason + ': not successful');
    Check(LResult.GetValue('total_count') is TJSONNull, AReason + ': unknown total is null');
    Check(LResult.GetValue<Integer>('returned_count') = 0, AReason + ': no fabricated rows');
    Check(Assigned(LResult.GetValue('adapter_details')), AReason + ': scoped adapter probe included');
  finally
    LResult.Free;
  end;
end;

procedure WorkerRead;
var
  LDone: TEvent;
  LError: string;
  LResult: TJSONObject;
  LStart: UInt64;
  LWorker: TThread;
begin
  LResult := nil;
  LDone := TEvent.Create(nil, True, False, '');
  LError := '';
  LWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        LResult := TDAIMessageService.Read('events');
      except
        on E: Exception do
          LError := E.ClassName + ': ' + E.Message;
      end;
      LDone.SetEvent;
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LStart := GetTickCount64;
    while (LDone.WaitFor(0) <> wrSignaled) and (GetTickCount64 - LStart < 3000) do
      CheckSynchronize(10);
    Check(LDone.WaitFor(0) = wrSignaled, 'worker call completes via main-thread dispatch');
    LWorker.WaitFor;
    Check(LError = '', 'worker call raises no exception: ' + LError);
    Check(LResult.GetValue<Boolean>('success'), 'worker obtains actual event rows');
  finally
    LResult.Free;
    LWorker.Free;
    LDone.Free;
  end;
end;

procedure RunTests;
var
  LBuild: TBetterHintWindowVirtualDrawTree;
  LEvents: IDEVirtualTrees.TVirtualStringTree;
  LForeign: ForeignVirtualTrees.TCustomVirtualStringTree;
  LWrongTree: TCustomControl;
  LMulti: IDEVirtualTrees.TVirtualStringTree;
  LColumn: TJSONObject;
  LEventForm: TDebugLogView;
  LIndex: Integer;
  LMessageForm: TMessageViewForm;
  LResult: TJSONObject;
  LRows: TJSONArray;
  LTabs: TTabSet;
  LText: string;
  LBefore: Integer;
begin
  Check(GetModuleHandle('vclide370.bpl') <> 0, 'isolated ABI producer BPL loaded');
  CheckRejected('arbitrary', 50, -1, 20000);
  CheckRejected('build', 0, -1, 20000);
  CheckRejected('build', 1001, -1, 20000);
  CheckRejected('events', 50, -2, 20000);
  CheckRejected('events', 50, -1, 0);
  CheckRejected('events', 50, -1, 200001);
  CheckUnavailable('build', 'missing build window');
  CheckUnavailable('events', 'missing event window');
  LMessageForm := TMessageViewForm.CreateNew(nil);
  LMessageForm.Name := 'MessageViewForm';
  LEventForm := TDebugLogView.CreateNew(nil);
  LEventForm.Name := 'DebugLogView';
  try
    LTabs := TTabSet.Create(LMessageForm);
    LTabs.Name := 'MessageGroups';
    LTabs.Tabs.Add('Suchergebnisse');
    LTabs.Tabs.Add('Erzeugen');
    LTabs.TabIndex := 0;
    LBuild := TBetterHintWindowVirtualDrawTree.Create(LMessageForm);
    LBuild.Name := 'MessageTreeView1';
    for LIndex := 0 to 4999 do
      LBuild.AddLine(WideString(Format('Zeile %d: [dcc32 Hinweis] Beispiel.pas: H2164 Test', [LIndex])));
    LResult := TDAIMessageService.Read('build');
    try
      Check(LResult.GetValue<Boolean>('available'), 'verified draw tree readable');
      Check(LResult.GetValue<Boolean>('success'), 'draw getter succeeds through genuine Delphi method ABI');
      Check(LResult.GetValue<Integer>('total_count') = 5000, 'native total count retained');
      Check(LResult.GetValue<Integer>('returned_count') = 50, 'default reads last 50');
      Check(LResult.GetValue<Boolean>('truncated'), 'omitted earlier rows reported');
      Check(LResult.GetValue<Integer>('group_index') = 1, 'build tab actual index found');
      Check(LResult.GetValue<string>('group_name') = 'Erzeugen', 'original group label retained');
      Check(LTabs.TabIndex = 0, 'reading build never changes the active search tab');
      Check(LBuild.TextCalls = 50, 'default never fetches the full message list');
      Check(LBuild.NavigationCalls <= 51, 'default navigates only its tail');
      LRows := LResult.GetValue<TJSONArray>('messages');
      for LIndex := 0 to 49 do
      begin
        Check(TJSONObject(LRows.Items[LIndex]).GetValue<Integer>('index') = 4950 + LIndex, 'original zero-based tail indices retained');
        Check(Pos('Zeile ' + IntToStr(4950 + LIndex) + ':', TJSONObject(LRows.Items[LIndex]).GetValue<string>('text')) = 1,
          'tail returns original text in chronological order');
      end;
    finally
      LResult.Free;
    end;

    LBefore := LBuild.NavigationCalls;
    LResult := TDAIMessageService.Read('build', 50, 0);
    try
      Check(LResult.GetValue<Integer>('returned_count') = 1, 'specific index returns one row');
      Check(TJSONObject(LResult.GetValue<TJSONArray>('messages').Items[0]).GetValue<Integer>('index') = 0, 'specific first index preserved');
      Check(LBuild.NavigationCalls - LBefore <= 2, 'early specific index navigates from the first node');
    finally
      LResult.Free;
    end;
    CheckRejected('build', 50, 5000, 20000);
    LBefore := LBuild.NavigationCalls;
    LResult := TDAIMessageService.Read('build', 50, 4999);
    try
      Check(LResult.GetValue<Integer>('returned_count') = 1, 'specific final index returns one row');
      Check(TJSONObject(LResult.GetValue<TJSONArray>('messages').Items[0]).GetValue<Integer>('index') = 4999, 'specific final index preserved');
      Check(LBuild.NavigationCalls - LBefore <= 2, 'late specific index navigates from the last node');
    finally
      LResult.Free;
    end;
    LResult := TDAIMessageService.Read('build', 1000, -1, 200000);
    try
      Check(LResult.GetValue<Integer>('returned_count') = 1000, 'maximum count reads exactly 1000 rows within generous text budget');
      Check(not LResult.GetValue<Boolean>('text_truncated'), 'complete selected rows are not text-truncated');
      Check(not LResult.GetValue<Boolean>('timed_out'), 'bounded native navigation completes maximum page');
      LRows := LResult.GetValue<TJSONArray>('messages');
      Check(TJSONObject(LRows.Items[0]).GetValue<Integer>('index') = 4000, 'maximum page starts at original tail boundary');
      Check(TJSONObject(LRows.Items[999]).GetValue<Integer>('index') = 4999, 'maximum page ends at original last index');
    finally
      LResult.Free;
    end;
    LBefore := LBuild.TextCalls;
    LTabs.Tabs[1] := 'Compile results';
    CheckUnavailable('build', 'unknown build tab is never guessed');
    Check(LBuild.TextCalls = LBefore, 'unknown tab never fetches another message tree');
    LTabs.Tabs[1] := '&Build';
    LResult := TDAIMessageService.Read('build', 1);
    try
      Check(LResult.GetValue<Boolean>('success'), 'verified English mnemonic build tab supported');
      Check(LResult.GetValue<string>('group_name') = '&Build', 'original English group label retained');
    finally
      LResult.Free;
    end;
    LTabs.Tabs.Add('Erzeugen');
    LBefore := LBuild.TextCalls;
    CheckUnavailable('build', 'ambiguous build tabs');
    Check(LBuild.TextCalls = LBefore, 'ambiguous tabs never invoke text getter');
    LTabs.Tabs.Delete(2);
    LTabs.Tabs[1] := 'Erzeugen';
    LBuild.Name := 'UnrelatedTree';
    CheckUnavailable('build', 'missing exact build tree');
    LBuild.Name := 'MessageTreeView1';

    LResult := TDAIMessageService.Read('build', 1000);
    try
      Check(LResult.GetValue<Integer>('returned_count') <= 1000, 'maximum row limit bounded');
      Check(LResult.GetValue<Boolean>('text_truncated'), 'overall character budget reported');
      LRows := LResult.GetValue<TJSONArray>('messages');
      LBefore := 0;
      for LIndex := 0 to LRows.Count - 1 do
        Inc(LBefore, Length(TJSONObject(LRows.Items[LIndex]).GetValue<string>('text')));
      Check(LBefore <= 20000, 'combined text fits the overall budget');
    finally
      LResult.Free;
    end;

    LEvents := IDEVirtualTrees.TVirtualStringTree.Create(LEventForm);
    LEvents.Name := 'LogTree';
    LResult := TDAIMessageService.Read('events');
    try
      Check(LResult.GetValue<Boolean>('available'), 'empty log is available');
      Check(LResult.GetValue<Boolean>('success'), 'empty log is successful');
      Check(LResult.GetValue<Integer>('total_count') = 0, 'empty log has an actual zero count');
      Check(LResult.GetValue<Integer>('returned_count') = 0, 'empty log has no rows');
      Check(not LResult.GetValue<Boolean>('truncated'), 'empty log is complete');
    finally
      LResult.Free;
    end;
    CheckRejected('events', 50, 0, 20000);
    LEvents.Name := 'DetachedLogTree';
    LForeign := ForeignVirtualTrees.TCustomVirtualStringTree.Create(LEventForm);
    try
      LForeign.Name := 'LogTree';
      CheckUnavailable('events', 'same class names from a foreign module');
      LResult := TDAIMessageService.Read('events');
      try
        Check(Pos('ABI', LResult.GetValue<string>('message')) > 0, 'foreign-module failure identifies verified ABI origin');
      finally
        LResult.Free;
      end;
    finally
      LForeign.Free;
    end;
    LWrongTree := TCustomControl.Create(LEventForm);
    try
      LWrongTree.Name := 'LogTree';
      CheckUnavailable('events', 'unrelated component with known control name');
    finally
      LWrongTree.Free;
    end;
    LEvents.Name := 'LogTree';
    LEvents.AddLine('Process started');
    LEvents.AddLine('Exception ETest: äΩ漢字 ' + WideString(#$D83D#$DE42));
    LEvents.AddLine('');
    LEvents.AddLine('Breakpoint hit');
    LResult := TDAIMessageService.Read(' EVENTS ');
    try
      Check(LResult.GetValue<Boolean>('success'), 'verified string tree uses native WideString return ABI');
      Check(LResult.GetValue<string>('source') = 'events', 'event source normalized');
      Check(LResult.GetValue<Integer>('total_count') = 4, 'event count retained');
      Check(LResult.GetValue<Integer>('returned_count') = 4, 'short event log returned completely');
      Check(not LResult.GetValue<Boolean>('truncated'), 'complete short log is not truncated');
      LRows := LResult.GetValue<TJSONArray>('messages');
      LText := TJSONObject(LRows.Items[1]).GetValue<string>('text');
      Check(LText = 'Exception ETest: äΩ漢字 ' + #$D83D#$DE42, 'Unicode and supplementary characters survive the BPL boundary');
      Check(TJSONObject(LRows.Items[2]).GetValue<string>('text') = '', 'empty legitimate log row survives B+/R+');
    finally
      LResult.Free;
    end;
    LResult := TDAIMessageService.Read('events', 50, 1, Length('Exception ETest: äΩ漢字 ') + 1);
    try
      LText := TJSONObject(LResult.GetValue<TJSONArray>('messages').Items[0]).GetValue<string>('text');
      Check(LText = 'Exception ETest: äΩ漢字 ', 'character limit never returns half a surrogate pair');
      Check(LResult.GetValue<Boolean>('text_truncated'), 'cut event text explicitly marked');
    finally
      LResult.Free;
    end;
    WorkerRead;
    LEvents.Header.Columns.Clear;
    LResult := TDAIMessageService.Read('events', 50, 3);
    try
      Check(LResult.GetValue<Boolean>('success'), 'implicit no-header column is readable');
      LColumn := TJSONObject(TJSONObject(LResult.GetValue<TJSONArray>('messages').Items[0]).GetValue<TJSONArray>('columns').Items[0]);
      Check(LColumn.GetValue<Integer>('column') = -1, 'implicit column uses native NoColumn identifier');
      Check(TJSONObject(LResult.GetValue<TJSONArray>('messages').Items[0]).GetValue<string>('text') = 'Breakpoint hit', 'implicit column retains full text');
    finally
      LResult.Free;
    end;
    LEvents.Header.Columns.Add;
    LEvents.Name := 'DetachedLogTree';
    LMulti := IDEVirtualTrees.TVirtualStringTree.Create(LEventForm);
    try
      LMulti.Name := 'LogTree';
      LMulti.Header.Columns.Add;
      LMulti.Header.Columns.Add;
      LMulti.AddColumns(['12:34', '42', 'Exception ETest: äΩ漢字']);
      LResult := TDAIMessageService.Read('events');
      try
        Check(LResult.GetValue<Boolean>('success'), 'multicolumn event log succeeds');
        Check(LResult.GetValue<Integer>('column_count') = 3, 'actual public collection column count retained');
        Check(LMulti.TextCalls = 3, 'every actual event column fetched exactly once');
        LRows := LResult.GetValue<TJSONArray>('messages');
        LText := TJSONObject(LRows.Items[0]).GetValue<string>('text');
        Check(LText = '12:34' + #9 + '42' + #9 + 'Exception ETest: äΩ漢字', 'time, PID and event message retained together');
        Check(TJSONObject(LRows.Items[0]).GetValue<Boolean>('columns_complete'), 'all event columns reported complete');
        for LIndex := 0 to 2 do
        begin
          LColumn := TJSONObject(TJSONObject(LRows.Items[0]).GetValue<TJSONArray>('columns').Items[LIndex]);
          Check(LColumn.GetValue<Integer>('column') = LIndex, 'native event column index retained');
          Check(not LColumn.GetValue<Boolean>('text_truncated'), 'individual complete columns are not truncated');
        end;
        LColumn := TJSONObject(TJSONObject(LRows.Items[0]).GetValue<TJSONArray>('columns').Items[2]);
        Check(Copy(LText, LColumn.GetValue<Integer>('text_start') + 1, LColumn.GetValue<Integer>('text_length')) = 'Exception ETest: äΩ漢字',
          'column spans recover actual event text without duplicate payload');
      finally
        LResult.Free;
      end;
      LResult := TDAIMessageService.Read('events', 50, -1, 6);
      try
        LRows := LResult.GetValue<TJSONArray>('messages');
        Check(Length(TJSONObject(LRows.Items[0]).GetValue<string>('text')) <= 6, 'shared character budget includes multicolumn separators');
        Check(not TJSONObject(LRows.Items[0]).GetValue<Boolean>('columns_complete'), 'budget-omitted event columns reported incomplete');
        Check(TJSONObject(LRows.Items[0]).GetValue('text_length') is TJSONNull, 'unread full row length is unknown rather than invented');
        Check(LResult.GetValue<Boolean>('text_truncated'), 'partial multicolumn entry reported truncated');
      finally
        LResult.Free;
      end;
      for LIndex := 4 to 33 do
        LMulti.Header.Columns.Add;
      LBefore := LMulti.TextCalls;
      CheckUnavailable('events', 'excessive event columns');
      Check(LMulti.TextCalls = LBefore, 'unsupported column count prevents native getters');
    finally
      LMulti.Free;
      LEvents.Name := 'LogTree';
    end;

    LEvents.TextDelay := 150;
    LResult := TDAIMessageService.Read('events');
    try
      Check(LResult.GetValue<Boolean>('timed_out'), 'bounded read budget reports slow provider');
      Check(not LResult.GetValue<Boolean>('success'), 'partial deadline result is not complete success');
      Check(LResult.GetValue<Integer>('returned_count') < 4, 'deadline stops further row retrieval');
    finally
      LResult.Free;
      LEvents.TextDelay := 0;
    end;
    LBefore := LEvents.TextCalls;
    LEvents.Destroying;
    CheckUnavailable('events', 'destroying event control');
    Check(LEvents.TextCalls = LBefore, 'destroying tree never calls native text getters');
    LBefore := LBuild.TextCalls;
    LTabs.Destroying;
    CheckUnavailable('build', 'destroying tab list');
    Check(LBuild.TextCalls = LBefore, 'destroying tabs never call native tree getters');
    LEventForm.Destroying;
    CheckUnavailable('events', 'destroying log form');
  finally
    LEventForm.Free;
    LMessageForm.Free;
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS: ', CheckCount, ' IDE log adapter/ABI and bounded-read checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
