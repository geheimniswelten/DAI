unit ToolsAPI;

interface

uses
  System.Classes,
  Vcl.ActnList,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ImgList;

const
  // Studio 37.0 ToolsAPI.pas:567; the test script also compares the SDK value.
  sDebugToolBar = 'DebugToolBar';

type
  IOTANotifier = interface
    ['{F17A7BCF-E07D-11D1-AB0B-00C04FB16FB3}']
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
  end;

  TNotifierObject = class(TInterfacedObject)
  protected
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
  end;

  INTAToolbarStreamNotifier = interface(IOTANotifier)
    ['{A2D9F2F7-815E-4E5B-BD83-2BD4A57A45E1}']
    procedure AfterSave(Toolbar: TWinControl);
    procedure BeforeSave(Toolbar: TWinControl);
    procedure ToolbarLoaded(Toolbar: TWinControl);
  end;

  INTAToolbarStreamNotifier190 = interface(INTAToolbarStreamNotifier)
    ['{9170ADE2-7D04-4B6C-AF74-9F56FB1AA29B}']
    procedure BeforeLoad(Toolbar: TWinControl);
  end;

  INTAReadToolbarNotifier = interface(IOTANotifier)
    ['{748F68BB-599C-4BE4-83A3-EEEBD920B6EE}']
    procedure FindMethodInstance(Reader: TReader; const MethodName: string; var Method: TMethod; var Error: Boolean);
    procedure SetName(Reader: TReader; Component: TComponent; var Name: string; var Handled: Boolean);
    procedure ReadError(Reader: TReader; const Message: string; var Handled: Boolean);
  end;

  // Minimal doubles of the official signatures used by the production unit.
  INTAServices = interface
    ['{8209041F-F37F-4570-88B8-6C310FFFF81A}']
    function GetActionList: TCustomActionList;
    function GetImageList: TCustomImageList;
    function GetToolBar(const ToolBarName: string): TToolBar;
    function AddMasked(Image: TBitmap; MaskColor: TColor; const Ident: string): Integer;
    function AddImage(const AImageName: string; const AImage: TGraphicArray): Integer;
    function AddToolButton(const ToolBarName, ButtonName: string; AAction: TCustomAction;
      const IsDivider: Boolean = False; const ReferenceButton: string = ''; InsertBefore: Boolean = False): TControl;
    function RegisterToolbarNotifier(const ANotifier: IOTANotifier): Integer;
    procedure UnregisterToolbarNotifier(AIndex: Integer);
    property ActionList: TCustomActionList read GetActionList;
    property ImageList: TCustomImageList read GetImageList;
    property ToolBar[const ToolBarName: string]: TToolBar read GetToolBar;
  end;

  IOTAEnvironmentOptions = interface
    ['{D5772B06-A933-4A46-BBF9-3B86E039B238}']
    procedure EditOptions(const Area: string; const PageCaption: string = '');
  end;

  IOTAServices = interface
    ['{7FD1CE91-E053-11D1-AB0B-00C04FB16FB3}']
    function GetEnvironmentOptions: IOTAEnvironmentOptions;
  end;

var
  BorlandIDEServices: IInterface;

implementation

procedure TNotifierObject.AfterSave;
begin
end;

procedure TNotifierObject.BeforeSave;
begin
end;

procedure TNotifierObject.Destroyed;
begin
end;

procedure TNotifierObject.Modified;
begin
end;

end.
