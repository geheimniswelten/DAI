unit h5u.DAI.Wizard;

interface

uses
  ToolsAPI;

type
  TDAIWizard = class(TNotifierObject, IOTAWizard)
  private
    FAboutBoxIndex: Integer;
    FIDENotifierIndex: Integer;
    FIDENotifier: IOTAIDENotifier;
    procedure RegisterSplashAndAbout;
    procedure RemoveAboutEntry;
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
  System.Types,
  Vcl.Graphics,
  h5u.DAI.Consts,
  h5u.DAI.IDE.Notifier,
  h5u.DAI.Options.Page,
  h5u.DAI.Runtime;

constructor TDAIWizard.Create;
var
  LOTAServices: IOTAServices;
begin
  inherited Create;
  FAboutBoxIndex := -1;
  FIDENotifierIndex := -1;

  RegisterSplashAndAbout;
  RegisterDAIOptionsPage;

  if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
  begin
    FIDENotifier := TDAIIDENotifier.Create;
    FIDENotifierIndex := LOTAServices.AddNotifier(FIDENotifier);
  end;

  TDAIRuntime.Start;
end;

destructor TDAIWizard.Destroy;
var
  LOTAServices: IOTAServices;
begin
  TDAIRuntime.Stop;

  if (FIDENotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
    try
      LOTAServices.RemoveNotifier(FIDENotifierIndex);
    except
    end;
  FIDENotifierIndex := -1;
  FIDENotifier := nil;

  UnregisterDAIOptionsPage;
  RemoveAboutEntry;
  inherited Destroy;
end;

procedure TDAIWizard.Execute;
var
  LOTAServices: IOTAServices;
begin
  if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
    LOTAServices.GetEnvironmentOptions.EditOptions('', 'DAI');
end;

function TDAIWizard.GetIDString: string;
begin
  Result := 'h5u.DAI.DelphiAI';
end;

function TDAIWizard.GetName: string;
begin
  Result := CDAIDisplayName;
end;

function TDAIWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TDAIWizard.RegisterSplashAndAbout;
var
  LAboutServices: IOTAAboutBoxServices;
  LBitmap: TBitmap;
begin
  LBitmap := TBitmap.Create;
  try
    LBitmap.PixelFormat := pf24bit;
    LBitmap.SetSize(24, 24);
    LBitmap.Canvas.Brush.Color := $00332A22;
    LBitmap.Canvas.FillRect(Rect(0, 0, 24, 24));
    LBitmap.Canvas.Brush.Color := clWhite;
    LBitmap.Canvas.Pen.Color := clWhite;
    LBitmap.Canvas.Rectangle(3, 3, 21, 21);
    LBitmap.Canvas.Font.Color := $00332A22;
    LBitmap.Canvas.Font.Style := [fsBold];
    LBitmap.Canvas.Font.Size := 9;
    LBitmap.Canvas.TextOut(4, 5, 'DAI');

    if Assigned(SplashScreenServices) then
      SplashScreenServices.AddPluginBitmap(
        CDAIDisplayName,
        LBitmap.Handle,
        False,
        'MCP-Integration für Codex'
      );

    if Supports(BorlandIDEServices, IOTAAboutBoxServices, LAboutServices) then
      FAboutBoxIndex := LAboutServices.AddPluginInfo(
        CDAIDisplayName,
        'DAI – Delphi AI' + sLineBreak +
        'Lokaler MCP-Server für Codex mit kontrolliertem Zugriff auf die Delphi OpenToolsAPI.',
        LBitmap.Handle,
        False,
        'Interne Erweiterung',
        CDAIVersion
      );
  finally
    LBitmap.Free;
  end;
end;

procedure TDAIWizard.RemoveAboutEntry;
var
  LAboutServices: IOTAAboutBoxServices;
begin
  if (FAboutBoxIndex >= 0) and Supports(BorlandIDEServices, IOTAAboutBoxServices, LAboutServices) then
    try
      LAboutServices.RemovePluginInfo(FAboutBoxIndex);
    except
    end;
  FAboutBoxIndex := -1;
end;

end.
