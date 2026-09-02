unit CodexMCP.Logger;

interface

type
  TCodexMCPLogger = class sealed
  public
    class procedure Log(const AAccessPoint, ADetail: string); static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  ToolsAPI,
  Winapi.Windows,
  CodexMCP.Settings;

class procedure TCodexMCPLogger.Log(
  const AAccessPoint,
  ADetail: string
);
var
  LMessage: string;
  LWrite: TThreadProcedure;
begin
  LMessage := Format('[Codex MCP] %s: %s', [AAccessPoint, ADetail]);
  OutputDebugString(PChar(LMessage));
  if not TCodexMCPSettings.Instance.LoggingEnabled then
    Exit;

  LWrite :=
    procedure
    var
      LMessages: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, LMessages) then
        LMessages.AddTitleMessage(LMessage);
    end;

  if GetCurrentThreadId = MainThreadID then
    LWrite()
  else
    TThread.Synchronize(nil, LWrite);
end;

end.
