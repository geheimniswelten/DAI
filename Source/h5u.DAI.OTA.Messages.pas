unit h5u.DAI.OTA.Messages;

interface

uses
  System.JSON;

type
  TDAIMessageService = class sealed
  public
    class function Read(const ASource: string; const ALastCount: Integer = 50; const AIndex: Integer = -1; const AMaximumCharacters: Integer = 20000): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.SysUtils,
  System.TypInfo,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Tabs,
  Winapi.Windows,
  h5u.DAI.OTA.Helpers;

type
  // Opaque Virtual Treeview node handles. No node/user-data layout is accessed.
  TVTFirstMethod = function: Pointer of object;
  TVTNodeMethod = function(ANode: Pointer): Pointer of object;
  TVTCountMethod = function: Cardinal of object;
  TVTIndexMethod = function(ANode: Pointer): Cardinal of object;
  TVTTextMethod = function(ANode: Pointer; AColumn: Integer): WideString of object;

  TVTReadAdapter = record
    First: TVTFirstMethod;
    Last: TVTNodeMethod;
    Next: TVTNodeMethod;
    Previous: TVTNodeMethod;
    Count: TVTCountMethod;
    Index: TVTIndexMethod;
    Text: TVTTextMethod;
  end;

const
  CMaximumRows = 1000;
  CMaximumColumns = 32;
  CMaximumCharacters = 200000;
  CReadBudgetMilliseconds = 250;
  CTreeModuleName = 'vclide370.bpl';
  {$IFDEF WIN64}
  CFirstExport = '_ZN15Idevirtualtrees16TBaseVirtualTree8GetFirstEv';
  CLastExport = '_ZN15Idevirtualtrees16TBaseVirtualTree7GetLastEPNS_12TVirtualNodeE';
  CNextExport = '_ZN15Idevirtualtrees16TBaseVirtualTree7GetNextEPNS_12TVirtualNodeE';
  CPreviousExport = '_ZN15Idevirtualtrees16TBaseVirtualTree11GetPreviousEPNS_12TVirtualNodeE';
  CCountExport = '_ZN15Idevirtualtrees16TBaseVirtualTree13GetTotalCountEv';
  CIndexExport = '_ZN15Idevirtualtrees16TBaseVirtualTree13AbsoluteIndexEPNS_12TVirtualNodeE';
  CStringTextExport = '_ZN15Idevirtualtrees24TCustomVirtualStringTree7GetTextEPNS_12TVirtualNodeEi';
  CDrawTextExport = '_ZN15Idevirtualtrees30TZombieTestableVirtualDrawTree13ZombieGetTextEPNS_12TVirtualNodeEi';
  {$ELSE}
  CFirstExport = '@Idevirtualtrees@TBaseVirtualTree@GetFirst$qqrv';
  CLastExport = '@Idevirtualtrees@TBaseVirtualTree@GetLast$qqrp28Idevirtualtrees@TVirtualNode';
  CNextExport = '@Idevirtualtrees@TBaseVirtualTree@GetNext$qqrp28Idevirtualtrees@TVirtualNode';
  CPreviousExport = '@Idevirtualtrees@TBaseVirtualTree@GetPrevious$qqrp28Idevirtualtrees@TVirtualNode';
  CCountExport = '@Idevirtualtrees@TBaseVirtualTree@GetTotalCount$qqrv';
  CIndexExport = '@Idevirtualtrees@TBaseVirtualTree@AbsoluteIndex$qqrp28Idevirtualtrees@TVirtualNode';
  CStringTextExport = '@Idevirtualtrees@TCustomVirtualStringTree@GetText$qqrp28Idevirtualtrees@TVirtualNodei';
  CDrawTextExport = '@Idevirtualtrees@TZombieTestableVirtualDrawTree@ZombieGetText$qqrp28Idevirtualtrees@TVirtualNodei';
  {$ENDIF}

var
  GReadLock: TObject;

function AncestorClass(const AObject: TObject; const AClassName: string): TClass;
var
  LClass: TClass;
begin
  Result := nil;
  if not Assigned(AObject) then
    Exit;
  LClass := AObject.ClassType;
  while Assigned(LClass) do
  begin
    if SameText(LClass.ClassName, AClassName) then
      Exit(LClass);
    LClass := LClass.ClassParent;
  end;
end;

function KnownForm(const AName: string; const AClassName: string): TCustomForm;
var
  LForm: TCustomForm;
  LIndex: Integer;
begin
  Result := nil;
  for LIndex := 0 to Screen.CustomFormCount - 1 do
  begin
    LForm := Screen.CustomForms[LIndex];
    if SameText(LForm.Name, AName) and SameText(LForm.ClassName, AClassName) then
    begin
      if csDestroying in LForm.ComponentState then
        Continue;
      if Assigned(Result) then
        raise EInvalidOperation.Create('Mehrere gleichnamige IDE-Logfenster verhindern eine eindeutige Auswahl.');
      Result := LForm;
    end;
  end;
end;

function AdapterDetails(const AForm: TCustomForm; const ATree: TComponent; const AReason: string): TJSONObject;
var
  LAncestors: TJSONArray;
  LClass: TClass;
  LCount: Integer;
  LExports: TJSONObject;
  LModule: HMODULE;

  procedure ExportFlag(const AName: string; const AExport: AnsiString);
  begin
    LExports.AddPair(AName, TJSONBool.Create((LModule <> 0) and Assigned(GetProcAddress(LModule, PAnsiChar(AExport)))));
  end;

begin
  Result := TJSONObject.Create;
  Result.AddPair('reason', AReason);
  if Assigned(AForm) then
    Result.AddPair('form_class', AForm.ClassName)
  else
    Result.AddPair('form_class', '');
  if Assigned(ATree) then
    Result.AddPair('control_class', ATree.ClassName)
  else
    Result.AddPair('control_class', '');
  LAncestors := TJSONArray.Create;
  if Assigned(ATree) then
  begin
    LClass := ATree.ClassType;
    LCount := 0;
    while Assigned(LClass) and (LCount < 20) do
    begin
      LAncestors.Add(LClass.ClassName);
      LClass := LClass.ClassParent;
      Inc(LCount);
    end;
  end;
  Result.AddPair('ancestors', LAncestors);
  LModule := GetModuleHandle(CTreeModuleName);
  LExports := TJSONObject.Create;
  ExportFlag('get_first', CFirstExport);
  ExportFlag('get_last', CLastExport);
  ExportFlag('get_next', CNextExport);
  ExportFlag('get_previous', CPreviousExport);
  ExportFlag('get_total_count', CCountExport);
  ExportFlag('absolute_index', CIndexExport);
  ExportFlag('string_get_text', CStringTextExport);
  ExportFlag('draw_get_text', CDrawTextExport);
  Result.AddPair('exports_available', LExports);
end;

function BindAdapter(const ATree: TComponent; out AAdapter: TVTReadAdapter; out AReason: string): Boolean;
var
  LModule: HMODULE;
  LTextExport: AnsiString;
  LBaseClass: TClass;
  LTextClass: TClass;

  function BoundMethod(const AExport: AnsiString): TMethod;
  begin
    Result.Code := GetProcAddress(LModule, PAnsiChar(AExport));
    Result.Data := ATree;
  end;

begin
  AAdapter := Default(TVTReadAdapter);
  AReason := '';
  Result := False;
  if Assigned(ATree) then
    if csDestroying in ATree.ComponentState then
    begin
      AReason := 'Die IDE-Logkontrolle wird bereits abgebaut.';
      Exit;
    end;
  LBaseClass := AncestorClass(ATree, 'TBaseVirtualTree');
  if not Assigned(LBaseClass) then
  begin
    AReason := 'Die bekannte IDE-Logkontrolle ist kein unterstützter virtueller Baum.';
    Exit;
  end;
  LTextClass := AncestorClass(ATree, 'TCustomVirtualStringTree');
  if Assigned(LTextClass) then
    LTextExport := CStringTextExport
  else
  begin
    LTextClass := AncestorClass(ATree, 'TZombieTestableVirtualDrawTree');
    LTextExport := CDrawTextExport;
  end;
  if not Assigned(LTextClass) then
  begin
    AReason := 'Für diesen Zeichenbaum ist kein verifizierter Textgetter verfügbar.';
    Exit;
  end;
  // Only an already loaded Delphi 13 IDE module is used. No package is loaded,
  // no private field layout is reproduced, and no node data is dereferenced.
  LModule := GetModuleHandle(CTreeModuleName);
  if LModule = 0 then
  begin
    AReason := 'Das Delphi-13-Modul mit den verifizierten Baum-Gettern ist nicht geladen.';
    Exit;
  end;
  if (System.FindClassHInstance(LBaseClass) <> LModule) or (System.FindClassHInstance(LTextClass) <> LModule) then
  begin
    AReason := 'Die Baumklassen stammen nicht aus dem Modul mit der verifizierten Delphi-13-ABI.';
    Exit;
  end;
  AAdapter.First := TVTFirstMethod(BoundMethod(CFirstExport));
  AAdapter.Last := TVTNodeMethod(BoundMethod(CLastExport));
  AAdapter.Next := TVTNodeMethod(BoundMethod(CNextExport));
  AAdapter.Previous := TVTNodeMethod(BoundMethod(CPreviousExport));
  AAdapter.Count := TVTCountMethod(BoundMethod(CCountExport));
  AAdapter.Index := TVTIndexMethod(BoundMethod(CIndexExport));
  AAdapter.Text := TVTTextMethod(BoundMethod(LTextExport));
  Result := Assigned(AAdapter.First) and Assigned(AAdapter.Last) and Assigned(AAdapter.Next) and Assigned(AAdapter.Previous) and
    Assigned(AAdapter.Count) and Assigned(AAdapter.Index) and Assigned(AAdapter.Text);
  if not Result then
    AReason := 'Mindestens ein verifizierter Baum-Getter fehlt im geladenen IDE-Modul.';
end;

function ReadColumnInfo(const ATree: TComponent; out AFirstColumn: Integer; out AColumnCount: Integer; out AReason: string): Boolean;
var
  LColumns: TObject;
  LColumnsClass: TClass;
  LHeader: TObject;
  LHeaderClass: TClass;
  LModule: HMODULE;
  LProperty: PPropInfo;
begin
  Result := False;
  AFirstColumn := 0;
  AColumnCount := 0;
  AReason := 'Die öffentlichen Header-/Spaltenmetadaten des bekannten Logbaums sind nicht verfügbar.';
  LProperty := GetPropInfo(ATree, 'Header');
  if not Assigned(LProperty) then
  begin
    AReason := 'Die bekannte IDE-Logkontrolle veröffentlicht keine Header-Eigenschaft.';
    Exit;
  end;
  if LProperty.PropType^.Kind <> tkClass then
    Exit;
  LHeader := GetObjectProp(ATree, LProperty);
  LHeaderClass := AncestorClass(LHeader, 'TVTHeader');
  if not Assigned(LHeaderClass) then
    Exit;
  LModule := GetModuleHandle(CTreeModuleName);
  if System.FindClassHInstance(LHeaderClass) <> LModule then
    Exit;
  LProperty := GetPropInfo(LHeader, 'Columns');
  if not Assigned(LProperty) then
  begin
    AReason := 'Der bekannte IDE-Logheader veröffentlicht keine Columns-Eigenschaft.';
    Exit;
  end;
  if LProperty.PropType^.Kind <> tkClass then
    Exit;
  LColumns := GetObjectProp(LHeader, LProperty);
  if not (LColumns is TCollection) then
    Exit;
  LColumnsClass := AncestorClass(LColumns, 'TVirtualTreeColumns');
  if not Assigned(LColumnsClass) then
    Exit;
  if System.FindClassHInstance(LColumnsClass) <> LModule then
    Exit;
  AColumnCount := TCollection(LColumns).Count;
  if AColumnCount > CMaximumColumns then
  begin
    AReason := 'Die Spaltenzahl des IDE-Logbaums überschreitet die unterstützte Lesegrenze.';
    Exit;
  end;
  // Virtual Treeview uses NoColumn=-1 for its implicit column when Header.Columns is empty.
  if AColumnCount = 0 then
  begin
    AFirstColumn := -1;
    AColumnCount := 1;
  end;
  AReason := '';
  Result := True;
end;

function PrefixWithinLimit(const AText: string; const AMaximum: Integer): string;
var
  LCount: Integer;
begin
  LCount := Min(Length(AText), AMaximum);
  if LCount > 0 then
    if LCount < Length(AText) then
      if (Ord(AText[LCount]) >= $D800) and (Ord(AText[LCount]) <= $DBFF) then
        Dec(LCount);
  Result := Copy(AText, 1, LCount);
end;

function SelectTree(const ASource: string; out AForm: TCustomForm; out ATree: TComponent; out AGroupIndex: Integer; out AGroupName: string; out AReason: string): Boolean;
var
  LComponent: TComponent;
  LIndex: Integer;
  LTabs: TTabSet;
  LText: string;
begin
  Result := False;
  AForm := nil;
  ATree := nil;
  AGroupIndex := -1;
  AGroupName := '';
  AReason := '';
  if ASource = 'events' then
  begin
    AForm := KnownForm('DebugLogView', 'TDebugLogView');
    if Assigned(AForm) then
      ATree := AForm.FindComponent('LogTree');
  end
  else
  begin
    AForm := KnownForm('MessageViewForm', 'TMessageViewForm');
    if Assigned(AForm) then
    begin
      ATree := AForm.FindComponent('MessageTreeView0');
      LComponent := AForm.FindComponent('MessageGroups');
      if not (LComponent is TTabSet) then
      begin
        AReason := 'Die öffentliche IDE-Meldungsgruppenliste ist nicht verfügbar.';
        Exit;
      end;
      LTabs := TTabSet(LComponent);
      if csDestroying in LTabs.ComponentState then
      begin
        AReason := 'Die IDE-Meldungsgruppenliste wird bereits abgebaut.';
        Exit;
      end;
      for LIndex := 0 to LTabs.Tabs.Count - 1 do
      begin
        LText := Trim(StringReplace(LTabs.Tabs[LIndex], '&', '', [rfReplaceAll]));
        if SameText(LText, 'Build') or SameText(LText, 'Erzeugen') then
        begin
          if AGroupIndex >= 0 then
          begin
            AReason := 'Die Build-Meldungsgruppe ist nicht eindeutig.';
            Exit;
          end;
          AGroupIndex := LIndex;
          AGroupName := LTabs.Tabs[LIndex];
        end;
      end;
      if AGroupIndex < 0 then
      begin
        AReason := 'Der Build-Tab wurde anhand der unterstützten IDE-Beschriftungen nicht eindeutig gefunden.';
        Exit;
      end;
      ATree := AForm.FindComponent('MessageTreeView' + IntToStr(AGroupIndex));
    end;
  end;
  if not Assigned(AForm) then
    AReason := 'Das bekannte IDE-Logfenster ist nicht erstellt.'
  else if not Assigned(ATree) then
    AReason := 'Die bekannte IDE-Logkontrolle ist nicht erstellt.'
  else
    Result := True;
end;

class function TDAIMessageService.Read(const ASource: string; const ALastCount: Integer; const AIndex: Integer; const AMaximumCharacters: Integer): TJSONObject;
var
  LResult: TJSONObject;
  LSource: string;
begin
  LSource := LowerCase(Trim(ASource));
  if (LSource <> 'build') and (LSource <> 'events') then
    raise EArgumentException.Create('Der Parameter "source" muss "build" oder "events" sein.');
  if (ALastCount < 1) or (ALastCount > CMaximumRows) then
    raise EArgumentOutOfRangeException.CreateFmt('Der Parameter "last_count" muss zwischen 1 und %d liegen.', [CMaximumRows]);
  if AIndex < -1 then
    raise EArgumentOutOfRangeException.Create('Der Parameter "index" darf nicht kleiner als -1 sein.');
  if (AMaximumCharacters < 1) or (AMaximumCharacters > CMaximumCharacters) then
    raise EArgumentOutOfRangeException.CreateFmt('Der Parameter "maximum_characters" muss zwischen 1 und %d liegen.', [CMaximumCharacters]);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LAdapter: TVTReadAdapter;
        LAvailable: Boolean;
        LBudget: Integer;
        LColumn: Integer;
        LColumnCount: Integer;
        LColumnInfo: TJSONObject;
        LColumnItems: TJSONArray;
        LFirstColumn: Integer;
        LJoinedText: string;
        LOriginalLength: Integer;
        LOriginalRowLength: Int64;
        LColumnsComplete: Boolean;
        LSelectionComplete: Boolean;
        LCount: Cardinal;
        LDeadline: UInt64;
        LForm: TCustomForm;
        LGroupIndex: Integer;
        LGroupName: string;
        LIndex: Cardinal;
        LForward: Boolean;
        LSelected: Boolean;
        LItem: TJSONObject;
        LItems: TJSONArray;
        LNeeded: Integer;
        LNode: Pointer;
        LReason: string;
        LRows: TObjectList<TJSONObject>;
        LSelectedIndex: Integer;
        LText: string;
        LTextCut: Boolean;
        LTimedOut: Boolean;
        LTree: TComponent;
      begin
        System.TMonitor.Enter(GReadLock);
        try
          LItems := TJSONArray.Create;
          LResult.AddPair('source', LSource);
          LResult.AddPair('backend', 'IDE Virtual Treeview; verifizierte Delphi-13-Getter');
          LResult.AddPair('index_base', TJSONNumber.Create(0));
          LResult.AddPair('last_count', TJSONNumber.Create(ALastCount));
          LResult.AddPair('requested_index', TJSONNumber.Create(AIndex));
          LResult.AddPair('maximum_characters', TJSONNumber.Create(AMaximumCharacters));
          LAvailable := SelectTree(LSource, LForm, LTree, LGroupIndex, LGroupName, LReason);
          if LAvailable then
            LAvailable := BindAdapter(LTree, LAdapter, LReason);
          if LAvailable then
            LAvailable := ReadColumnInfo(LTree, LFirstColumn, LColumnCount, LReason);
          LResult.AddPair('group_index', TJSONNumber.Create(LGroupIndex));
          LResult.AddPair('group_name', LGroupName);
          LResult.AddPair('available', TJSONBool.Create(LAvailable));
          LResult.AddPair('messages', LItems);
          if not LAvailable then
          begin
            LResult.AddPair('success', TJSONBool.Create(False));
            LResult.AddPair('total_count', TJSONNull.Create);
            LResult.AddPair('returned_count', TJSONNumber.Create(0));
            LResult.AddPair('truncated', TJSONBool.Create(False));
            LResult.AddPair('message', LReason);
            LResult.AddPair('adapter_details', AdapterDetails(LForm, LTree, LReason));
            Exit;
          end;
          LResult.AddPair('column_count', TJSONNumber.Create(LColumnCount));
          LResult.AddPair('column_offset_unit', 'UTF-16 code units; zero-based');
          LCount := LAdapter.Count();
          if (AIndex >= 0) and (Cardinal(AIndex) >= LCount) then
            raise EArgumentOutOfRangeException.CreateFmt('Der Meldungsindex %d liegt außerhalb der %d vorhandenen Zeilen.', [AIndex, LCount]);
          LResult.AddPair('total_count', TJSONNumber.Create(Int64(LCount)));
          LDeadline := GetTickCount64 + CReadBudgetMilliseconds;
          LBudget := AMaximumCharacters;
          LTimedOut := False;
          LTextCut := False;
          LSelectionComplete := True;
          LRows := TObjectList<TJSONObject>.Create(True);
          try
            if LCount > 0 then
            begin
              LForward := False;
              if AIndex >= 0 then
                LForward := Cardinal(AIndex) < LCount div 2;
              if LForward then
                LNode := LAdapter.First()
              else
                LNode := LAdapter.Last(nil);
              if AIndex >= 0 then
                LNeeded := 1
              else
                LNeeded := Min(Int64(LCount), ALastCount);
              while Assigned(LNode) and (LNeeded > 0) do
              begin
                if GetTickCount64 >= LDeadline then
                begin
                  LTimedOut := True;
                  Break;
                end;
                LIndex := LAdapter.Index(LNode);
                if AIndex < 0 then
                  LSelected := True
                else
                  LSelected := LIndex = Cardinal(AIndex);
                if LSelected then
                begin
                  LItem := TJSONObject.Create;
                  LRows.Add(LItem);
                  LColumnItems := TJSONArray.Create;
                  LItem.AddPair('columns', LColumnItems);
                  LItem.AddPair('index', TJSONNumber.Create(Int64(LIndex)));
                  LJoinedText := '';
                  LOriginalRowLength := 0;
                  LColumnsComplete := True;
                  for LColumn := 0 to LColumnCount - 1 do
                  begin
                    if GetTickCount64 >= LDeadline then
                    begin
                      LTimedOut := True;
                      LColumnsComplete := False;
                      Break;
                    end;
                    if LColumn > 0 then
                    begin
                      if LBudget < 2 then
                      begin
                        LColumnsComplete := False;
                        Break;
                      end;
                      LJoinedText := LJoinedText + #9;
                      Inc(LOriginalRowLength);
                      Dec(LBudget);
                    end;
                    LText := string(LAdapter.Text(LNode, LFirstColumn + LColumn));
                    LOriginalLength := Length(LText);
                    Inc(LOriginalRowLength, LOriginalLength);
                    LText := PrefixWithinLimit(LText, LBudget);
                    LColumnInfo := TJSONObject.Create;
                    LColumnItems.AddElement(LColumnInfo);
                    LColumnInfo.AddPair('column', TJSONNumber.Create(LFirstColumn + LColumn));
                    LColumnInfo.AddPair('text_start', TJSONNumber.Create(Length(LJoinedText)));
                    LColumnInfo.AddPair('text_length', TJSONNumber.Create(Length(LText)));
                    LColumnInfo.AddPair('original_text_length', TJSONNumber.Create(LOriginalLength));
                    LColumnInfo.AddPair('text_truncated', TJSONBool.Create(Length(LText) < LOriginalLength));
                    LTextCut := LTextCut or (Length(LText) < LOriginalLength);
                    LJoinedText := LJoinedText + LText;
                    Dec(LBudget, Length(LText));
                  end;
                  if LColumnsComplete then
                    LItem.AddPair('text_length', TJSONNumber.Create(LOriginalRowLength))
                  else
                    LItem.AddPair('text_length', TJSONNull.Create);
                  LItem.AddPair('text', LJoinedText);
                  LItem.AddPair('columns_complete', TJSONBool.Create(LColumnsComplete));
                  LItem.AddPair('text_truncated', TJSONBool.Create((LOriginalRowLength > Length(LJoinedText)) or not LColumnsComplete));
                  LTextCut := LTextCut or not LColumnsComplete;
                  Dec(LNeeded);
                  if LBudget <= 0 then
                    Break;
                end;
                if LForward then
                  LNode := LAdapter.Next(LNode)
                else
                  LNode := LAdapter.Previous(LNode);
              end;
              if (AIndex >= 0) and (LNeeded > 0) then
                LSelectionComplete := False;
            end;
            // The tail is collected backward, then returned in original order.
            while LRows.Count > 0 do
            begin
              LSelectedIndex := LRows.Count - 1;
              LItems.AddElement(LRows.Extract(LRows[LSelectedIndex]));
            end;
          finally
            LRows.Free;
          end;
          LResult.AddPair('returned_count', TJSONNumber.Create(LItems.Count));
          LResult.AddPair('truncated', TJSONBool.Create((Int64(LItems.Count) < LCount) or LTextCut or LTimedOut));
          LResult.AddPair('text_truncated', TJSONBool.Create(LTextCut));
          LResult.AddPair('timed_out', TJSONBool.Create(LTimedOut));
          LResult.AddPair('success', TJSONBool.Create(not LTimedOut and LSelectionComplete));
          LResult.AddPair('order', 'oldest_to_newest');
          if not LSelectionComplete then
            LResult.AddPair('message', 'Der angeforderte Originalindex war während des Lesens nicht mehr verfügbar.')
          else
            LResult.AddPair('message', '');
        finally
          System.TMonitor.Exit(GReadLock);
        end;
      end
    );
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

initialization
  GReadLock := TObject.Create;

finalization
  GReadLock.Free;

end.
