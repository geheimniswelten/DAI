unit h5u.DAI.Options.Page;

interface

uses
  Vcl.Forms,
  ToolsAPI;

type
  TDAIOptionsPage = class(TInterfacedObject, INTAAddInOptions)
  private
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

procedure RegisterDAIOptionsPage;
procedure UnregisterDAIOptionsPage;

implementation

uses
  System.Classes,
  System.SysUtils,
  h5u.DAI.Options.Frame;

var
  GOptionsPage: INTAAddInOptions;

procedure TDAIOptionsPage.DialogClosed(Accepted: Boolean);
begin
  if Accepted and (FFrame is TDAIOptionsFrame) then
    TDAIOptionsFrame(FFrame).StoreToSettings;
  FFrame := nil;
end;

procedure TDAIOptionsPage.FrameCreated(AFrame: TCustomFrame);
var
  LThemingServices: IOTAIDEThemingServices;
begin
  FFrame := AFrame;
  if AFrame is TDAIOptionsFrame then
    TDAIOptionsFrame(AFrame).LoadFromSettings;
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, LThemingServices) then
    LThemingServices.ApplyTheme(AFrame);
end;

function TDAIOptionsPage.GetArea: string;
begin
  Result := '';
end;

function TDAIOptionsPage.GetCaption: string;
begin
  Result := 'DAI';
end;

function TDAIOptionsPage.GetFrameClass: TCustomFrameClass;
begin
  Result := TDAIOptionsFrame;
end;

function TDAIOptionsPage.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TDAIOptionsPage.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

function TDAIOptionsPage.ValidateContents: Boolean;
begin
  Result := True;
end;

procedure RegisterDAIOptionsPage;
var
  LServices: INTAEnvironmentOptionsServices;
begin
  if Assigned(GOptionsPage) then
    Exit;
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LServices) then
    Exit;
  GOptionsPage := TDAIOptionsPage.Create;
  LServices.RegisterAddInOptions(GOptionsPage);
end;

procedure UnregisterDAIOptionsPage;
var
  LServices: INTAEnvironmentOptionsServices;
begin
  if not Assigned(GOptionsPage) then
    Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LServices) then
    try
      LServices.UnregisterAddInOptions(GOptionsPage);
    except
    end;
  GOptionsPage := nil;
end;

initialization
  GOptionsPage := nil;

finalization
  UnregisterDAIOptionsPage;

end.
