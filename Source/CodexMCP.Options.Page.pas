unit CodexMCP.Options.Page;

interface

procedure RegisterCodexMCPOptionsPage;
procedure UnregisterCodexMCPOptionsPage;

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  Vcl.Forms,
  ToolsAPI,
  CodexMCP.Options.Frame;

type
  TCodexMCPOptionsAddIn = class(TInterfacedObject, INTAAddInOptions)
  strict private
    FFrame: TCustomFrame;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

var
  GOptionsAddIn: INTAAddInOptions;

{ TCodexMCPOptionsAddIn }

procedure TCodexMCPOptionsAddIn.DialogClosed(Accepted: Boolean);
begin
  try
    if Accepted and (FFrame is TCodexMCPOptionsFrame) then
      TCodexMCPOptionsFrame(FFrame).StoreToSettings;
  finally
    FFrame := nil;
  end;
end;

procedure TCodexMCPOptionsAddIn.FrameCreated(AFrame: TCustomFrame);
begin
  FFrame := AFrame;
  if AFrame is TCodexMCPOptionsFrame then
    TCodexMCPOptionsFrame(AFrame).LoadFromSettings;
end;

function TCodexMCPOptionsAddIn.GetArea: string;
begin
  Result := '';
end;

function TCodexMCPOptionsAddIn.GetCaption: string;
begin
  Result := 'Codex MCP für Delphi IDE';
end;

function TCodexMCPOptionsAddIn.GetFrameClass: TCustomFrameClass;
begin
  Result := TCodexMCPOptionsFrame;
end;

function TCodexMCPOptionsAddIn.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TCodexMCPOptionsAddIn.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

function TCodexMCPOptionsAddIn.ValidateContents: Boolean;
var
  LMessage: string;
begin
  Result := not (FFrame is TCodexMCPOptionsFrame) or
    TCodexMCPOptionsFrame(FFrame).ValidateSettings(LMessage);
  if not Result then
    MessageDlg(LMessage, mtError, [mbOK], 0);
end;

procedure DoRegisterOptionsPage;
var
  LServices: INTAEnvironmentOptionsServices;
begin
  if Assigned(GOptionsAddIn) then
    Exit;
  if Supports(
    BorlandIDEServices,
    INTAEnvironmentOptionsServices,
    LServices
  ) then
  begin
    GOptionsAddIn := TCodexMCPOptionsAddIn.Create;
    LServices.RegisterAddInOptions(GOptionsAddIn);
  end;
end;

procedure RegisterCodexMCPOptionsPage;
begin
  DoRegisterOptionsPage;
end;

procedure UnregisterCodexMCPOptionsPage;
var
  LServices: INTAEnvironmentOptionsServices;
begin
  if not Assigned(GOptionsAddIn) then
    Exit;
  if Supports(
    BorlandIDEServices,
    INTAEnvironmentOptionsServices,
    LServices
  ) then
  begin
    try
      LServices.UnregisterAddInOptions(GOptionsAddIn);
    except
      // Die IDE kann ihre Optionsdienste bereits heruntergefahren haben.
    end;
  end;
  GOptionsAddIn := nil;
end;

end.
