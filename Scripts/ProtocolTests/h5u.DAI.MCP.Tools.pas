unit h5u.DAI.MCP.Tools;
interface
uses System.JSON, h5u.DAI.Types;
type
  TDAIMCPTools = class
  public
    class var CallCount: Integer;
    class function ListTools: TJSONArray; static;
    class function CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject; static;
  end;
implementation
uses Winapi.Windows;
class function TDAIMCPTools.ListTools: TJSONArray;
begin Result := TJSONArray.Create; end;
class function TDAIMCPTools.CallTool(const AName: string; const AArguments: TJSONObject; const AContext: TDAIRequestContext): TJSONObject;
begin
  InterlockedIncrement(CallCount);
  Result := TJSONObject.Create.AddPair('called', AName).AddPair('client', AContext.ClientName).AddPair('thread', AContext.ThreadId);
end;
end.