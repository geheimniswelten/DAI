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
  if GetCurrentThreadId = MainThreadID then
  begin
    if Supports(BorlandIDEServices, IOTAMessageServices, LMessages) then
      LMessages.AddTitleMessage(AText);
    Exit;
  end;

  TThread.Queue(nil,
    procedure var LMessages: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, LMessages) then
        LMessages.AddTitleMessage(AText);
    end);
end;

class procedure TDAILog.Error(const AText: string);
begin
  AddMessage('[DAI] Fehler: ' + AText);
end;

end.
