program TestWindows;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Winapi.Windows,
  h5u.DAI.Windows.Inspection;

type
  TWindowWorker = class(TThread)
  private
    FRespond: Boolean;
    FReady: THandle;
    FStop: THandle;
    FWindow: HWND;
    FStatic: HWND;
    FPassword: HWND;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARespond: Boolean);
    destructor Destroy; override;
    procedure AwaitReady;
    procedure Finish;
    property Window: HWND read FWindow;
    property StaticControl: HWND read FStatic;
    property PasswordControl: HWND read FPassword;
  end;

  TInspectionWorker = class(TThread)
  private
    FResult: TJSONObject;
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
    function TakeResult: TJSONObject;
  end;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function HandleText(const AHandle: HWND): string;
begin
  Result := '0x' + IntToHex(NativeUInt(AHandle), SizeOf(Pointer) * 2);
end;

function JsonString(const AObject: TJSONObject; const AName: string): string;
var
  LValue: TJSONValue;
begin
  if not Assigned(AObject) then
    Exit('');
  LValue := AObject.GetValue(AName);
  if Assigned(LValue) then
    Result := LValue.Value
  else
    Result := '';
end;

function JsonInteger(const AObject: TJSONObject; const AName: string): Int64;
begin
  Result := StrToInt64Def(JsonString(AObject, AName), -1);
end;

function FindHandle(const AResult: TJSONObject; const AHandle: HWND): TJSONObject;
var
  LWindows, LChildren: TJSONArray;
  LWindow, LChild: TJSONValue;
begin
  Result := nil;
  LWindows := TJSONArray(AResult.GetValue('windows'));
  for LWindow in LWindows do
  begin
    if JsonString(TJSONObject(LWindow), 'handle') = HandleText(AHandle) then
      Exit(TJSONObject(LWindow));
    LChildren := TJSONArray(TJSONObject(LWindow).GetValue('children'));
    if Assigned(LChildren) then
      for LChild in LChildren do
        if JsonString(TJSONObject(LChild), 'handle') = HandleText(AHandle) then
          Exit(TJSONObject(LChild));
  end;
end;

constructor TWindowWorker.Create(const ARespond: Boolean);
begin
  inherited Create(True);
  FRespond := ARespond;
  FReady := CreateEvent(nil, True, False, nil);
  FStop := CreateEvent(nil, True, False, nil);
  if (FReady = 0) or (FStop = 0) then
    RaiseLastOSError;
end;

destructor TWindowWorker.Destroy;
begin
  Finish;
  CloseHandle(FReady);
  CloseHandle(FStop);
  inherited;
end;

procedure TWindowWorker.Execute;
var
  LMessage: TMsg;
begin
  try
    // Hidden windows belong only to this isolated test process. Never enumerate or send input to an IDE.
    FWindow := CreateWindowEx(WS_EX_TOOLWINDOW, 'STATIC', 'DAI isolated window', WS_OVERLAPPED,
      0, 0, 160, 100, 0, 0, HInstance, nil);
    if FWindow = 0 then
      RaiseLastOSError;
    FStatic := CreateWindowEx(0, 'STATIC', 'DAI isolated label', WS_CHILD, 0, 0, 100, 20, FWindow, 0, HInstance, nil);
    FPassword := CreateWindowEx(0, 'EDIT', 'test-only-secret', WS_CHILD or ES_PASSWORD,
      0, 20, 100, 20, FWindow, 0, HInstance, nil);
    if (FStatic = 0) or (FPassword = 0) then
      RaiseLastOSError;
    SetEvent(FReady);
    if FRespond then
    begin
      while WaitForSingleObject(FStop, 0) = WAIT_TIMEOUT do
      begin
        MsgWaitForMultipleObjects(1, FStop, False, 50, QS_ALLINPUT);
        while PeekMessage(LMessage, 0, 0, 0, PM_REMOVE) do
        begin
          TranslateMessage(LMessage);
          DispatchMessage(LMessage);
        end;
      end;
    end
    else
      WaitForSingleObject(FStop, 10000);
  except
    on E: Exception do
      FError := E.ClassName + ': ' + E.Message;
  end;
  SetEvent(FReady);
  if FWindow <> 0 then
    DestroyWindow(FWindow);
end;

procedure TWindowWorker.AwaitReady;
begin
  if WaitForSingleObject(FReady, 5000) <> WAIT_OBJECT_0 then
  begin
    Writeln('FAIL: test window creation exceeded five seconds');
    Halt(1);
  end;
  Check(FError = '', 'isolated windows are created');
  Check(IsWindow(FWindow), 'test window remains alive');
end;

procedure TWindowWorker.Finish;
begin
  SetEvent(FStop);
  if WaitForSingleObject(Handle, 5000) <> WAIT_OBJECT_0 then
  begin
    Writeln('FAIL: isolated window thread exceeded five-second cleanup limit');
    Halt(1);
  end;
  WaitFor;
end;

procedure TInspectionWorker.Execute;
begin
  FResult := TDAIWindowService.IDEWindows(True, 100, 500, 300);
end;

destructor TInspectionWorker.Destroy;
begin
  FResult.Free;
  inherited;
end;

function TInspectionWorker.TakeResult: TJSONObject;
begin
  Result := FResult;
  FResult := nil;
end;

procedure ValidatePID(const AResult: TJSONObject; const AProcessId: DWORD);
var
  LWindows, LChildren: TJSONArray;
  LWindow, LChild: TJSONValue;
begin
  Check(JsonInteger(AResult, 'process_id') = AProcessId, 'snapshot uses the requested process ID');
  LWindows := TJSONArray(AResult.GetValue('windows'));
  for LWindow in LWindows do
  begin
    Check(JsonInteger(TJSONObject(LWindow), 'process_id') = AProcessId, 'every top-level window is PID-filtered');
    Check(Length(JsonString(TJSONObject(LWindow), 'handle')) = 2 + SizeOf(Pointer) * 2, 'HWND is a pointer-size hex string');
    LChildren := TJSONArray(TJSONObject(LWindow).GetValue('children'));
    if Assigned(LChildren) then
      for LChild in LChildren do
        Check(JsonInteger(TJSONObject(LChild), 'process_id') = AProcessId, 'every child window is PID-filtered');
  end;
end;

procedure TestLocalWindows;
var
  LRunning, LHung: TWindowWorker;
  LInspection: TInspectionWorker;
  LResult, LWindow: TJSONObject;
begin
  LRunning := TWindowWorker.Create(True);
  LHung := TWindowWorker.Create(False);
  try
    LRunning.Start;
    LHung.Start;
    LRunning.AwaitReady;
    LHung.AwaitReady;
    LResult := TDAIWindowService.TestProcessWindows(GetCurrentProcessId, True, 100, 500, 1000);
    try
      ValidatePID(LResult, GetCurrentProcessId);
      Check(JsonInteger(LResult, 'pointer_bits') = SizeOf(Pointer) * 8, 'reported pointer size matches executable');
      LWindow := FindHandle(LResult, LRunning.Window);
      Check(Assigned(LWindow), 'responsive top-level window is listed');
      Check(JsonString(LWindow, 'title') = 'DAI isolated window', 'responsive window caption is read');
      LWindow := FindHandle(LResult, LRunning.StaticControl);
      Check(Assigned(LWindow), 'responsive child control is listed');
      Check(JsonString(LWindow, 'title') = 'DAI isolated label', 'responsive static control text is read');
      LWindow := FindHandle(LResult, LRunning.PasswordControl);
      Check(Assigned(LWindow), 'password control metadata remains visible');
      Check(JsonString(LWindow, 'title') = '', 'password control text is omitted');
      Check(JsonString(LWindow, 'text_status') = 'input_or_sensitive_text_omitted', 'omitted input text is explicit');
      LWindow := FindHandle(LResult, LHung.Window);
      Check(Assigned(LWindow), 'non-responding window metadata is listed');
      Check(JsonString(LWindow, 'text_status') = 'unavailable', 'non-responding text read returns unavailable');
      Check(JsonInteger(LResult, 'elapsed_ms') < 1500, 'hung window does not exceed bounded snapshot time');
      Check(not LResult.ToJSON.Contains('test-only-secret'), 'snapshot never exposes input content');
    finally
      LResult.Free;
    end;
    TDAIWindowService.RegisterPermissionWindow(LRunning.Window);
    TDAIWindowService.RegisterPermissionWindow(LRunning.Window);
    try
      LResult := TDAIWindowService.TestProcessWindows(GetCurrentProcessId, True, 100, 500, 1000);
      try
        Check(not Assigned(FindHandle(LResult, LRunning.Window)), 'protected permission window is excluded');
        Check(not Assigned(FindHandle(LResult, LRunning.StaticControl)), 'protected permission child is excluded');
        Check(JsonInteger(LResult, 'excluded_permission_window_count') >= 1, 'protected exclusion is reported');
      finally
        LResult.Free;
      end;
    finally
      TDAIWindowService.UnregisterPermissionWindow(LRunning.Window);
    end;
    LResult := TDAIWindowService.TestProcessWindows(GetCurrentProcessId, False, 100, 500, 1000);
    try
      Check(Assigned(FindHandle(LResult, LRunning.Window)), 'unregistered permission HWND is listed again');
      Check(JsonInteger(LResult, 'control_count') = 0, 'children are optional');
    finally
      LResult.Free;
    end;
    LResult := TDAIWindowService.TestProcessWindows(GetCurrentProcessId, True, 1, 1, 1000);
    try
      Check(JsonInteger(LResult, 'window_count') <= 1, 'top-level window count is capped');
      Check(JsonInteger(LResult, 'control_count') <= 1, 'total child control count is capped');
      Check(JsonString(LResult, 'truncated') = 'true', 'quantity truncation is explicit');
    finally
      LResult.Free;
    end;
    LResult := TDAIWindowService.TestProcessWindows(GetCurrentProcessId, True, 10000, 10000, 1);
    try
      Check(JsonInteger(LResult, 'window_count') <= 100, 'unit enforces its hard window limit');
      Check(JsonInteger(LResult, 'control_count') <= 500, 'unit enforces its hard control limit');
      Check(JsonInteger(LResult, 'elapsed_ms') < 300, 'one-millisecond request remains bounded');
    finally
      LResult.Free;
    end;
    LInspection := TInspectionWorker.Create(True);
    try
      LInspection.Start;
      // Deliberately do not pump the main-thread queue while the native request runs.
      if WaitForSingleObject(LInspection.Handle, 2000) <> WAIT_OBJECT_0 then
      begin
        Writeln('FAIL: main-thread-unavailable snapshot exceeded two seconds');
        Halt(1);
      end;
      LInspection.WaitFor;
      LResult := LInspection.TakeResult;
      try
        Check(JsonString(LResult, 'available') = 'true', 'native IDE snapshot survives unavailable main thread');
        Check(JsonString(LResult, 'vcl_available') = 'false', 'VCL metadata timeout is explicit');
        Check(JsonString(LResult, 'vcl_reason') = 'main_thread_timeout', 'VCL query has a bounded queue wait');
        Check(JsonInteger(LResult, 'elapsed_ms') < 600, 'total snapshot budget includes the main-thread wait');
      finally
        LResult.Free;
      end;
      CheckSynchronize(0);
      Check(True, 'cancelled queue callback leaves no unsafe pending snapshot');
    finally
      LInspection.Free;
    end;
  finally
    LHung.Free;
    LRunning.Free;
  end;
end;

function FindVCLName(const AResult: TJSONObject; const AName: string): TJSONObject;
var
  LWindows, LChildren: TJSONArray;
  LWindow, LChild: TJSONValue;
  LMetadata: TJSONObject;
begin
  Result := nil;
  LWindows := TJSONArray(AResult.GetValue('windows'));
  for LWindow in LWindows do
  begin
    LMetadata := TJSONObject(TJSONObject(LWindow).GetValue('vcl'));
    if JsonString(LMetadata, 'name') = AName then
      Exit(TJSONObject(LWindow));
    LChildren := TJSONArray(TJSONObject(LWindow).GetValue('children'));
    if Assigned(LChildren) then
      for LChild in LChildren do
      begin
        LMetadata := TJSONObject(TJSONObject(LChild).GetValue('vcl'));
        if JsonString(LMetadata, 'name') = AName then
          Exit(TJSONObject(LChild));
      end;
  end;
end;

procedure TestVCLMetadata;
var
  LForm: TForm;
  LLabel: TLabel;
  LInput: TEdit;
  LResult, LControl, LMetadata: TJSONObject;
begin
  LForm := TForm.CreateNew(nil);
  try
    LForm.Name := 'WindowInspectionTestForm';
    LLabel := TLabel.Create(LForm);
    LLabel.Parent := LForm;
    LLabel.Name := 'WindowInspectionTestLabel';
    LLabel.Caption := 'DAI isolated graphic label';
    LInput := TEdit.Create(LForm);
    LInput.Parent := LForm;
    LInput.Name := 'WindowInspectionTestApiToken';
    LInput.Text := 'test-only-vcl-secret';
    Check(not LForm.HandleAllocated, 'isolated VCL form starts without an HWND');
    Check(not LInput.HandleAllocated, 'isolated VCL input starts without an HWND');
    LResult := TDAIWindowService.IDEWindows(True, 100, 500, 1000);
    try
      Check(JsonString(LResult, 'vcl_available') = 'true', 'main-thread VCL metadata is available');
      Check(Assigned(FindVCLName(LResult, LForm.Name)), 'VCL form metadata is merged');
      LControl := FindVCLName(LResult, LLabel.Name);
      Check(Assigned(LControl), 'graphic control without HWND is listed');
      LMetadata := TJSONObject(LControl.GetValue('vcl'));
      Check(JsonString(LMetadata, 'class_name') = 'TLabel', 'VCL control class is reported');
      Check(JsonString(LMetadata, 'handle_allocated') = 'false', 'graphic control has no allocated HWND');
      LControl := FindVCLName(LResult, LInput.Name);
      Check(Assigned(LControl), 'sensitive VCL input metadata remains available');
      Check(JsonString(LControl, 'title') = '', 'sensitive VCL input text is omitted');
      Check(not LResult.ToJSON.Contains('test-only-vcl-secret'), 'VCL getter-free snapshot omits token content');
      Check(not LForm.HandleAllocated, 'VCL metadata does not create a form HWND');
      Check(not LInput.HandleAllocated, 'VCL metadata does not create an input HWND');
    finally
      LResult.Free;
    end;
    // Deliberately allocate only this isolated test form to verify the real HWND protection contract.
    TDAIWindowService.RegisterPermissionWindow(LForm.Handle);
    try
      LResult := TDAIWindowService.IDEWindows(True, 100, 500, 1000);
      try
        Check(not Assigned(FindHandle(LResult, LForm.Handle)), 'protected VCL form HWND is excluded');
        Check(not Assigned(FindVCLName(LResult, LForm.Name)), 'VCL merge cannot reintroduce a protected form');
        Check(not Assigned(FindVCLName(LResult, LLabel.Name)), 'protected VCL graphic control is excluded');
        Check(not Assigned(FindVCLName(LResult, LInput.Name)), 'protected VCL input control is excluded');
      finally
        LResult.Free;
      end;
    finally
      TDAIWindowService.UnregisterPermissionWindow(LForm.Handle);
    end;
    LResult := TDAIWindowService.IDEWindows(True, 100, 500, 1000);
    try
      Check(Assigned(FindVCLName(LResult, LForm.Name)), 'VCL form appears after protection is removed');
      Check(JsonInteger(LResult, 'window_count') <= 100, 'native and VCL forms share the hard window limit');
      Check(JsonInteger(LResult, 'control_count') <= 500, 'native and VCL controls share the hard control limit');
    finally
      LResult.Free;
    end;
  finally
    LForm.Free;
  end;
end;

procedure ChildMode(const AReadyName, AStopName: string);
var
  LReady, LStop: THandle;
  LWorker: TWindowWorker;
begin
  if not AReadyName.StartsWith('Local\DAI.WindowTests.') or not AStopName.StartsWith('Local\DAI.WindowTests.') then
    raise EArgumentException.Create('Only isolated test event names are permitted.');
  LReady := OpenEvent(EVENT_MODIFY_STATE, False, PChar(AReadyName));
  LStop := OpenEvent(SYNCHRONIZE, False, PChar(AStopName));
  if (LReady = 0) or (LStop = 0) then
    RaiseLastOSError;
  try
    LWorker := TWindowWorker.Create(True);
    try
      LWorker.Start;
      LWorker.AwaitReady;
      SetEvent(LReady);
      WaitForSingleObject(LStop, 10000);
    finally
      LWorker.Free;
    end;
  finally
    CloseHandle(LReady);
    CloseHandle(LStop);
  end;
end;

procedure TestForeignProcess(const AExecutable: string);
var
  LGuid: TGUID;
  LReadyName, LStopName, LCommand: string;
  LReady, LStop: THandle;
  LStartup: TStartupInfo;
  LProcess: TProcessInformation;
  LResult: TJSONObject;
begin
  CreateGUID(LGuid);
  LReadyName := 'Local\DAI.WindowTests.' + GUIDToString(LGuid) + '.ready';
  LStopName := 'Local\DAI.WindowTests.' + GUIDToString(LGuid) + '.stop';
  LReady := CreateEvent(nil, True, False, PChar(LReadyName));
  LStop := CreateEvent(nil, True, False, PChar(LStopName));
  if (LReady = 0) or (LStop = 0) then
    RaiseLastOSError;
  try
    FillChar(LStartup, SizeOf(LStartup), 0);
    LStartup.cb := SizeOf(LStartup);
    LCommand := '"' + AExecutable + '" --child "' + LReadyName + '" "' + LStopName + '"';
    UniqueString(LCommand);
    if not CreateProcess(nil, PChar(LCommand), nil, nil, False, CREATE_NO_WINDOW, nil, nil, LStartup, LProcess) then
      RaiseLastOSError;
    try
      Check(WaitForSingleObject(LReady, 5000) = WAIT_OBJECT_0, 'isolated foreign process creates hidden windows');
      LResult := TDAIWindowService.TestProcessWindows(LProcess.dwProcessId, True, 100, 500, 1000);
      try
        ValidatePID(LResult, LProcess.dwProcessId);
        Check(JsonInteger(LResult, 'window_count') >= 1, 'foreign process top-level window is found');
        Check(JsonInteger(LResult, 'control_count') >= 2, 'foreign process child controls are found');
        Check(LResult.ToJSON.Contains('DAI isolated label'), 'foreign static text is read without pointer truncation');
        Check(not LResult.ToJSON.Contains('test-only-secret'), 'foreign input content is omitted');
      finally
        LResult.Free;
      end;
    finally
      SetEvent(LStop);
      if WaitForSingleObject(LProcess.hProcess, 5000) <> WAIT_OBJECT_0 then
      begin
        Writeln('FAIL: isolated child process exceeded cleanup limit');
        Halt(1);
      end;
      CloseHandle(LProcess.hThread);
      CloseHandle(LProcess.hProcess);
    end;
  finally
    CloseHandle(LReady);
    CloseHandle(LStop);
  end;
end;

begin
  try
    if (ParamCount = 3) and (ParamStr(1) = '--child') then
      ChildMode(ParamStr(2), ParamStr(3))
    else
    begin
      TestLocalWindows;
      TestVCLMetadata;
      if (ParamCount = 2) and (ParamStr(1) = '--peer') then
        TestForeignProcess(ParamStr(2))
      else
        TestForeignProcess(ParamStr(0));
      Writeln('OK: ', CheckCount, ' isolated window checks (', SizeOf(Pointer) * 8, '-bit)');
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
