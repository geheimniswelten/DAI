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
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Settings;

class procedure TDAILog.Access(const AText: string);
begin
  if TDAISettings.Instance.LogAccessPoints then
    AddMessage('[DAI] ' + AText);
end;

class procedure TDAILog.AddMessage(const AText: string);
var
  LMessages: IOTAMessageServices;
begin
  try
    if GetCurrentThreadId = MainThreadID then
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, LMessages) then
        LMessages.AddTitleMessage(AText)
      else
        OutputDebugString(PChar(AText));
      Exit;
    end;

    TThread.Queue(
      nil,
      procedure
      var
        LQueuedMessages: IOTAMessageServices;
      begin
        try
          if Supports(BorlandIDEServices, IOTAMessageServices, LQueuedMessages) then
            LQueuedMessages.AddTitleMessage(AText)
          else
            OutputDebugString(PChar(AText));
        except
          OutputDebugString(PChar(AText));
        end;
      end
    );
  except
    OutputDebugString(PChar(AText));
  end;
end;

class procedure TDAILog.Error(const AText: string);
begin
  AddMessage('[DAI] Fehler: ' + AText);
end;

end.
