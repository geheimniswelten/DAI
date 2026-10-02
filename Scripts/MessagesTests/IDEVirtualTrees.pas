unit IDEVirtualTrees;

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls;

type
  TVirtualNode = record
    Reserved: Byte;
  end;
  PVirtualNode = ^TVirtualNode;

  TVirtualTreeColumns = class(TCollection);

  TVTHeader = class(TPersistent)
  private
    FColumns: TVirtualTreeColumns;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Columns: TVirtualTreeColumns read FColumns;
  end;

  TBaseVirtualTree = class(TCustomControl)
  private
    FNodes: TList<TObject>;
    FHeader: TVTHeader;
  public
    TextCalls: Integer;
    NavigationCalls: Integer;
    TextDelay: Integer;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddLine(const AText: WideString);
    procedure AddColumns(const ATexts: array of WideString);
    function GetFirst: PVirtualNode;
    function GetLast(ANode: PVirtualNode): PVirtualNode;
    function GetNext(ANode: PVirtualNode): PVirtualNode;
    function GetPrevious(ANode: PVirtualNode): PVirtualNode;
    function GetTotalCount: Cardinal;
    function AbsoluteIndex(ANode: PVirtualNode): Cardinal;
    function ReadText(ANode: PVirtualNode; AColumn: Integer): WideString;
  published
    property Header: TVTHeader read FHeader;
  end;

  TCustomVirtualStringTree = class(TBaseVirtualTree)
  public
    function GetText(ANode: PVirtualNode; AColumn: Integer): WideString;
  end;

  TVirtualStringTree = class(TCustomVirtualStringTree);

  TZombieTestableVirtualDrawTree = class(TBaseVirtualTree)
  public
    function ZombieGetText(ANode: PVirtualNode; AColumn: Integer): WideString;
  end;

  TBetterHintWindowVirtualDrawTree = class(TZombieTestableVirtualDrawTree);

implementation

uses
  System.SysUtils,
  Winapi.Windows;

type
  TFixtureNode = class
  public
    Index: Cardinal;
    Texts: TArray<WideString>;
  end;

constructor TVTHeader.Create;
begin
  inherited;
  FColumns := TVirtualTreeColumns.Create(TCollectionItem);
end;

destructor TVTHeader.Destroy;
begin
  FColumns.Free;
  inherited;
end;

constructor TBaseVirtualTree.Create(AOwner: TComponent);
begin
  inherited;
  FNodes := TList<TObject>.Create;
  FHeader := TVTHeader.Create;
  FHeader.Columns.Add;
end;

destructor TBaseVirtualTree.Destroy;
var
  LNode: TObject;
begin
  for LNode in FNodes do
    LNode.Free;
  FNodes.Free;
  FHeader.Free;
  inherited;
end;

procedure TBaseVirtualTree.AddLine(const AText: WideString);
begin
  AddColumns([AText]);
end;

procedure TBaseVirtualTree.AddColumns(const ATexts: array of WideString);
var
  LNode: TFixtureNode;
  LIndex: Integer;
begin
  LNode := TFixtureNode.Create;
  LNode.Index := FNodes.Count;
  SetLength(LNode.Texts, Length(ATexts));
  for LIndex := 0 to High(ATexts) do
    LNode.Texts[LIndex] := ATexts[LIndex];
  FNodes.Add(LNode);
end;

function TBaseVirtualTree.GetFirst: PVirtualNode;
begin
  Inc(NavigationCalls);
  Result := nil;
  if FNodes.Count > 0 then
    Result := PVirtualNode(FNodes[0]);
end;

function TBaseVirtualTree.GetLast(ANode: PVirtualNode): PVirtualNode;
begin
  Inc(NavigationCalls);
  if Assigned(ANode) then
    raise EArgumentException.Create('Fixture GetLast only accepts the whole-tree request.');
  Result := nil;
  if FNodes.Count > 0 then
    Result := PVirtualNode(FNodes.Last);
end;

function TBaseVirtualTree.GetNext(ANode: PVirtualNode): PVirtualNode;
var
  LIndex: Cardinal;
begin
  Inc(NavigationCalls);
  LIndex := AbsoluteIndex(ANode);
  Result := nil;
  if LIndex + 1 < Cardinal(FNodes.Count) then
    Result := PVirtualNode(FNodes[LIndex + 1]);
end;

function TBaseVirtualTree.GetPrevious(ANode: PVirtualNode): PVirtualNode;
var
  LIndex: Cardinal;
begin
  Inc(NavigationCalls);
  LIndex := AbsoluteIndex(ANode);
  Result := nil;
  if LIndex > 0 then
    Result := PVirtualNode(FNodes[LIndex - 1]);
end;

function TBaseVirtualTree.GetTotalCount: Cardinal;
begin
  Result := FNodes.Count;
end;

function TBaseVirtualTree.AbsoluteIndex(ANode: PVirtualNode): Cardinal;
begin
  // This is the producer's own node object, never foreign IDE data.
  Result := TFixtureNode(ANode).Index;
end;

function TBaseVirtualTree.ReadText(ANode: PVirtualNode; AColumn: Integer): WideString;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('Tree text getter called outside the main thread.');
  Inc(TextCalls);
  if TextDelay > 0 then
    Sleep(TextDelay);
  if AColumn = -1 then
  begin
    if FHeader.Columns.Count <> 0 then
      raise EArgumentException.Create('NoColumn is only valid without explicit columns.');
    AColumn := 0;
  end;
  Result := TFixtureNode(ANode).Texts[AColumn];
end;

function TCustomVirtualStringTree.GetText(ANode: PVirtualNode; AColumn: Integer): WideString;
begin
  Result := ReadText(ANode, AColumn);
end;

function TZombieTestableVirtualDrawTree.ZombieGetText(ANode: PVirtualNode; AColumn: Integer): WideString;
begin
  Result := ReadText(ANode, AColumn);
end;

end.
