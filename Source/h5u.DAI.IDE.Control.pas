unit h5u.DAI.IDE.Control;

interface

uses
  System.JSON;

type
  TDAIIDEControl = class sealed
  public
    class function Control(const AAction: string): TJSONObject; static;
    class procedure ResetDeferredClose; static;
    class function HasDeferredClose: Boolean; static;
    class function CompleteDeferredClose: Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Vcl.Forms,
  Winapi.Messages,
  Winapi.Windows,
  h5u.DAI.OTA.Helpers;

type
  TDAIDeferredClose = record
    Window: HWND;
    ProcessId: Cardinal;
    WindowThreadId: Cardinal;
  end;

threadvar
  GDeferredClose: TDAIDeferredClose;

function MainWindowOnMainThread(out AWindow: HWND; out AProcessId, AThreadId: Cardinal): Boolean;
var
  LMainForm: TForm;
begin
  AWindow := 0;
  AProcessId := 0;
  AThreadId := 0;
  if not Assigned(Application) then
    Exit(False);
  LMainForm := Application.MainForm;
  if not Assigned(LMainForm) then
    Exit(False);
  if csDestroying in LMainForm.ComponentState then
    Exit(False);
  // Accessing Handle without this guard would create a window during teardown.
  if not LMainForm.HandleAllocated then
    Exit(False);
  AWindow := LMainForm.Handle;
  if not IsWindow(AWindow) then
    Exit(False);
  AThreadId := GetWindowThreadProcessId(AWindow, AProcessId);
  Result := (AThreadId <> 0) and (AProcessId = GetCurrentProcessId);
end;

class function TDAIIDEControl.Control(const AAction: string): TJSONObject;
var
  LAccepted, LClosePending, LForeground, LMinimized, LVisible: Boolean;
  LAction: string;
  LProcessId, LWindowThreadId: Cardinal;
  LWindow: HWND;
begin
  LAction := LowerCase(Trim(AAction));
  if (LAction <> 'minimize') and (LAction <> 'restore') and (LAction <> 'foreground') and
    (LAction <> 'background') and (LAction <> 'close') then
    raise EArgumentException.Create('action muss minimize, restore, foreground, background oder close sein.');
  if LAction = 'close' then
    ResetDeferredClose;
  LAccepted := False;
  LClosePending := False;
  LForeground := False;
  LMinimized := False;
  LVisible := False;
  LWindow := 0;
  LProcessId := 0;
  LWindowThreadId := 0;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if not MainWindowOnMainThread(LWindow, LProcessId, LWindowThreadId) then
        raise EInvalidOperation.Create('Das vorhandene Hauptfenster der Delphi-IDE ist nicht verfügbar.');
      if LAction = 'minimize' then
      begin
        ShowWindow(LWindow, SW_MINIMIZE);
        LAccepted := IsIconic(LWindow);
      end
      else if LAction = 'restore' then
      begin
        ShowWindow(LWindow, SW_RESTORE);
        LAccepted := not IsIconic(LWindow) and IsWindowVisible(LWindow);
      end
      else if LAction = 'foreground' then
      begin
        if IsIconic(LWindow) then
          ShowWindow(LWindow, SW_RESTORE);
        SetForegroundWindow(LWindow);
        // Windows may refuse focus stealing. Report the observed result.
        LAccepted := GetForegroundWindow = LWindow;
      end
      else if LAction = 'background' then
        LAccepted := SetWindowPos(LWindow, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)
      else
      begin
        // No message is posted here: the HTTP server must first write its response.
        LAccepted := True;
        LClosePending := True;
      end;
      LForeground := GetForegroundWindow = LWindow;
      LMinimized := IsIconic(LWindow);
      LVisible := IsWindowVisible(LWindow);
    end);
  if LClosePending then
  begin
    // Keep this on the original caller/HTTP worker, not on the synchronized IDE thread.
    GDeferredClose.Window := LWindow;
    GDeferredClose.ProcessId := LProcessId;
    GDeferredClose.WindowThreadId := LWindowThreadId;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('action', LAction);
  Result.AddPair('accepted', TJSONBool.Create(LAccepted));
  Result.AddPair('foreground', TJSONBool.Create(LForeground));
  Result.AddPair('minimized', TJSONBool.Create(LMinimized));
  Result.AddPair('visible', TJSONBool.Create(LVisible));
  Result.AddPair('close_pending', TJSONBool.Create(LClosePending));
  if LClosePending then
    Result.AddPair('save_prompts_possible', TJSONBool.Create(True));
end;

class procedure TDAIIDEControl.ResetDeferredClose;
begin
  GDeferredClose := Default(TDAIDeferredClose);
end;

class function TDAIIDEControl.HasDeferredClose: Boolean;
begin
  Result := GDeferredClose.Window <> 0;
end;

class function TDAIIDEControl.CompleteDeferredClose: Boolean;
var
  LDeferred: TDAIDeferredClose;
  LPosted: Boolean;
begin
  LDeferred := GDeferredClose;
  ResetDeferredClose;
  if LDeferred.Window = 0 then
    Exit(False);
  LPosted := False;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LProcessId, LThreadId: Cardinal;
        LWindow: HWND;
      begin
        if not MainWindowOnMainThread(LWindow, LProcessId, LThreadId) then
          Exit;
        if (LWindow <> LDeferred.Window) or (LProcessId <> LDeferred.ProcessId) or
          (LThreadId <> LDeferred.WindowThreadId) then
          Exit;
        // Normal close preserves CloseQuery, save prompts and user cancellation.
        LPosted := PostMessage(LWindow, WM_CLOSE, 0, 0);
      end);
  except
    // The response is already sent; a stale/closing IDE must not raise afterwards.
    LPosted := False;
  end;
  Result := LPosted;
end;

end.
