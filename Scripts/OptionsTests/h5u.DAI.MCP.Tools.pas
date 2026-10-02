unit h5u.DAI.MCP.Tools;

interface

uses
  System.JSON;

type
  TDAIMCPTools = class sealed
  public
    class var ListCount: Integer;
    class var CatalogVariant: Integer;
    class function ListTools: TJSONArray; static;
  end;

implementation

procedure AddFixtureTool(const ATools: TJSONArray; const AName, ADescription: string);
var
  LTool: TJSONObject;
begin
  LTool := TJSONObject.Create;
  LTool.AddPair('name', AName);
  LTool.AddPair('description', ADescription);
  // A synthetic schema value verifies that the catalog displays only name/description.
  LTool.AddPair('inputSchema', TJSONObject.Create.AddPair('private_fixture', 'DO_NOT_DISPLAY_SCHEMA'));
  ATools.AddElement(LTool);
end;

class function TDAIMCPTools.ListTools: TJSONArray;
begin
  Inc(ListCount);
  Result := TJSONArray.Create;
  if CatalogVariant = 2 then
    Exit;
  AddFixtureTool(Result, 'ide_status', 'Liest den aktuellen IDE-Status.');
  if CatalogVariant = 1 then
  begin
    AddFixtureTool(Result, 'dynamic_fixture_added_tool', 'Ein erst später vorhandenes Werkzeug.');
    Exit;
  end;
  AddFixtureTool(Result, 'source_search', 'Sucht hilfreiche Quellen.' + #13#10 + #13#10 + '  Nur Interfaces als Standard.');
  AddFixtureTool(Result, 'ui_active_dialog', 'Liest den aktiven Dialog, ohne Eingabetexte auszulesen.');
end;

end.
