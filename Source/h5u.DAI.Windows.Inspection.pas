unit h5u.DAI.Windows.Inspection;

interface

uses
  System.JSON,
  Winapi.Windows;

type
  TDAIWindowService = class sealed
  public
    class function IDEWindows(const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer): TJSONObject; static;
    class function DebuggerWindows(const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer): TJSONObject; static;
    class procedure RegisterPermissionWindow(const AHandle: HWND); static;
    class procedure UnregisterPermissionWindow(const AHandle: HWND); static;
    class function IsProtectedPermissionWindow(const AHandle: HWND): Boolean; static;
{$IFDEF DAI_WINDOW_TEST}
    class function TestProcessWindows(const AProcessId: DWORD; const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer): TJSONObject; static;
{$ENDIF}
  end;

implementation

uses
{$IFNDEF DAI_WINDOW_TEST}
  ToolsAPI,
{$ENDIF}
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ImgList,
  Winapi.CommCtrl,
  Winapi.Messages;

const
  CMaximumWindows = 100;
  CMaximumControls = 500;
  CMaximumTimeoutMs = 2000;
  CMessageTimeoutMs = 50;
  CMaximumTextChars = 2048;
  CMaximumPendingSnapshots = 32;

type
  TSnapshotKind = (skIDE, skDebugger);

  IWindowSnapshot = interface
    ['{9AAC6869-B0DF-4344-BC53-149651761AAC}']
    procedure Run;
    procedure Cancel;
    function Wait(const ATimeoutMs: Cardinal): Boolean;
    function TakeResult: TJSONObject;
  end;

  TWindowSnapshot = class(TInterfacedObject, IWindowSnapshot)
  private
    FKind: TSnapshotKind;
    FIncludeChildren: Boolean;
    FMaximumWindows: Integer;
    FMaximumControls: Integer;
    FDeadline: UInt64;
    FCancelled: Integer;
    FEvent: TEvent;
    FLock: TObject;
    FResult: TJSONObject;
    function Expired: Boolean;
    function ReadIDE: TJSONObject;
    function ReadDebugger: TJSONObject;
  public
    constructor Create(const AKind: TSnapshotKind; const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls: Integer; const ADeadline: UInt64);
    destructor Destroy; override;
    procedure Run;
    procedure Cancel;
    function Wait(const ATimeoutMs: Cardinal): Boolean;
    function TakeResult: TJSONObject;
  end;

  TSnapshotDispatcher = class
  private
    FLock: TObject;
    FJobs: TList<IWindowSnapshot>;
  public
    constructor Create;
    destructor Destroy; override;
    function Enqueue(const AJob: IWindowSnapshot): Boolean;
    procedure Remove(const AJob: IWindowSnapshot);
    procedure DispatchQueued;
  end;

  TNativeScan = class
  private
    FProcessId: DWORD;
    FIncludeChildren: Boolean;
    FMaximumWindows: Integer;
    FMaximumControls: Integer;
    FDeadline: UInt64;
    FStarted: UInt64;
    FWindows: TJSONArray;
    FChildren: TJSONArray;
    FControlCount: Integer;
    FUnavailableCount: Integer;
    FExcludedCount: Integer;
    FTruncated: Boolean;
    FError: string;
    function Expired: Boolean;
    function ProtectedWindow(const AHandle: HWND): Boolean;
    function WindowJson(const AHandle: HWND; const AChild: Boolean): TJSONObject;
    function IncludeWindow(const AHandle: HWND; const AChild: Boolean): Boolean;
    procedure MergeVCL(const ASnapshot: TJSONObject);
  public
    constructor Create(const AProcessId: DWORD; const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer; const AStarted: UInt64);
    destructor Destroy; override;
    function Execute(const ASnapshot: TJSONObject = nil): TJSONObject;
  end;

var
  GPermissionLock: TObject;
  GPermissionWindows: TList<HWND>;
  GDispatcher: TSnapshotDispatcher;

function Bounded(const AValue, AMinimum, AMaximum: Integer): Integer;
begin
  Result := AValue;
  if Result < AMinimum then
    Result := AMinimum;
  if Result > AMaximum then
    Result := AMaximum;
end;

function HandleText(const AHandle: HWND): string;
begin
  Result := '0x' + IntToHex(NativeUInt(AHandle), SizeOf(Pointer) * 2);
end;

function ParsedHandle(const AValue: string): HWND;
var
  LValue: UInt64;
begin
  Result := 0;
  if not AValue.StartsWith('0x') then
    Exit;
  if TryStrToUInt64('$' + Copy(AValue, 3, MaxInt), LValue) then
    if LValue <= High(NativeUInt) then
      Result := HWND(NativeUInt(LValue));
end;

function IsPermissionWindow(const AHandle: HWND): Boolean;
var
  LProtected: HWND;
begin
  Result := False;
  if AHandle = 0 then
    Exit;
  System.TMonitor.Enter(GPermissionLock);
  try
    for LProtected in GPermissionWindows do
      if (AHandle = LProtected) or IsChild(LProtected, AHandle) then
        Exit(True);
  finally
    System.TMonitor.Exit(GPermissionLock);
  end;
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

function JsonBool(const AObject: TJSONObject; const AName: string): Boolean;
begin
  Result := SameText(JsonString(AObject, AName), 'true');
end;

function SensitiveName(const AName: string): Boolean;
var
  LName: string;
begin
  LName := LowerCase(AName);
  Result := LName.Contains('password') or LName.Contains('passwd') or LName.Contains('token') or LName.Contains('secret') or
    LName.Contains('credential') or LName.Contains('apikey') or LName.Contains('api_key');
end;

function SnapshotUnavailable(const AReason: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('available', TJSONBool.Create(False));
  Result.AddPair('reason', AReason);
end;

constructor TWindowSnapshot.Create(const AKind: TSnapshotKind; const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls: Integer; const ADeadline: UInt64);
begin
  inherited Create;
  FKind := AKind;
  FIncludeChildren := AIncludeChildren;
  FMaximumWindows := AMaximumWindows;
  FMaximumControls := AMaximumControls;
  FDeadline := ADeadline;
  FLock := TObject.Create;
  FEvent := TEvent.Create(nil, True, False, '');
end;

destructor TWindowSnapshot.Destroy;
begin
  FResult.Free;
  FEvent.Free;
  FLock.Free;
  inherited;
end;

function TWindowSnapshot.Expired: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0) or (GetTickCount64 >= FDeadline);
end;

function RectangleJson(const ARect: TRect): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('left', TJSONNumber.Create(ARect.Left));
  Result.AddPair('top', TJSONNumber.Create(ARect.Top));
  Result.AddPair('right', TJSONNumber.Create(ARect.Right));
  Result.AddPair('bottom', TJSONNumber.Create(ARect.Bottom));
end;

procedure AddToolButtonDiagnostics(const AButton: TToolButton; const AJson: TJSONObject);
var
  LToolbar: TToolBar;
  LLayout, LNative: TJSONObject;
  LHandle: HWND;
  LNativeImages: HIMAGELIST;
  LCount: LRESULT;
  LIndex: Integer;
  LButton: TTBButton;
  LClientRect, LItemRect: TRect;
begin
  AJson.AddPair('button_index', TJSONNumber.Create(AButton.Index));
  AJson.AddPair('bounds', RectangleJson(AButton.BoundsRect));
  if not (AButton.Parent is TToolBar) then
    Exit;
  LToolbar := TToolBar(AButton.Parent);
  if csDestroying in LToolbar.ComponentState then
    Exit;
  LLayout := TJSONObject.Create;
  AJson.AddPair('parent_toolbar', LLayout);
  LLayout.AddPair('bounds', RectangleJson(LToolbar.BoundsRect));
  LLayout.AddPair('visible', TJSONBool.Create(LToolbar.Visible));
  LLayout.AddPair('showing', TJSONBool.Create(LToolbar.Showing));
  LLayout.AddPair('auto_size', TJSONBool.Create(LToolbar.AutoSize));
  LLayout.AddPair('wrapable', TJSONBool.Create(LToolbar.Wrapable));
  LLayout.AddPair('hide_clipped_buttons', TJSONBool.Create(LToolbar.HideClippedButtons));
  LLayout.AddPair('handle_allocated', TJSONBool.Create(LToolbar.HandleAllocated));
  if Assigned(LToolbar.Images) then
  begin
    LLayout.AddPair('images_handle_allocated', TJSONBool.Create(LToolbar.Images.HandleAllocated));
    // TCustomImageList.GetCount checks HandleAllocated and returns zero otherwise.
    LLayout.AddPair('images_count', TJSONNumber.Create(LToolbar.Images.Count));
  end
  else
  begin
    LLayout.AddPair('images_handle_allocated', TJSONBool.Create(False));
    LLayout.AddPair('images_count', TJSONNumber.Create(0));
  end;
  LNative := TJSONObject.Create;
  LLayout.AddPair('native', LNative);
  if not LToolbar.HandleAllocated then
  begin
    // VCL ClientRect/ClientWidth/ClientHeight would invoke HandleNeeded here.
    LLayout.AddPair('client_rect', TJSONNull.Create);
    LLayout.AddPair('client_width', TJSONNull.Create);
    LLayout.AddPair('client_height', TJSONNull.Create);
    LNative.AddPair('available', TJSONBool.Create(False));
    LNative.AddPair('reason', 'handle_not_allocated');
    Exit;
  end;
  LHandle := LToolbar.Handle;
  if not Winapi.Windows.GetClientRect(LHandle, LClientRect) then
  begin
    LNative.AddPair('available', TJSONBool.Create(False));
    LNative.AddPair('reason', 'client_rect_unavailable');
    Exit;
  end;
  LLayout.AddPair('client_rect', RectangleJson(LClientRect));
  LLayout.AddPair('client_width', TJSONNumber.Create(LClientRect.Right - LClientRect.Left));
  LLayout.AddPair('client_height', TJSONNumber.Create(LClientRect.Bottom - LClientRect.Top));
  LCount := SendMessage(LHandle, TB_BUTTONCOUNT, 0, 0);
  if (LCount < 0)
{$IFDEF CPUX64}
    or (LCount > High(Integer))
{$ENDIF}
  then
  begin
    LNative.AddPair('available', TJSONBool.Create(False));
    LNative.AddPair('reason', 'invalid_button_count');
    Exit;
  end;
  LNative.AddPair('button_count', TJSONNumber.Create(Integer(LCount)));
  LNativeImages := HIMAGELIST(SendMessage(LHandle, TB_GETIMAGELIST, 0, 0));
  LNative.AddPair('has_image_list', TJSONBool.Create(LNativeImages <> 0));
  if LNativeImages <> 0 then
    LNative.AddPair('images_count', TJSONNumber.Create(ImageList_GetImageCount(LNativeImages)))
  else
    LNative.AddPair('images_count', TJSONNumber.Create(0));
  LIndex := AButton.Index;
  if (LIndex < 0) or (LIndex >= LCount) then
  begin
    LNative.AddPair('available', TJSONBool.Create(False));
    LNative.AddPair('reason', 'index_outside_native_buttons');
    Exit;
  end;
  FillChar(LButton, SizeOf(LButton), 0);
  if SendMessage(LHandle, TB_GETBUTTON, WPARAM(LIndex), LPARAM(@LButton)) = 0 then
  begin
    LNative.AddPair('available', TJSONBool.Create(False));
    LNative.AddPair('reason', 'native_button_unavailable');
    Exit;
  end;
  LNative.AddPair('available', TJSONBool.Create(True));
  // Never expose or dereference dwData, which is the VCL control pointer.
  LNative.AddPair('identity_matches', TJSONBool.Create(LButton.dwData = NativeUInt(Pointer(AButton))));
  LNative.AddPair('state', TJSONNumber.Create(LButton.fsState));
  LNative.AddPair('hidden', TJSONBool.Create((LButton.fsState and TBSTATE_HIDDEN) <> 0));
  LNative.AddPair('image_index', TJSONNumber.Create(LButton.iBitmap));
  if SendMessage(LHandle, TB_GETITEMRECT, WPARAM(LIndex), LPARAM(@LItemRect)) <> 0 then
  begin
    LNative.AddPair('item_rect', RectangleJson(LItemRect));
    LNative.AddPair('clipped', TJSONBool.Create((LItemRect.Left < LClientRect.Left) or (LItemRect.Top < LClientRect.Top) or
      (LItemRect.Right > LClientRect.Right) or (LItemRect.Bottom > LClientRect.Bottom)));
  end
  else
  begin
    LNative.AddPair('item_rect', TJSONNull.Create);
    LNative.AddPair('clipped', TJSONNull.Create);
  end;
end;

function TWindowSnapshot.ReadIDE: TJSONObject;
var
  LForms: TJSONArray;
  LForm: TCustomForm;
  LFormJson: TJSONObject;
  LControls: TJSONArray;
  LCount, LIndex: Integer;
  LFormHandle: HWND;
  LTruncated, LFormSensitive: Boolean;

  procedure ReadControls(const AParent: TWinControl; const ADepth: Integer; const AParentSensitive: Boolean);
  var
    LChildIndex: Integer;
    LControl: TControl;
    LControlJson: TJSONObject;
    LHandle: HWND;
    LSensitive: Boolean;
  begin
    if ADepth > 32 then
    begin
      LTruncated := True;
      Exit;
    end;
    for LChildIndex := 0 to AParent.ControlCount - 1 do
    begin
      if Expired or (LCount >= FMaximumControls) then
      begin
        LTruncated := True;
        Exit;
      end;
      LControl := AParent.Controls[LChildIndex];
      if csDestroying in LControl.ComponentState then
        Continue;
      LHandle := 0;
      if LControl is TWinControl then
        if TWinControl(LControl).HandleAllocated then
          LHandle := TWinControl(LControl).Handle;
      if IsPermissionWindow(LHandle) then
        Continue;
      LSensitive := AParentSensitive or SensitiveName(LControl.Name) or SensitiveName(LControl.ClassName);
      LControlJson := TJSONObject.Create;
      LControlJson.AddPair('handle', HandleText(LHandle));
      LControlJson.AddPair('name', LControl.Name);
      LControlJson.AddPair('class_name', LControl.ClassName);
      LControlJson.AddPair('visible', TJSONBool.Create(LControl.Visible));
      LControlJson.AddPair('handle_allocated', TJSONBool.Create(LHandle <> 0));
      LControlJson.AddPair('sensitive', TJSONBool.Create(LSensitive));
      LControlJson.AddPair('depth', TJSONNumber.Create(ADepth));
      if Assigned(LControl.Parent) then
      begin
        LControlJson.AddPair('parent_name', LControl.Parent.Name);
        LControlJson.AddPair('parent_class_name', LControl.Parent.ClassName);
      end;
      if Assigned(LControl.Owner) then
      begin
        LControlJson.AddPair('owner_name', LControl.Owner.Name);
        LControlJson.AddPair('owner_class_name', LControl.Owner.ClassName);
      end;
      if (LControl is TToolButton) and not LSensitive then
      begin
        AddToolButtonDiagnostics(TToolButton(LControl), LControlJson);
        LControlJson.AddPair('button_style', TJSONNumber.Create(Ord(TToolButton(LControl).Style)));
        LControlJson.AddPair('image_index', TJSONNumber.Create(TToolButton(LControl).ImageIndex));
        LControlJson.AddPair('image_name', TToolButton(LControl).ImageName);
        LControlJson.AddPair('has_dropdown_menu', TJSONBool.Create(Assigned(TToolButton(LControl).DropdownMenu)));
        if Assigned(TToolButton(LControl).Action) then
        begin
          LControlJson.AddPair('action_name', TToolButton(LControl).Action.Name);
          LControlJson.AddPair('action_class_name', TToolButton(LControl).Action.ClassName);
        end;
      end;
      LControls.AddElement(LControlJson);
      Inc(LCount);
      if LControl is TWinControl then
        ReadControls(TWinControl(LControl), ADepth + 1, LSensitive);
    end;
  end;

begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('available', TJSONBool.Create(True));
    LForms := TJSONArray.Create;
    Result.AddPair('forms', LForms);
    LCount := 0;
    LTruncated := False;
    for LIndex := 0 to Screen.CustomFormCount - 1 do
    begin
      if Expired or (LForms.Count >= FMaximumWindows) then
      begin
        LTruncated := True;
        Break;
      end;
      LForm := Screen.CustomForms[LIndex];
      if csDestroying in LForm.ComponentState then
        Continue;
      LFormHandle := 0;
      if LForm.HandleAllocated then
        LFormHandle := LForm.Handle;
      if IsPermissionWindow(LFormHandle) then
        Continue;
      LFormJson := TJSONObject.Create;
      LFormJson.AddPair('handle', HandleText(LFormHandle));
      LFormJson.AddPair('name', LForm.Name);
      LFormJson.AddPair('class_name', LForm.ClassName);
      LFormJson.AddPair('visible', TJSONBool.Create(TControl(LForm).Visible));
      LFormJson.AddPair('modal', TJSONBool.Create(fsModal in LForm.FormState));
      LFormJson.AddPair('active', TJSONBool.Create(Screen.ActiveCustomForm = LForm));
      LFormSensitive := SensitiveName(LForm.Name) or SensitiveName(LForm.ClassName);
      LFormJson.AddPair('sensitive', TJSONBool.Create(LFormSensitive));
      LForms.AddElement(LFormJson);
      LControls := TJSONArray.Create;
      LFormJson.AddPair('controls', LControls);
      if FIncludeChildren then
        ReadControls(LForm, 0, LFormSensitive);
    end;
    Result.AddPair('truncated', TJSONBool.Create(LTruncated));
  except
    Result.Free;
    raise;
  end;
end;

function TWindowSnapshot.ReadDebugger: TJSONObject;
{$IFNDEF DAI_WINDOW_TEST}
var
  LDebugger: IOTADebuggerServices;
  LProcess: IOTAProcess;
{$ENDIF}
begin
{$IFDEF DAI_WINDOW_TEST}
  Result := SnapshotUnavailable('debugger_unavailable_in_isolated_test');
{$ELSE}
  if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
    Exit(SnapshotUnavailable('debugger_services_unavailable'));
  LProcess := LDebugger.CurrentProcess;
  if not Assigned(LProcess) then
    Exit(SnapshotUnavailable('no_current_debugger_process'));
  Result := TJSONObject.Create;
  try
    Result.AddPair('available', TJSONBool.Create(True));
    Result.AddPair('process_id', TJSONNumber.Create(Int64(LProcess.OSProcessId)));
    Result.AddPair('executable', LProcess.ExeName);
    Result.AddPair('process_state', LProcess.State);
    Result.AddPair('stopped', TJSONBool.Create(LProcess.ProcessState in [psStopped, psFault, psResFault, psException]));
  except
    Result.Free;
    raise;
  end;
{$ENDIF}
end;

procedure TWindowSnapshot.Run;
var
  LResult: TJSONObject;
begin
  if Expired then
  begin
    FEvent.SetEvent;
    Exit;
  end;
  LResult := nil;
  try
    try
      if FKind = skIDE then
        LResult := ReadIDE
      else
        LResult := ReadDebugger;
    except
      LResult.Free;
      LResult := SnapshotUnavailable('main_thread_snapshot_failed');
    end;
    System.TMonitor.Enter(FLock);
    try
      if not Expired then
      begin
        FResult := LResult;
        LResult := nil;
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
  finally
    LResult.Free;
    FEvent.SetEvent;
  end;
end;

procedure TWindowSnapshot.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TWindowSnapshot.Wait(const ATimeoutMs: Cardinal): Boolean;
begin
  Result := FEvent.WaitFor(ATimeoutMs) = wrSignaled;
end;

function TWindowSnapshot.TakeResult: TJSONObject;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FResult;
    FResult := nil;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

constructor TSnapshotDispatcher.Create;
begin
  inherited;
  FLock := TObject.Create;
  FJobs := TList<IWindowSnapshot>.Create;
end;

destructor TSnapshotDispatcher.Destroy;
var
  LJob: IWindowSnapshot;
begin
  TThread.RemoveQueuedEvents(nil, DispatchQueued);
  for LJob in FJobs do
    LJob.Cancel;
  FJobs.Free;
  FLock.Free;
  inherited;
end;

function TSnapshotDispatcher.Enqueue(const AJob: IWindowSnapshot): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FJobs.Count < CMaximumPendingSnapshots;
    if Result then
    begin
      FJobs.Add(AJob);
      TThread.ForceQueue(nil, DispatchQueued);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TSnapshotDispatcher.Remove(const AJob: IWindowSnapshot);
begin
  System.TMonitor.Enter(FLock);
  try
    FJobs.Remove(AJob);
    if FJobs.Count = 0 then
      TThread.RemoveQueuedEvents(nil, DispatchQueued);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TSnapshotDispatcher.DispatchQueued;
var
  LJob: IWindowSnapshot;
begin
  LJob := nil;
  System.TMonitor.Enter(FLock);
  try
    if FJobs.Count > 0 then
    begin
      LJob := FJobs[0];
      FJobs.Delete(0);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  if Assigned(LJob) then
    LJob.Run;
end;

function MainThreadSnapshot(const AKind: TSnapshotKind; const AIncludeChildren: Boolean;
  const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer; const AStarted: UInt64): TJSONObject;
var
  LJob: IWindowSnapshot;
  LWaitMs: Cardinal;
begin
  LJob := TWindowSnapshot.Create(AKind, AIncludeChildren, AMaximumWindows, AMaximumControls, AStarted + UInt64(ATimeoutMs));
  if GetCurrentThreadId = MainThreadID then
    LJob.Run
  else
  begin
    if not GDispatcher.Enqueue(LJob) then
      Exit(SnapshotUnavailable('main_thread_busy'));
    // Leave most of the total budget for native enumeration, even while the IDE is blocked.
    LWaitMs := Cardinal(Bounded(ATimeoutMs div 4, 1, 250));
    if not LJob.Wait(LWaitMs) then
    begin
      LJob.Cancel;
      GDispatcher.Remove(LJob);
      Exit(SnapshotUnavailable('main_thread_timeout'));
    end;
  end;
  Result := LJob.TakeResult;
  if not Assigned(Result) then
    Result := SnapshotUnavailable('main_thread_timeout');
end;

constructor TNativeScan.Create(const AProcessId: DWORD; const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer; const AStarted: UInt64);
begin
  inherited Create;
  FProcessId := AProcessId;
  FIncludeChildren := AIncludeChildren;
  FMaximumWindows := Bounded(AMaximumWindows, 1, CMaximumWindows);
  FMaximumControls := Bounded(AMaximumControls, 0, CMaximumControls);
  FStarted := AStarted;
  FDeadline := AStarted + UInt64(Bounded(ATimeoutMs, 1, CMaximumTimeoutMs));
  FWindows := TJSONArray.Create;
end;

destructor TNativeScan.Destroy;
begin
  FWindows.Free;
  inherited;
end;

function TNativeScan.Expired: Boolean;
begin
  Result := GetTickCount64 >= FDeadline;
  if Result then
    FTruncated := True;
end;

function TNativeScan.ProtectedWindow(const AHandle: HWND): Boolean;
begin
  Result := IsPermissionWindow(AHandle);
end;

function TNativeScan.WindowJson(const AHandle: HWND; const AChild: Boolean): TJSONObject;
var
  LClassBuffer: array[0..255] of Char;
  LTextBuffer: array[0..CMaximumTextChars] of Char;
  LClassName, LTextStatus: string;
  LThreadId, LProcessId: DWORD;
  LMessageResult: DWORD_PTR;
  LTimeout: Cardinal;
  LNow: UInt64;
  LStyle: NativeInt;
  LRect: TRect;
  LReadText: Boolean;
begin
  Result := nil;
  LProcessId := 0;
  LThreadId := GetWindowThreadProcessId(AHandle, @LProcessId);
  if (LThreadId = 0) or (LProcessId <> FProcessId) or ProtectedWindow(AHandle) then
    Exit;
  FillChar(LClassBuffer, SizeOf(LClassBuffer), 0);
  GetClassName(AHandle, LClassBuffer, Length(LClassBuffer));
  LClassName := string(LClassBuffer);
  FillChar(LTextBuffer, SizeOf(LTextBuffer), 0);
  LTextStatus := 'available';
  LStyle := GetWindowLongPtr(AHandle, GWL_STYLE);
  LReadText := (LClassName <> '') and not SensitiveName(LClassName);
  // Input text may contain credentials even when the control does not use ES_PASSWORD.
  if LowerCase(LClassName).Contains('edit') or LowerCase(LClassName).Contains('combo') or
    LowerCase(LClassName).Contains('memo') or LowerCase(LClassName).Contains('rich') then
    LReadText := False;
  if AChild and ((LStyle and ES_PASSWORD) <> 0) then
    LReadText := False;
  if SameText(LClassName, 'STATIC') and ((LStyle and SS_TYPEMASK) in [SS_ICON, SS_BITMAP, SS_ENHMETAFILE]) then
    LReadText := False;
  if not LReadText then
    LTextStatus := 'input_or_sensitive_text_omitted'
  else if LProcessId <> GetCurrentProcessId then
  begin
    if not AChild then
      GetWindowTextW(AHandle, LTextBuffer, Length(LTextBuffer))
    else
      LTextStatus := 'pending';
  end
  else if LThreadId = GetCurrentThreadId then
    LTextStatus := 'same_thread_text_omitted'
  else
    LTextStatus := 'pending';
  if LTextStatus = 'pending' then
  begin
    LNow := GetTickCount64;
    if LNow >= FDeadline then
    begin
      FTruncated := True;
      LTextStatus := 'deadline_exceeded'
    end
    else
    begin
      LTimeout := Cardinal(FDeadline - LNow);
      if LTimeout > CMessageTimeoutMs then
        LTimeout := CMessageTimeoutMs;
      if LTimeout = 0 then
        LTimeout := 1;
      LMessageResult := 0;
      if SendMessageTimeoutW(AHandle, WM_GETTEXT, Length(LTextBuffer), LPARAM(@LTextBuffer[0]),
        SMTO_ABORTIFHUNG or SMTO_BLOCK or SMTO_ERRORONEXIT, LTimeout, @LMessageResult) = 0 then
        LTextStatus := 'unavailable'
      else
        LTextStatus := 'available';
    end;
  end;
  // HWNDs may disappear or be recycled during a snapshot; discard an inconsistent record.
  LProcessId := 0;
  if (GetWindowThreadProcessId(AHandle, @LProcessId) <> LThreadId) or (LProcessId <> FProcessId) or ProtectedWindow(AHandle) then
    Exit;
  if LTextStatus <> 'available' then
    Inc(FUnavailableCount);
  Result := TJSONObject.Create;
  Result.AddPair('kind', 'native');
  Result.AddPair('handle', HandleText(AHandle));
  Result.AddPair('process_id', TJSONNumber.Create(Int64(LProcessId)));
  Result.AddPair('thread_id', TJSONNumber.Create(Int64(LThreadId)));
  Result.AddPair('class_name', LClassName);
  if LTextStatus = 'available' then
    Result.AddPair('title', string(LTextBuffer))
  else
    Result.AddPair('title', '');
  Result.AddPair('text_status', LTextStatus);
  Result.AddPair('visible', TJSONBool.Create(IsWindowVisible(AHandle)));
  Result.AddPair('enabled', TJSONBool.Create(IsWindowEnabled(AHandle)));
  Result.AddPair('owner_handle', HandleText(GetWindow(AHandle, GW_OWNER)));
  Result.AddPair('parent_handle', HandleText(GetParent(AHandle)));
  if GetWindowRect(AHandle, LRect) then
  begin
    Result.AddPair('left', TJSONNumber.Create(LRect.Left));
    Result.AddPair('top', TJSONNumber.Create(LRect.Top));
    Result.AddPair('width', TJSONNumber.Create(LRect.Width));
    Result.AddPair('height', TJSONNumber.Create(LRect.Height));
  end;
  Result.AddPair('text_truncated', TJSONBool.Create(StrLen(LTextBuffer) = CMaximumTextChars));
end;

function EnumChildren(const AHandle: HWND; const AParameter: LPARAM): BOOL; stdcall;
begin
  Result := TNativeScan(Pointer(AParameter)).IncludeWindow(AHandle, True);
end;

function EnumTopLevel(const AHandle: HWND; const AParameter: LPARAM): BOOL; stdcall;
begin
  Result := TNativeScan(Pointer(AParameter)).IncludeWindow(AHandle, False);
end;

function TNativeScan.IncludeWindow(const AHandle: HWND; const AChild: Boolean): Boolean;
var
  LProcessId: DWORD;
  LJson: TJSONObject;
begin
  Result := not Expired;
  if not Result then
    Exit;
  LProcessId := 0;
  if (GetWindowThreadProcessId(AHandle, @LProcessId) = 0) or (LProcessId <> FProcessId) then
    Exit;
  if ProtectedWindow(AHandle) then
  begin
    Inc(FExcludedCount);
    Exit;
  end;
  if AChild then
  begin
    if FControlCount >= FMaximumControls then
    begin
      FTruncated := True;
      Exit(False);
    end;
  end
  else if FWindows.Count >= FMaximumWindows then
  begin
    FTruncated := True;
    Exit(False);
  end;
  try
    LJson := WindowJson(AHandle, AChild);
    if not Assigned(LJson) then
      Exit;
    if AChild then
    begin
      FChildren.AddElement(LJson);
      Inc(FControlCount);
    end
    else
    begin
      FWindows.AddElement(LJson);
      if FIncludeChildren then
      begin
        FChildren := TJSONArray.Create;
        LJson.AddPair('children', FChildren);
        EnumChildWindows(AHandle, @EnumChildren, LPARAM(Self));
      end;
    end;
  except
    // Never unwind a Delphi exception through a Windows enumeration callback.
    FError := 'native_window_snapshot_failed';
    FTruncated := True;
    Result := False;
  end;
end;

function FindHandle(const AItems: TJSONArray; const AHandle: string): TJSONObject;
var
  LItem: TJSONValue;
begin
  Result := nil;
  if not Assigned(AItems) or (AHandle = HandleText(0)) then
    Exit;
  for LItem in AItems do
    if (LItem is TJSONObject) and (JsonString(TJSONObject(LItem), 'handle') = AHandle) then
      Exit(TJSONObject(LItem));
end;

procedure TNativeScan.MergeVCL(const ASnapshot: TJSONObject);
var
  LForms, LControls, LChildren: TJSONArray;
  LFormValue, LControlValue: TJSONValue;
  LForm, LControl, LWindow, LChild, LMetadata: TJSONObject;
  LPair: TJSONPair;
begin
  if not Assigned(ASnapshot) or not JsonBool(ASnapshot, 'available') then
    Exit;
  LForms := TJSONArray(ASnapshot.GetValue('forms'));
  if not Assigned(LForms) then
    Exit;
  if JsonBool(ASnapshot, 'truncated') then
    FTruncated := True;
  for LFormValue in LForms do
  begin
    if Expired then
      Exit;
    LForm := TJSONObject(LFormValue);
    if IsPermissionWindow(ParsedHandle(JsonString(LForm, 'handle'))) then
    begin
      Inc(FExcludedCount);
      Continue;
    end;
    LWindow := FindHandle(FWindows, JsonString(LForm, 'handle'));
    if not Assigned(LWindow) then
    begin
      if FWindows.Count >= FMaximumWindows then
      begin
        FTruncated := True;
        Continue;
      end;
      LWindow := TJSONObject.Create;
      LWindow.AddPair('kind', 'vcl_form');
      LWindow.AddPair('handle', JsonString(LForm, 'handle'));
      LWindow.AddPair('process_id', TJSONNumber.Create(Int64(FProcessId)));
      LWindow.AddPair('title', '');
      LWindow.AddPair('text_status', 'no_native_text_snapshot');
      FWindows.AddElement(LWindow);
    end;
    LMetadata := TJSONObject.Create;
    for LPair in LForm do
      if not SameText(LPair.JsonString.Value, 'controls') then
        LMetadata.AddPair(TJSONPair(LPair.Clone));
    LWindow.AddPair('vcl', LMetadata);
    if JsonBool(LForm, 'sensitive') then
    begin
      LWindow.RemovePair('title').Free;
      LWindow.AddPair('title', '');
      LWindow.RemovePair('text_status').Free;
      LWindow.AddPair('text_status', 'input_or_sensitive_text_omitted');
    end;
    if not FIncludeChildren then
      Continue;
    LChildren := TJSONArray(LWindow.GetValue('children'));
    if not Assigned(LChildren) then
    begin
      LChildren := TJSONArray.Create;
      LWindow.AddPair('children', LChildren);
    end;
    LControls := TJSONArray(LForm.GetValue('controls'));
    for LControlValue in LControls do
    begin
      if Expired then
        Exit;
      LControl := TJSONObject(LControlValue);
      if IsPermissionWindow(ParsedHandle(JsonString(LControl, 'handle'))) then
        Continue;
      LChild := FindHandle(LChildren, JsonString(LControl, 'handle'));
      if not Assigned(LChild) then
      begin
        if FControlCount >= FMaximumControls then
        begin
          FTruncated := True;
          Continue;
        end;
        LChild := TJSONObject.Create;
        LChild.AddPair('kind', 'vcl_control');
        LChild.AddPair('handle', JsonString(LControl, 'handle'));
        LChild.AddPair('title', '');
        LChild.AddPair('text_status', 'no_native_text_snapshot');
        LChildren.AddElement(LChild);
        Inc(FControlCount);
      end;
      if JsonBool(LControl, 'sensitive') then
      begin
        LChild.RemovePair('title').Free;
        LChild.AddPair('title', '');
        LChild.RemovePair('text_status').Free;
        LChild.AddPair('text_status', 'input_or_sensitive_text_omitted');
      end;
      LChild.AddPair('vcl', TJSONValue(LControl.Clone));
    end;
  end;
end;

function TNativeScan.Execute(const ASnapshot: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('available', TJSONBool.Create(FProcessId <> 0));
    Result.AddPair('process_id', TJSONNumber.Create(Int64(FProcessId)));
    if FProcessId <> 0 then
    begin
      EnumWindows(@EnumTopLevel, LPARAM(Self));
      MergeVCL(ASnapshot);
    end;
    Result.AddPair('windows', FWindows);
    FWindows := nil;
    Result.AddPair('window_count', TJSONNumber.Create(TJSONArray(Result.GetValue('windows')).Count));
    Result.AddPair('control_count', TJSONNumber.Create(FControlCount));
    Result.AddPair('unavailable_text_count', TJSONNumber.Create(FUnavailableCount));
    Result.AddPair('excluded_permission_window_count', TJSONNumber.Create(FExcludedCount));
    Result.AddPair('truncated', TJSONBool.Create(FTruncated));
    Result.AddPair('elapsed_ms', TJSONNumber.Create(Int64(GetTickCount64 - FStarted)));
    Result.AddPair('message_timeout_ms', TJSONNumber.Create(CMessageTimeoutMs));
    Result.AddPair('pointer_bits', TJSONNumber.Create(SizeOf(Pointer) * 8));
    if FError <> '' then
      Result.AddPair('reason', FError);
  except
    Result.Free;
    raise;
  end;
end;

class function TDAIWindowService.IsProtectedPermissionWindow(const AHandle: HWND): Boolean;
begin
  Result := IsPermissionWindow(AHandle);
end;

class procedure TDAIWindowService.RegisterPermissionWindow(const AHandle: HWND);
begin
  if AHandle = 0 then
    Exit;
  System.TMonitor.Enter(GPermissionLock);
  try
    if not GPermissionWindows.Contains(AHandle) then
      GPermissionWindows.Add(AHandle);
  finally
    System.TMonitor.Exit(GPermissionLock);
  end;
end;

class procedure TDAIWindowService.UnregisterPermissionWindow(const AHandle: HWND);
begin
  System.TMonitor.Enter(GPermissionLock);
  try
    GPermissionWindows.Remove(AHandle);
  finally
    System.TMonitor.Exit(GPermissionLock);
  end;
end;

class function TDAIWindowService.IDEWindows(const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer): TJSONObject;
var
  LStarted: UInt64;
  LSnapshot: TJSONObject;
  LScan: TNativeScan;
  LTimeoutMs: Integer;
begin
  LStarted := GetTickCount64;
  LTimeoutMs := Bounded(ATimeoutMs, 1, CMaximumTimeoutMs);
  LSnapshot := MainThreadSnapshot(skIDE, AIncludeChildren, Bounded(AMaximumWindows, 1, CMaximumWindows),
    Bounded(AMaximumControls, 0, CMaximumControls), LTimeoutMs, LStarted);
  try
    LScan := TNativeScan.Create(GetCurrentProcessId, AIncludeChildren, AMaximumWindows, AMaximumControls, LTimeoutMs, LStarted);
    try
      Result := LScan.Execute(LSnapshot);
      Result.AddPair('scope', 'ide');
      Result.AddPair('vcl_available', TJSONBool.Create(JsonBool(LSnapshot, 'available')));
      if not JsonBool(LSnapshot, 'available') then
        Result.AddPair('vcl_reason', JsonString(LSnapshot, 'reason'));
    finally
      LScan.Free;
    end;
  finally
    LSnapshot.Free;
  end;
end;

class function TDAIWindowService.DebuggerWindows(const AIncludeChildren: Boolean; const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer): TJSONObject;
var
  LStarted: UInt64;
  LSnapshot: TJSONObject;
  LScan: TNativeScan;
  LProcessId: DWORD;
  LTimeoutMs: Integer;
begin
  LStarted := GetTickCount64;
  LTimeoutMs := Bounded(ATimeoutMs, 1, CMaximumTimeoutMs);
  LSnapshot := MainThreadSnapshot(skDebugger, False, 0, 0, LTimeoutMs, LStarted);
  try
    LProcessId := DWORD(StrToInt64Def(JsonString(LSnapshot, 'process_id'), 0));
    LScan := TNativeScan.Create(LProcessId, AIncludeChildren, AMaximumWindows, AMaximumControls, LTimeoutMs, LStarted);
    try
      Result := LScan.Execute;
      Result.AddPair('scope', 'debuggee');
      Result.AddPair('debugger_available', TJSONBool.Create(JsonBool(LSnapshot, 'available')));
      if JsonBool(LSnapshot, 'available') then
      begin
        Result.AddPair('executable', JsonString(LSnapshot, 'executable'));
        Result.AddPair('process_state', JsonString(LSnapshot, 'process_state'));
        Result.AddPair('stopped', TJSONBool.Create(JsonBool(LSnapshot, 'stopped')));
      end
      else
        Result.AddPair('reason', JsonString(LSnapshot, 'reason'));
    finally
      LScan.Free;
    end;
  finally
    LSnapshot.Free;
  end;
end;

{$IFDEF DAI_WINDOW_TEST}
class function TDAIWindowService.TestProcessWindows(const AProcessId: DWORD; const AIncludeChildren: Boolean;
  const AMaximumWindows, AMaximumControls, ATimeoutMs: Integer): TJSONObject;
var
  LScan: TNativeScan;
begin
  LScan := TNativeScan.Create(AProcessId, AIncludeChildren, AMaximumWindows, AMaximumControls, ATimeoutMs, GetTickCount64);
  try
    Result := LScan.Execute;
  finally
    LScan.Free;
  end;
end;
{$ENDIF}

initialization
  GPermissionLock := TObject.Create;
  GPermissionWindows := TList<HWND>.Create;
  GDispatcher := TSnapshotDispatcher.Create;

finalization
  GDispatcher.Free;
  GPermissionWindows.Free;
  GPermissionLock.Free;

end.
