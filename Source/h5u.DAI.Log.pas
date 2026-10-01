unit h5u.DAI.Log;

interface

uses
  System.JSON;

type
  TDAILog = class sealed
  private
    class procedure AddMessage(const AText: string); static;
  public
    class procedure Access(const AText: string); static;
    class procedure Error(const AText: string); static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Settings;

type
  TDAILogDispatcher = class
  private
    FLock: TObject;
    FMessages: TQueue<string>;
    FQueued: Boolean;
    FStopped: Boolean;
    procedure DispatchQueued;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string);
    procedure Shutdown;
  end;

var
  GDispatcher: TDAILogDispatcher;

procedure WriteMessageOnMainThread(const AText: string);
var
  LMessages: IOTAMessageServices;
begin
  try
    if Supports(BorlandIDEServices, IOTAMessageServices, LMessages) then
      LMessages.AddTitleMessage(AText)
    else
      OutputDebugString(PChar(AText));
  except
    OutputDebugString(PChar(AText));
  end;
end;

constructor TDAILogDispatcher.Create;
begin
  inherited;
  FLock := TObject.Create;
  FMessages := TQueue<string>.Create;
end;

destructor TDAILogDispatcher.Destroy;
begin
  Shutdown;
  FMessages.Free;
  FLock.Free;
  inherited;
end;

procedure TDAILogDispatcher.Add(const AText: string);
var
  LStopped: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    LStopped := FStopped;
    if not LStopped and (GetCurrentThreadId <> MainThreadID) then
    begin
      // Retain text only. The stable method identifies precisely our queued event.
      FMessages.Enqueue(AText);
      if not FQueued then
      begin
        TThread.ForceQueue(nil, DispatchQueued);
        FQueued := True;
      end;
      Exit;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  if LStopped then
    OutputDebugString(PChar(AText))
  else
    WriteMessageOnMainThread(AText);
end;

procedure TDAILogDispatcher.DispatchQueued;
var
  LText: string;
begin
  repeat
    System.TMonitor.Enter(FLock);
    try
      if FStopped or (FMessages.Count = 0) then
      begin
        FQueued := False;
        Exit;
      end;
      LText := FMessages.Dequeue;
    finally
      System.TMonitor.Exit(FLock);
    end;
    WriteMessageOnMainThread(LText);
  until False;
end;

procedure TDAILogDispatcher.Shutdown;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopped := True;
    FMessages.Clear;
    FQueued := False;
    // Never remove unrelated Queue(nil) callbacks from the IDE or other packages.
    TThread.RemoveQueuedEvents(nil, DispatchQueued);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class procedure TDAILog.Access(const AText: string);
begin
  if TDAISettings.Instance.LogAccessPoints then
    AddMessage('[DAI] ' + AText);
end;

class procedure TDAILog.AddMessage(const AText: string);
begin
  try
    GDispatcher.Add(AText);
  except
    OutputDebugString(PChar(AText));
  end;
end;

class procedure TDAILog.Error(const AText: string);
begin
  AddMessage('[DAI] Fehler: ' + AText);
end;

class procedure TDAILog.Shutdown;
begin
  GDispatcher.Shutdown;
end;

initialization
  GDispatcher := TDAILogDispatcher.Create;

finalization
  GDispatcher.Free;

end.
