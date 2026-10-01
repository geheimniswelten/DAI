unit h5u.DAI.MCP.Tools;
interface
uses System.JSON, System.SyncObjs, System.SysUtils, h5u.DAI.Types;
type
  TDAIMCPTools = class
  public
    class var CallCount: Integer;
    class var SynchronizeEntered: TEvent;
    class var SynchronizeCompleted: Integer;
    class var SynchronizeCallbackThreadId: Cardinal;
    class var SynchronizeCallback: TProc;
    class function ListTools: TJSONArray; static;
    class function CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject; static;
  end;
implementation
uses System.Classes, Winapi.Windows;
class function TDAIMCPTools.ListTools: TJSONArray;
begin Result := TJSONArray.Create; end;
class function TDAIMCPTools.CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
begin
  InterlockedIncrement(CallCount);
  if SameText(AName, 'sync-stop') and Assigned(SynchronizeEntered) then
  begin
    SynchronizeEntered.SetEvent;
    TThread.Synchronize(nil,
      procedure
      begin
        SynchronizeCallbackThreadId := GetCurrentThreadId;
        if Assigned(SynchronizeCallback) then
          SynchronizeCallback;
        InterlockedIncrement(SynchronizeCompleted);
      end);
  end;
  Result := TJSONObject.Create.AddPair('called', AName).AddPair('client', AContext.ClientName).AddPair('thread', AContext.ThreadId);
end;
end.
