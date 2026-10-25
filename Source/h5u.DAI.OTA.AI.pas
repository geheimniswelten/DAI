unit h5u.DAI.OTA.AI;

interface

uses
  System.JSON;

type
  TDAIAIService = class sealed
  public
    class function Status: TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  {$IF CompilerVersion >= 37.0}
  ToolsAPI.AI,
  {$IFEND}
  h5u.DAI.OTA.Helpers;

class function TDAIAIService.Status: TJSONObject;
var
  LProviders: TJSONArray;
  {$IF CompilerVersion >= 37.0}
  LAvailable: Boolean;
  {$IFEND}
begin
  Result := TJSONObject.Create;
  LProviders := TJSONArray.Create;
  Result.AddPair('providers', LProviders);
{$IF CompilerVersion >= 37.0}
  try
    LAvailable := False;
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LIndex: Integer;
        LPlugin: IOTAAIPlugin;
        LFeatures: TAIFeatures;
      begin
        if not Assigned(AIEngineService) then
          Exit;
        for LIndex := 0 to AIEngineService.PluginCount - 1 do
        begin
          LPlugin := AIEngineService.GetPluginByIndex(LIndex);
          if not Assigned(LPlugin) then
            Continue;
          LFeatures := LPlugin.AvailableFeatures;
          LProviders.AddElement(TJSONObject.Create.AddPair('name', LPlugin.Name)
            .AddPair('enabled', TJSONBool.Create(LPlugin.Enabled))
            .AddPair('chat', TJSONBool.Create(afChat in LFeatures))
            .AddPair('instruction', TJSONBool.Create(afInstruction in LFeatures)));
          LAvailable := LAvailable or (LPlugin.Enabled and ((afChat in LFeatures) or (afInstruction in LFeatures)));
        end;
      end);
    Result.AddPair('supported', TJSONBool.Create(True));
    Result.AddPair('available', TJSONBool.Create(LAvailable));
    Result.AddPair('reason', 'OTA-Providerstatus; API-Erreichbarkeit und Zugangsdaten wurden nicht durch eine Modellanfrage geprüft.');
  except
    on E: Exception do
    begin
      Result.AddPair('supported', TJSONBool.Create(True));
      Result.AddPair('available', TJSONBool.Create(False));
      // Provider exceptions may contain credentials or request data.
      Result.AddPair('reason', 'Der OTA-KI-Providerstatus konnte nicht gelesen werden.');
    end;
  end;
{$ELSE}
  Result.AddPair('supported', TJSONBool.Create(False));
  Result.AddPair('available', TJSONBool.Create(False));
  Result.AddPair('reason', 'Der OTA-KI-Adapter ist in diesem Build erst ab Delphi 13 verfügbar. Der lokale Indexer bleibt nutzbar.');
{$IFEND}
  Result.AddPair('network_request_sent', TJSONBool.Create(False));
end;

end.
