unit CodexMCP.Wizard;

interface

uses
  ToolsAPI;

type
  TCodexMCPWizard = class(TNotifierObject, IOTAWizard, IOTAIDStringWizard)
  public
    constructor Create;
    destructor Destroy; override;
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  CodexMCP.Constants,
  CodexMCP.Host;

constructor TCodexMCPWizard.Create;
begin
  inherited Create;
  TCodexMCPHost.Instance.ApplySettings;
end;

destructor TCodexMCPWizard.Destroy;
begin
  TCodexMCPHost.ShutdownInstance;
  inherited;
end;

procedure TCodexMCPWizard.Execute;
begin
  MessageDlg(
    CCodexMCPProductName + sLineBreak +
    TCodexMCPHost.Instance.StatusText + sLineBreak + sLineBreak +
    'Konfiguration: Tools > Options > Third Party > Codex MCP für Delphi IDE',
    mtInformation,
    [mbOK],
    0
  );
end;

function TCodexMCPWizard.GetIDString: string;
begin
  Result := CCodexMCPWizardId;
end;

function TCodexMCPWizard.GetName: string;
begin
  Result := CCodexMCPProductName;
end;

function TCodexMCPWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

end.
