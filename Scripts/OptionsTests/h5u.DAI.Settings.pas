unit h5u.DAI.Settings;

interface

uses
  System.Classes;

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    Enabled: Boolean;
    LogAccessPoints: Boolean;
    Port: Integer;
    Token: string;
    CustomReadDirectories: TStringList;
    SaveCount: Integer;
    constructor Create;
    destructor Destroy; override;
    class function Instance: TDAISettings; static;
    class procedure Reset; static;
    function GenerateToken: string;
    function LocalizedProjectsDirectoryHint: string;
    procedure Save;
  end;

implementation

constructor TDAISettings.Create;
begin
  inherited Create;
  CustomReadDirectories := TStringList.Create;
end;

destructor TDAISettings.Destroy;
begin
  CustomReadDirectories.Free;
  inherited Destroy;
end;

function TDAISettings.GenerateToken: string;
begin
  Result := 'synthetic-generated-options-token';
end;

class function TDAISettings.Instance: TDAISettings;
begin
  Result := FInstance;
end;

function TDAISettings.LocalizedProjectsDirectoryHint: string;
begin
  Result := 'C:\SyntheticDAITest\Projects';
end;

class procedure TDAISettings.Reset;
begin
  FInstance.Enabled := False;
  FInstance.LogAccessPoints := False;
  FInstance.Port := 7101;
  FInstance.Token := 'synthetic-stored-options-token';
  FInstance.CustomReadDirectories.Clear;
  FInstance.SaveCount := 0;
end;

procedure TDAISettings.Save;
begin
  Inc(SaveCount);
end;

initialization
  TDAISettings.FInstance := TDAISettings.Create;
  TDAISettings.Reset;

finalization
  TDAISettings.FInstance.Free;

end.
