program TestDesigner;
{$APPTYPE CONSOLE}

// Test.Designer.ps1 copies the exact private production methods into the generated include.
// These doubles implement the original ToolsAPI interfaces; no IDE instance is accessed.

uses System.Classes, System.JSON, System.SysUtils, System.TypInfo,
  System.Math, ToolsAPI;
{$I DAI.Designer.Constants.inc}
type TFakeComponent = class(TInterfacedObject, IOTAComponent)
public
  Kind: TTypeKind;
  Text: string;
  ReadSuccess: Boolean;
  ReadRaises: Boolean;
  function GetComponentType: string;
  function GetComponentHandle: TOTAHandle;
  function GetParent: IOTAComponent;
  function IsTControl: Boolean;
  function GetPropCount: Integer;
  function GetPropName(Index: Integer): string;
  function GetPropType(Index: Integer): TTypeKind;
  function GetPropTypeByName(const Name: string): TTypeKind;
  function GetPropValue(Index: Integer; var Value): Boolean;
  function GetPropValueByName(const Name: string; var Value): Boolean;
  function SetProp(Index: Integer; const Value): Boolean;
  function SetPropByName(const Name: string; const Value): Boolean;
  function GetChildren(Param: Pointer; Proc: TOTAGetChildCallback): Boolean;
  function GetControlCount: Integer;
  function GetControl(Index: Integer): IOTAComponent;
  function GetComponentCount: Integer;
  function GetComponent(Index: Integer): IOTAComponent;
  function Select(AddToSelection: Boolean): Boolean;
  function Focus(AddToSelection: Boolean): Boolean;
  function Delete: Boolean;
end;
var GChecks: Integer;
procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then raise Exception.Create('FAIL: ' + AName);
  Inc(GChecks);
end;
function TFakeComponent.GetComponentType: string; begin Result := 'TFakeComponent'; end;
function TFakeComponent.GetComponentHandle: TOTAHandle; begin Result := Self; end;
function TFakeComponent.GetParent: IOTAComponent; begin Result := nil; end;
function TFakeComponent.IsTControl: Boolean; begin Result := False; end;
function TFakeComponent.GetPropCount: Integer; begin Result := 1; end;
function TFakeComponent.GetPropName(Index: Integer): string; begin Result := 'Value'; end;
function TFakeComponent.GetPropType(Index: Integer): TTypeKind; begin Result := Kind; end;
function TFakeComponent.GetPropTypeByName(const Name: string): TTypeKind;
begin if Name = 'Name' then Result := tkUString else Result := Kind; end;
function TFakeComponent.GetPropValue(Index: Integer; var Value): Boolean;
begin Result := GetPropValueByName('Value', Value); end;
function TFakeComponent.GetPropValueByName(const Name: string; var Value): Boolean;
begin
  if Name = 'Name' then
  begin
    PUnicodeString(@Value)^ := 'Fixture';
    Exit(True);
  end;
  if ReadRaises then raise Exception.Create('fixture getter failed');
  case Kind of
    tkString: PShortString(@Value)^ := ShortString(Text);
    tkLString: PAnsiString(@Value)^ := AnsiString(Text);
    tkWString: PWideString(@Value)^ := WideString(Text);
    tkUString: PUnicodeString(@Value)^ := Text;
  end;
  Result := ReadSuccess;
end;
function TFakeComponent.SetProp(Index: Integer; const Value): Boolean; begin Result := False; end;
function TFakeComponent.SetPropByName(const Name: string; const Value): Boolean; begin Result := False; end;
function TFakeComponent.GetChildren(Param: Pointer; Proc: TOTAGetChildCallback): Boolean; begin Result := True; end;
function TFakeComponent.GetControlCount: Integer; begin Result := 0; end;
function TFakeComponent.GetControl(Index: Integer): IOTAComponent; begin Result := nil; end;
function TFakeComponent.GetComponentCount: Integer; begin Result := 0; end;
function TFakeComponent.GetComponent(Index: Integer): IOTAComponent; begin Result := nil; end;
function TFakeComponent.Select(AddToSelection: Boolean): Boolean; begin Result := False; end;
function TFakeComponent.Focus(AddToSelection: Boolean): Boolean; begin Result := False; end;
function TFakeComponent.Delete: Boolean; begin Result := False; end;

{$I DAI.Designer.Functions.inc}

procedure RunCase(AKind: TTypeKind; const AText: string; AReadable, ARaises: Boolean);
var LFake: TFakeComponent; LComponent: IOTAComponent; LJson, LProperty: TJSONObject;
begin
  LFake := TFakeComponent.Create;
  LFake.Kind := AKind;
  LFake.Text := AText;
  LFake.ReadSuccess := AReadable;
  LFake.ReadRaises := ARaises;
  LComponent := LFake;
  LJson := ComponentJson(LComponent);
  try
    Check(LJson.GetValue<string>('name') = 'Fixture', 'component metadata remains readable');
    LProperty := TJSONObject(LJson.GetValue<TJSONArray>('properties').Items[0]);
    Check(LProperty.GetValue<Boolean>('value_available') = (AReadable and not ARaises),
      'availability follows actual OTA Boolean for ' + GetEnumName(TypeInfo(TTypeKind), Ord(AKind)));
    if AReadable and not ARaises then
      Check(LProperty.GetValue<string>('value') = AText, 'successful value preserved, including genuine empty strings')
    else
      Check(LProperty.GetValue('value') = nil, 'failed getter never supplies a fake empty or written string');
    if ARaises then
      Check(LProperty.GetValue<string>('read_error') = 'fixture getter failed', 'getter exception remains visible');
  finally
    LJson.Free;
  end;
end;
var LKind: TTypeKind; LComponent: IOTAComponent; LFake: TFakeComponent; LValue: TJSONValue;
begin
  try
    for LKind in [tkString, tkLString, tkWString, tkUString] do
    begin
      RunCase(LKind, 'readable', True, False);
      RunCase(LKind, '', True, False);
      RunCase(LKind, 'untrusted data despite False', False, False);
      RunCase(LKind, '', False, False);
      RunCase(LKind, 'unused', False, True);
    end;
    Check(ComponentString(nil, 'Value') = '', 'nil component metadata remains empty');
    for LKind in [tkLString, tkWString, tkUString] do
    begin
      LFake := TFakeComponent.Create;
      LFake.Kind := LKind;
      LFake.Text := StringOfChar('x', CMaximumPropertyCharacters + 104);
      LFake.ReadSuccess := True;
      LComponent := LFake;
      LValue := ScalarProperty(LComponent, 'Value', LKind);
      try
        Check((LValue is TJSONString) and (Length(TJSONString(LValue).Value) = CMaximumPropertyCharacters), 'successful long value retains truncation bound');
      finally LValue.Free; end;
    end;
    Writeln('PASS: ', GChecks, ' native designer scalar readability checks');
  except
    on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
