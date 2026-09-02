unit CodexMCP.Register;

interface

procedure Register;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Winapi.Windows,
  ToolsAPI,
  CodexMCP.Constants,
  CodexMCP.Host,
  CodexMCP.Logger,
  CodexMCP.Options.Page,
  CodexMCP.Wizard;

var
  GWizardIndex: Integer = -1;

procedure RegisterSplashEntry;
var
  LBitmap: TBitmap;
begin
  if not Assigned(SplashScreenServices) then
    Exit;
  LBitmap := TBitmap.Create;
  try
    LBitmap.PixelFormat := pf24bit;
    LBitmap.SetSize(24, 24);
    LBitmap.Canvas.Brush.Color := RGB(34, 40, 49);
    LBitmap.Canvas.FillRect(Rect(0, 0, 24, 24));
    LBitmap.Canvas.Pen.Color := RGB(230, 235, 241);
    LBitmap.Canvas.Brush.Color := RGB(230, 235, 241);
    LBitmap.Canvas.RoundRect(3, 5, 21, 20, 5, 5);
    LBitmap.Canvas.Brush.Color := RGB(34, 40, 49);
    LBitmap.Canvas.Pen.Color := RGB(34, 40, 49);
    LBitmap.Canvas.Ellipse(7, 10, 10, 13);
    LBitmap.Canvas.Ellipse(14, 10, 17, 13);
    LBitmap.Canvas.MoveTo(8, 16);
    LBitmap.Canvas.LineTo(16, 16);
    LBitmap.Canvas.Pen.Color := RGB(230, 235, 241);
    LBitmap.Canvas.MoveTo(12, 5);
    LBitmap.Canvas.LineTo(12, 2);
    LBitmap.Canvas.Brush.Color := RGB(84, 160, 255);
    LBitmap.Canvas.Ellipse(10, 0, 14, 4);
    SplashScreenServices.AddPluginBitmap(
      CCodexMCPProductName,
      LBitmap.Handle,
      False,
      'Internal'
    );
  finally
    LBitmap.Free;
  end;
end;

procedure Register;
var
  LWizard: IOTAWizard;
  LWizardServices: IOTAWizardServices;
begin
  RegisterCodexMCPOptionsPage;
  if Supports(
    BorlandIDEServices,
    IOTAWizardServices,
    LWizardServices
  ) then
  begin
    LWizard := TCodexMCPWizard.Create;
    GWizardIndex := LWizardServices.AddWizard(LWizard);
  end;
  RegisterSplashEntry;
  TCodexMCPLogger.Log('package', 'Package registriert');
end;

procedure UnregisterWizard;
var
  LWizardServices: IOTAWizardServices;
begin
  if (GWizardIndex >= 0) and Supports(
    BorlandIDEServices,
    IOTAWizardServices,
    LWizardServices
  ) then
  begin
    try
      LWizardServices.RemoveWizard(GWizardIndex);
    except
      // Die IDE kann den Wizarddienst bereits heruntergefahren haben.
    end;
  end;
  GWizardIndex := -1;
end;

finalization
  UnregisterCodexMCPOptionsPage;
  UnregisterWizard;
  TCodexMCPHost.ShutdownInstance;

end.
