unit h5u.DAI.IDE.Toolbar;

interface

type
  TDAIIDEToolbar = class sealed
  public
    class var CheckCount: Integer;
    class var OffMainThread: Boolean;
    class var LastShared: Boolean;
    class var LastManualClientRegistration: Boolean;
    class var LastPort: Integer;
    class var LastToken: string;
    class var LastSaveCount: Integer;
    class var LastRegisterCount: Integer;
    class var LastUnregisterCount: Integer;
    class var LastStartCount: Integer;
    class var LastStopCount: Integer;
    class procedure Reset; static;
    class procedure CheckRegistrations; static;
  end;

implementation

uses
  System.Classes,
  Winapi.Windows,
  h5u.DAI.Clients.Registration,
  h5u.DAI.Runtime,
  h5u.DAI.Settings;

class procedure TDAIIDEToolbar.CheckRegistrations;
begin
  Inc(CheckCount);
  OffMainThread := OffMainThread or (GetCurrentThreadId <> MainThreadID);
  LastShared := TDAISettings.Instance.UseSharedConnectionSettings;
  LastManualClientRegistration := TDAISettings.Instance.ManualClientRegistration;
  LastPort := TDAISettings.Instance.Port;
  LastToken := TDAISettings.Instance.Token;
  LastSaveCount := TDAISettings.Instance.SaveCount;
  LastRegisterCount := TDAIClientRegistration.RegisterCount;
  LastUnregisterCount := TDAIClientRegistration.UnregisterCount;
  LastStartCount := TDAIRuntime.StartCount;
  LastStopCount := TDAIRuntime.StopCount;
end;

class procedure TDAIIDEToolbar.Reset;
begin
  CheckCount := 0;
  OffMainThread := False;
  LastShared := False;
  LastManualClientRegistration := False;
  LastPort := 0;
  LastToken := '';
  LastSaveCount := 0;
  LastRegisterCount := 0;
  LastUnregisterCount := 0;
  LastStartCount := 0;
  LastStopCount := 0;
end;

end.
