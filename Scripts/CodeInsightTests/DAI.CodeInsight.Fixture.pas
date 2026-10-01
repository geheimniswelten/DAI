unit DAI.CodeInsight.Fixture;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  System.Types,
  ToolsAPI;

type
  TTestProviderMode = (pmTimeout, pmImmediate, pmDeferred, pmError, pmRaiseAfterCapture);

  TStoredDefinition = record
    RequestId: Integer;
    Callback: TOTAGotoDefinitionCallBack;
    CallbackEx: TOTAGotoDefinitionCallBackEx;
  end;

  TTestEditView = class(TInterfacedObject, IOTAEditView)
  public
    procedure IncreaseDecreaseFontSize(const ActionMode: TOTAIncreaseDecreaseFontSizeMode);
    function AddNotifier(const Extension: INTAEditViewNotifier): Integer;
    procedure RemoveNotifier(Index: Integer);
    procedure NavigateToModification(Direction: TSearchDirection; ModificationType: TOTAModificationType);
    procedure ClearAllBookmarks;
    function BookmarkGoto(BookmarkID: Integer): Boolean;
    function BookmarkRecord(BookmarkID: Integer): Boolean;
    function BookmarkToggle(BookmarkID: Integer): Boolean;
    procedure Center(Row, Col: Integer);
    function GetBlock: IOTAEditBlock;
    function GetBookmarkPos(BookmarkID: Integer): TOTACharPos;
    function GetBottomRow: Integer;
    function GetBuffer: IOTAEditBuffer;
    function GetEditWindow: INTAEditWindow;
    function GetLastEditColumn: Integer;
    function GetLastEditRow: Integer;
    function GetLeftColumn: Integer;
    function GetPosition: IOTAEditPosition;
    function GetRightColumn: Integer;
    function GetTopRow: Integer;
    procedure MoveCursorToView;
    procedure MoveViewToCursor;
    procedure PageDown;
    procedure PageUp;
    procedure Paint;
    function Scroll(DeltaRow: Integer; DeltaCol: Integer): Integer;
    procedure SetTopLeft(TopRow, LeftCol: Integer);
    procedure SetTempMsg(const Msg: string);
    function GetCursorPos: TOTAEditPos;
    procedure SetCursorPos(const Value: TOTAEditPos);
    function GetTopPos: TOTAEditPos;
    procedure SetTopPos(const Value: TOTAEditPos);
    function GetViewSize: TSize;
    function PosToCharPos(Pos: Longint): TOTACharPos;
    function CharPosToPos(CharPos: TOTACharPos): Longint;
    procedure ConvertPos(EdPosToCharPos: Boolean; var EditPos: TOTAEditPos; var CharPos: TOTACharPos);
    procedure GetAttributeAtPos(const EdPos: TOTAEditPos; IncludeMargin: Boolean; var Element, LineFlag: Integer);
    function SameView(const EditView: IOTAEditView): Boolean;
  end;

  TTestSourceEditor = class(TInterfacedObject, IOTASourceEditor)
  public
    View: IOTAEditView;
    procedure SwitchToView(Index: Integer; const AViewContext: TObject); overload;
    procedure SwitchToView(const AViewIdentifier: string; const AViewContext: TObject); overload;
    function GetSubViewCount: Integer;
    function GetSubViewIdentifier(Index: Integer): string;
    function GetSubViewIndex: Integer;
    procedure SwitchToView(Index: Integer); overload;
    procedure SwitchToView(const AViewIdentifier: string); overload;
    function CreateReader: IOTAEditReader;
    function CreateWriter: IOTAEditWriter;
    function CreateUndoableWriter: IOTAEditWriter;
    function GetEditViewCount: Integer;
    function GetEditView(Index: Integer): IOTAEditView;
    function GetLinesInBuffer: Longint;
    function SetSyntaxHighlighter(SyntaxHighlighter: TOTASyntaxHighlighter): TOTASyntaxHighlighter;
    function GetBlockAfter: TOTACharPos;
    function GetBlockStart: TOTACharPos;
    function GetBlockType: TOTABlockType;
    function GetBlockVisible: Boolean;
    procedure SetBlockAfter(const Value: TOTACharPos);
    procedure SetBlockStart(const Value: TOTACharPos);
    procedure SetBlockType(Value: TOTABlockType);
    procedure SetBlockVisible(Value: Boolean);
    function AddNotifier(const ANotifier: IOTANotifier): Integer;
    function GetFileName: string;
    function GetModified: Boolean;
    function GetModule: IOTAModule;
    function MarkModified: Boolean;
    procedure RemoveNotifier(Index: Integer);
    procedure Show;
  end;

  TTestCodeInsightProvider = class(TInterfacedObject, IOTACodeInsightManager, IOTAAsyncCodeInsightManager)
  private
    FStoredDefinitions: TList<TStoredDefinition>;
    FStoredHints: TList<TOTAHintTextCallBack>;
    FWorker: TThread;
  protected
    function GetStoredDefinitionCount: Integer;
    function GetStoredHintCount: Integer;
    function InvokeDefinition(ALine, ACharacter: Integer; ACallback: TOTAGotoDefinitionCallBack;
      ACallbackEx: TOTAGotoDefinitionCallBackEx): Integer;
  public
    BeforeAsyncCallback: TThreadProcedure;
    ProviderId: string;
    Mode: TTestProviderMode;
    RequestId: Integer;
    ReplyFile: string;
    ReplyLine: Integer;
    ReplyCharacter: Integer;
    HintText: string;
    InputLine: Integer;
    InputCharacter: Integer;
    HintLine: Integer;
    HintColumn: Integer;
    DefinitionCount: Integer;
    CancelCount: Integer;
    CancelledId: Integer;
    HintCount: Integer;
    SyncHintCount: Integer;
    HtmlViewerCount: Integer;
    LateProvider: TTestCodeInsightProvider;
    constructor Create(const AProviderId: string);
    destructor Destroy; override;
    procedure DeliverStoredDefinitions;
    procedure DeliverStoredHints;
    procedure JoinWorker;
    property StoredDefinitionCount: Integer read GetStoredDefinitionCount;
    property StoredHintCount: Integer read GetStoredHintCount;
    function GetOptionSetName: string;
    function GetName: string;
    function GetIDString: string;
    function GetEnabled: Boolean;
    procedure SetEnabled(Value: Boolean);
    function EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
    procedure AllowCodeInsight(var Allow: Boolean; const Key: Char);
    function PreValidateCodeInsight(const Str: string): Boolean;
    function IsViewerBrowsable(Index: Integer): Boolean;
    function GetMultiSelect: Boolean;
    procedure GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
    procedure OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
    function HandlesFile(const AFileName: string): Boolean;
    function GetLongestItem: string;
    procedure GetParameterList(out ParameterList: IOTACodeInsightParameterList);
    procedure GetCodeInsightType(AChar: Char; AElement: Integer; out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
    function InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
    function InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; var SelectedIndex: Integer): Boolean;
    procedure ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
    function ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
    function GetHintText(HintLine, HintCol: Integer): string;
    function GotoDefinition(out AFileName: string; out ALineNum: Integer; Index: Integer = -1): Boolean;
    procedure Done(Accepted: Boolean; out DisplayParams: Boolean);
    procedure AsyncAllowCodeInsight(var AAllow: Boolean; const AKey: Char);
    function AsyncCanInvoke(AInsightType: TOTACodeInsightType): Boolean;
    function AsyncEnabled: Boolean;
    function AsyncInvokeCodeCompletion(AHowInvoked: TOTAInvokeType; var AStr: string; ALine, ACharIndex: Integer; ACallback: TOTACodeCompleteCallBack): Integer;
    function AsyncInvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; const AFileName: string; ALine, ACharIndex: Integer; ACallback: TOTAParametersCallBack): Integer;
    function AsyncGetHintText(HintLine, HintCol: Integer; ACallBack: TOTAHintTextCallBack): Integer;
    function AsyncGotoDefinition(const AFileName: string; ALine, ACharIndex: Integer; ACallBack: TOTAGotoDefinitionCallBack): Integer;
    procedure AsyncParameterCodeInsightParamIndex(const AFileName: string; ALine, ACharIndex: Integer; ACallBack: TOTAParamIndexCallBack);
    procedure AsyncOperationCanceled(AId: Integer);
    function ShowCalculating: Boolean;
  end;

  TTestCodeInsightServices = class(TInterfacedObject, IBorlandIDEServices, IOTACodeInsightServices)
  public
    Provider: IOTACodeInsightManager;
    ContextSetCount: Integer;
    ContextResetCount: Integer;
    function SupportsService(const Service: TGUID): Boolean;
    function GetService(const Service: TGUID): IInterface; overload;
    function GetService(const Service: TGUID; out Svc): Boolean; overload;
    function HandlesFile(const AFileName, AIDString: string): Boolean;
    procedure SetQueryContext(const EditView: IOTAEditView; const CodeInsightManager: IOTACodeInsightManager);
    procedure GetEditView(out EditView: IOTAEditView);
    procedure GetViewer(out Viewer: IOTACodeInsightViewer);
    procedure GetCurrentCodeInsightManager(out CodeInsightManager: IOTACodeInsightManager);
    procedure CancelCodeInsightProcessing;
    function AddCodeInsightManager(const ACodeInsightManager: IOTACodeInsightManager): Integer;
    procedure RemoveCodeInsightManager(Index: Integer);
    procedure InsertText(const Str: string; Replace: Boolean);
    function GetCodeInsightManagerCount: Integer;
    function GetCodeInsightManager(Index: Integer): IOTACodeInsightManager;
  end;

  TTestCodeInsightProviderEx = class(TTestCodeInsightProvider, IOTAAsyncCodeInsightManager290, IOTACodeInsightManager90)
  public
    function AsyncGotoDefinitionEx(const AFileName: string; ALine, ACharIndex: Integer; ACallBack: TOTAGotoDefinitionCallBackEx): Integer;
    function GetHelpInsightHtml: WideString;
  end;

implementation

uses
  Winapi.Windows;

procedure TTestEditView.IncreaseDecreaseFontSize(const ActionMode: TOTAIncreaseDecreaseFontSizeMode);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.IncreaseDecreaseFontSize');
end;

function TTestEditView.AddNotifier(const Extension: INTAEditViewNotifier): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.AddNotifier');
end;

procedure TTestEditView.RemoveNotifier(Index: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.RemoveNotifier');
end;

procedure TTestEditView.NavigateToModification(Direction: TSearchDirection; ModificationType: TOTAModificationType);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.NavigateToModification');
end;

procedure TTestEditView.ClearAllBookmarks;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.ClearAllBookmarks');
end;

function TTestEditView.BookmarkGoto(BookmarkID: Integer): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.BookmarkGoto');
end;

function TTestEditView.BookmarkRecord(BookmarkID: Integer): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.BookmarkRecord');
end;

function TTestEditView.BookmarkToggle(BookmarkID: Integer): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.BookmarkToggle');
end;

procedure TTestEditView.Center(Row, Col: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.Center');
end;

function TTestEditView.GetBlock: IOTAEditBlock;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetBlock');
end;

function TTestEditView.GetBookmarkPos(BookmarkID: Integer): TOTACharPos;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetBookmarkPos');
end;

function TTestEditView.GetBottomRow: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetBottomRow');
end;

function TTestEditView.GetBuffer: IOTAEditBuffer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetBuffer');
end;

function TTestEditView.GetEditWindow: INTAEditWindow;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetEditWindow');
end;

function TTestEditView.GetLastEditColumn: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetLastEditColumn');
end;

function TTestEditView.GetLastEditRow: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetLastEditRow');
end;

function TTestEditView.GetLeftColumn: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetLeftColumn');
end;

function TTestEditView.GetPosition: IOTAEditPosition;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetPosition');
end;

function TTestEditView.GetRightColumn: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetRightColumn');
end;

function TTestEditView.GetTopRow: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetTopRow');
end;

procedure TTestEditView.MoveCursorToView;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.MoveCursorToView');
end;

procedure TTestEditView.MoveViewToCursor;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.MoveViewToCursor');
end;

procedure TTestEditView.PageDown;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.PageDown');
end;

procedure TTestEditView.PageUp;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.PageUp');
end;

procedure TTestEditView.Paint;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.Paint');
end;

function TTestEditView.Scroll(DeltaRow: Integer; DeltaCol: Integer): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.Scroll');
end;

procedure TTestEditView.SetTopLeft(TopRow, LeftCol: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.SetTopLeft');
end;

procedure TTestEditView.SetTempMsg(const Msg: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.SetTempMsg');
end;

function TTestEditView.GetCursorPos: TOTAEditPos;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetCursorPos');
end;

procedure TTestEditView.SetCursorPos(const Value: TOTAEditPos);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.SetCursorPos');
end;

function TTestEditView.GetTopPos: TOTAEditPos;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetTopPos');
end;

procedure TTestEditView.SetTopPos(const Value: TOTAEditPos);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.SetTopPos');
end;

function TTestEditView.GetViewSize: TSize;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetViewSize');
end;

function TTestEditView.PosToCharPos(Pos: Longint): TOTACharPos;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.PosToCharPos');
end;

function TTestEditView.CharPosToPos(CharPos: TOTACharPos): Longint;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.CharPosToPos');
end;

procedure TTestEditView.ConvertPos(EdPosToCharPos: Boolean; var EditPos: TOTAEditPos; var CharPos: TOTACharPos);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.ConvertPos');
end;

procedure TTestEditView.GetAttributeAtPos(const EdPos: TOTAEditPos; IncludeMargin: Boolean; var Element, LineFlag: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.GetAttributeAtPos');
end;

function TTestEditView.SameView(const EditView: IOTAEditView): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestEditView.SameView');
end;

procedure TTestSourceEditor.SwitchToView(Index: Integer; const AViewContext: TObject);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SwitchToView');
end;

procedure TTestSourceEditor.SwitchToView(const AViewIdentifier: string; const AViewContext: TObject);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SwitchToView');
end;

function TTestSourceEditor.GetSubViewCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetSubViewCount');
end;

function TTestSourceEditor.GetSubViewIdentifier(Index: Integer): string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetSubViewIdentifier');
end;

function TTestSourceEditor.GetSubViewIndex: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetSubViewIndex');
end;

procedure TTestSourceEditor.SwitchToView(Index: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SwitchToView');
end;

procedure TTestSourceEditor.SwitchToView(const AViewIdentifier: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SwitchToView');
end;

function TTestSourceEditor.CreateReader: IOTAEditReader;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.CreateReader');
end;

function TTestSourceEditor.CreateWriter: IOTAEditWriter;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.CreateWriter');
end;

function TTestSourceEditor.CreateUndoableWriter: IOTAEditWriter;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.CreateUndoableWriter');
end;

function TTestSourceEditor.GetEditViewCount: Integer;
begin
  Result := 1;
end;

function TTestSourceEditor.GetEditView(Index: Integer): IOTAEditView;
begin
  if Index <> 0 then
    raise EArgumentOutOfRangeException.Create('Synthetic editor view index');
  Result := View;
end;

function TTestSourceEditor.GetLinesInBuffer: Longint;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetLinesInBuffer');
end;

function TTestSourceEditor.SetSyntaxHighlighter(SyntaxHighlighter: TOTASyntaxHighlighter): TOTASyntaxHighlighter;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SetSyntaxHighlighter');
end;

function TTestSourceEditor.GetBlockAfter: TOTACharPos;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetBlockAfter');
end;

function TTestSourceEditor.GetBlockStart: TOTACharPos;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetBlockStart');
end;

function TTestSourceEditor.GetBlockType: TOTABlockType;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetBlockType');
end;

function TTestSourceEditor.GetBlockVisible: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetBlockVisible');
end;

procedure TTestSourceEditor.SetBlockAfter(const Value: TOTACharPos);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SetBlockAfter');
end;

procedure TTestSourceEditor.SetBlockStart(const Value: TOTACharPos);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SetBlockStart');
end;

procedure TTestSourceEditor.SetBlockType(Value: TOTABlockType);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SetBlockType');
end;

procedure TTestSourceEditor.SetBlockVisible(Value: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.SetBlockVisible');
end;

function TTestSourceEditor.AddNotifier(const ANotifier: IOTANotifier): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.AddNotifier');
end;

function TTestSourceEditor.GetFileName: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetFileName');
end;

function TTestSourceEditor.GetModified: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetModified');
end;

function TTestSourceEditor.GetModule: IOTAModule;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.GetModule');
end;

function TTestSourceEditor.MarkModified: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.MarkModified');
end;

procedure TTestSourceEditor.RemoveNotifier(Index: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.RemoveNotifier');
end;

procedure TTestSourceEditor.Show;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestSourceEditor.Show');
end;

function TTestCodeInsightProvider.GetOptionSetName: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GetOptionSetName');
end;

function TTestCodeInsightProvider.GetName: string;
begin
  Result := ProviderId;
end;

function TTestCodeInsightProvider.GetIDString: string;
begin
  Result := ProviderId;
end;

function TTestCodeInsightProvider.GetEnabled: Boolean;
begin
  Result := True;
end;

procedure TTestCodeInsightProvider.SetEnabled(Value: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.SetEnabled');
end;

function TTestCodeInsightProvider.EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.EditorTokenValidChars');
end;

procedure TTestCodeInsightProvider.AllowCodeInsight(var Allow: Boolean; const Key: Char);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.AllowCodeInsight');
end;

function TTestCodeInsightProvider.PreValidateCodeInsight(const Str: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.PreValidateCodeInsight');
end;

function TTestCodeInsightProvider.IsViewerBrowsable(Index: Integer): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.IsViewerBrowsable');
end;

function TTestCodeInsightProvider.GetMultiSelect: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GetMultiSelect');
end;

procedure TTestCodeInsightProvider.GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GetSymbolList');
end;

procedure TTestCodeInsightProvider.OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.OnEditorKey');
end;

function TTestCodeInsightProvider.HandlesFile(const AFileName: string): Boolean;
begin
  Result := True;
end;

function TTestCodeInsightProvider.GetLongestItem: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GetLongestItem');
end;

procedure TTestCodeInsightProvider.GetParameterList(out ParameterList: IOTACodeInsightParameterList);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GetParameterList');
end;

procedure TTestCodeInsightProvider.GetCodeInsightType(AChar: Char; AElement: Integer; out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GetCodeInsightType');
end;

function TTestCodeInsightProvider.InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.InvokeCodeCompletion');
end;

function TTestCodeInsightProvider.InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; var SelectedIndex: Integer): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.InvokeParameterCodeInsight');
end;

procedure TTestCodeInsightProvider.ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.ParameterCodeInsightAnchorPos');
end;

function TTestCodeInsightProvider.ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.ParameterCodeInsightParamIndex');
end;

function TTestCodeInsightProvider.GetHintText(HintLine, HintCol: Integer): string;
begin
  Inc(SyncHintCount);
  Result := 'unrelated current editor text';
end;

function TTestCodeInsightProvider.GotoDefinition(out AFileName: string; out ALineNum: Integer; Index: Integer = -1): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.GotoDefinition');
end;

procedure TTestCodeInsightProvider.Done(Accepted: Boolean; out DisplayParams: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.Done');
end;

procedure TTestCodeInsightProvider.AsyncAllowCodeInsight(var AAllow: Boolean; const AKey: Char);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.AsyncAllowCodeInsight');
end;

function TTestCodeInsightProvider.AsyncCanInvoke(AInsightType: TOTACodeInsightType): Boolean;
begin
  Result := AInsightType in [citBrowseCodeInsight, citHintCodeInsight];
end;

function TTestCodeInsightProvider.AsyncEnabled: Boolean;
begin
  Result := True;
end;

function TTestCodeInsightProvider.AsyncInvokeCodeCompletion(AHowInvoked: TOTAInvokeType; var AStr: string; ALine, ACharIndex: Integer;
  ACallback: TOTACodeCompleteCallBack): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.AsyncInvokeCodeCompletion');
end;

function TTestCodeInsightProvider.AsyncInvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; const AFileName: string; ALine, ACharIndex: Integer;
  ACallback: TOTAParametersCallBack): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.AsyncInvokeParameterCodeInsight');
end;

function TTestCodeInsightProvider.AsyncGetHintText(HintLine, HintCol: Integer; ACallBack: TOTAHintTextCallBack): Integer;
begin
  Inc(HintCount);
  Self.HintLine := HintLine;
  HintColumn := HintCol;
  Result := RequestId;
  if Mode = pmTimeout then
    FStoredHints.Add(ACallBack)
  else if Mode = pmDeferred then
  begin
    JoinWorker;
    FWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(15);
        if Assigned(BeforeAsyncCallback) then
          TThread.Synchronize(nil, BeforeAsyncCallback);
        ACallBack(Self, RequestId, HintText, False, '');
      end);
    FWorker.FreeOnTerminate := False;
    FWorker.Start;
  end
  else
  begin
    if Assigned(LateProvider) then
    begin
      LateProvider.DeliverStoredHints;
      LateProvider := nil;
    end;
    ACallBack(Self, RequestId, HintText, Mode = pmError, '');
  end;
end;

function TTestCodeInsightProvider.AsyncGotoDefinition(const AFileName: string; ALine, ACharIndex: Integer; ACallBack: TOTAGotoDefinitionCallBack): Integer;
begin
  Result := InvokeDefinition(ALine, ACharIndex, ACallBack, nil);
end;

procedure TTestCodeInsightProvider.AsyncParameterCodeInsightParamIndex(const AFileName: string; ALine, ACharIndex: Integer; ACallBack: TOTAParamIndexCallBack);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.AsyncParameterCodeInsightParamIndex');
end;

procedure TTestCodeInsightProvider.AsyncOperationCanceled(AId: Integer);
begin
  Inc(CancelCount);
  CancelledId := AId;
end;

function TTestCodeInsightProvider.ShowCalculating: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightProvider.ShowCalculating');
end;

function TTestCodeInsightServices.SupportsService(const Service: TGUID): Boolean;
var
  LService: IInterface;
begin
  Result := QueryInterface(Service, LService) = 0;
end;

function TTestCodeInsightServices.GetService(const Service: TGUID): IInterface;
begin
  if QueryInterface(Service, Result) <> 0 then
    Result := nil;
end;

function TTestCodeInsightServices.GetService(const Service: TGUID; out Svc): Boolean;
begin
  Result := QueryInterface(Service, Svc) = 0;
end;

function TTestCodeInsightServices.HandlesFile(const AFileName, AIDString: string): Boolean;
begin
  Result := Assigned(Provider) and (AIDString = Provider.GetIDString);
end;

procedure TTestCodeInsightServices.SetQueryContext(const EditView: IOTAEditView; const CodeInsightManager: IOTACodeInsightManager);
begin
  if Assigned(EditView) and Assigned(CodeInsightManager) then
    Inc(ContextSetCount)
  else if not Assigned(EditView) and not Assigned(CodeInsightManager) then
    Inc(ContextResetCount)
  else
    raise EInvalidOperation.Create('Synthetic context must set or clear both interfaces');
end;

procedure TTestCodeInsightServices.GetEditView(out EditView: IOTAEditView);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightServices.GetEditView');
end;

procedure TTestCodeInsightServices.GetViewer(out Viewer: IOTACodeInsightViewer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightServices.GetViewer');
end;

procedure TTestCodeInsightServices.GetCurrentCodeInsightManager(out CodeInsightManager: IOTACodeInsightManager);
begin
  CodeInsightManager := Provider;
end;

procedure TTestCodeInsightServices.CancelCodeInsightProcessing;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightServices.CancelCodeInsightProcessing');
end;

function TTestCodeInsightServices.AddCodeInsightManager(const ACodeInsightManager: IOTACodeInsightManager): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightServices.AddCodeInsightManager');
end;

procedure TTestCodeInsightServices.RemoveCodeInsightManager(Index: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightServices.RemoveCodeInsightManager');
end;

procedure TTestCodeInsightServices.InsertText(const Str: string; Replace: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestCodeInsightServices.InsertText');
end;

function TTestCodeInsightServices.GetCodeInsightManagerCount: Integer;
begin
  Result := Ord(Assigned(Provider));
end;

function TTestCodeInsightServices.GetCodeInsightManager(Index: Integer): IOTACodeInsightManager;
begin
  if Index <> 0 then
    raise EArgumentOutOfRangeException.Create('Synthetic provider index');
  Result := Provider;
end;

constructor TTestCodeInsightProvider.Create(const AProviderId: string);
begin
  inherited Create;
  ProviderId := AProviderId;
  RequestId := 41;
  Mode := pmImmediate;
  ReplyFile := 'C:\SyntheticDAICodeInsight\' + AProviderId + '.pas';
  ReplyLine := 12;
  ReplyCharacter := 7;
  HintText := 'synthetic position-specific hint';
  FStoredDefinitions := TList<TStoredDefinition>.Create;
  FStoredHints := TList<TOTAHintTextCallBack>.Create;
end;

destructor TTestCodeInsightProvider.Destroy;
begin
  JoinWorker;
  DeliverStoredDefinitions;
  DeliverStoredHints;
  FStoredHints.Free;
  FStoredDefinitions.Free;
  inherited;
end;

procedure DeliverDefinition(const ASender: TObject; const ACall: TStoredDefinition; const AFile: string; ALine, ACharacter: Integer; AError: Boolean);
begin
  if Assigned(ACall.CallbackEx) then
    ACall.CallbackEx(ASender, ACall.RequestId, AFile, ALine, ACharacter, AError, '')
  else
    ACall.Callback(ASender, ACall.RequestId, AFile, ALine, AError, '');
end;

function TTestCodeInsightProvider.InvokeDefinition(ALine, ACharacter: Integer; ACallback: TOTAGotoDefinitionCallBack;
  ACallbackEx: TOTAGotoDefinitionCallBackEx): Integer;
var
  LCall: TStoredDefinition;
begin
  Inc(DefinitionCount);
  InputLine := ALine;
  InputCharacter := ACharacter;
  LCall := Default(TStoredDefinition);
  LCall.RequestId := RequestId;
  LCall.Callback := ACallback;
  LCall.CallbackEx := ACallbackEx;
  Result := RequestId;
  if Mode in [pmTimeout, pmRaiseAfterCapture] then
  begin
    FStoredDefinitions.Add(LCall);
    if Mode = pmRaiseAfterCapture then
      raise EInvalidOperation.Create('Synthetic provider keeps callback after invocation failure');
    Exit;
  end;
  if Assigned(LateProvider) then
  begin
    // Deliver the old result before the new request's returned ID is registered.
    LateProvider.DeliverStoredDefinitions;
    LateProvider := nil;
  end;
  if Mode = pmDeferred then
  begin
    JoinWorker;
    FWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(15);
        DeliverDefinition(Self, LCall, ReplyFile, ReplyLine, ReplyCharacter, False);
      end);
    FWorker.FreeOnTerminate := False;
    FWorker.Start;
  end
  else
    DeliverDefinition(Self, LCall, ReplyFile, ReplyLine, ReplyCharacter, Mode = pmError);
end;

function TTestCodeInsightProvider.GetStoredDefinitionCount: Integer;
begin
  Result := FStoredDefinitions.Count;
end;

function TTestCodeInsightProvider.GetStoredHintCount: Integer;
begin
  Result := FStoredHints.Count;
end;

procedure TTestCodeInsightProvider.DeliverStoredDefinitions;
var
  LCall: TStoredDefinition;
begin
  while FStoredDefinitions.Count > 0 do
  begin
    LCall := FStoredDefinitions[0];
    FStoredDefinitions.Delete(0);
    DeliverDefinition(Self, LCall, 'C:\SyntheticDAICodeInsight\StaleReply.pas', 999, 999, False);
  end;
end;

procedure TTestCodeInsightProvider.DeliverStoredHints;
var
  LCallback: TOTAHintTextCallBack;
begin
  while FStoredHints.Count > 0 do
  begin
    LCallback := FStoredHints[0];
    FStoredHints.Delete(0);
    LCallback(Self, RequestId, 'stale help text', False, '');
  end;
end;

procedure TTestCodeInsightProvider.JoinWorker;
begin
  if Assigned(FWorker) then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
end;

function TTestCodeInsightProviderEx.AsyncGotoDefinitionEx(const AFileName: string; ALine, ACharIndex: Integer;
  ACallBack: TOTAGotoDefinitionCallBackEx): Integer;
begin
  Result := InvokeDefinition(ALine, ACharIndex, nil, ACallBack);
end;

function TTestCodeInsightProviderEx.GetHelpInsightHtml: WideString;
begin
  Inc(HtmlViewerCount);
  Result := '<p>unrelated selected viewer item</p>';
end;

end.
