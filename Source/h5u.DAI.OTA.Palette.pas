unit h5u.DAI.OTA.Palette;

interface

uses
  System.JSON;

type
  TDAIPaletteService = class sealed
  public
    class function ListComponents(const AArguments: TJSONObject): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.StrUtils,
  System.SysUtils,
  PaletteAPI,
  ToolsAPI,
  h5u.DAI.OTA.Helpers;

const
  CMaximumPaletteResults = 4096;
  CMaximumPaletteItems = 32768;
  CMaximumPaletteDepth = 64;

type
  TDAIPaletteOptions = record
    Query: string;
    Category: string;
    IncludeUnavailable: Boolean;
    MaximumResults: Integer;
  end;

function ParsePaletteArguments(const AArguments: TJSONObject): TDAIPaletteOptions;
var
  LPair: TJSONPair;
  LValue: TJSONValue;
begin
  Result := Default(TDAIPaletteOptions);
  Result.MaximumResults := 500;
  if not Assigned(AArguments) then
    Exit;
  for LPair in AArguments do
    if (LPair.JsonString.Value <> 'query') and (LPair.JsonString.Value <> 'category') and
      (LPair.JsonString.Value <> 'include_unavailable') and (LPair.JsonString.Value <> 'maximum_results') then
      raise EArgumentException.CreateFmt('Unbekanntes Palettenargument: %s', [LPair.JsonString.Value]);
  LValue := AArguments.GetValue('query');
  if Assigned(LValue) then
  begin
    if not (LValue is TJSONString) then
      raise EArgumentException.Create('query muss eine Zeichenfolge sein.');
    Result.Query := LValue.Value;
  end;
  LValue := AArguments.GetValue('category');
  if Assigned(LValue) then
  begin
    if not (LValue is TJSONString) then
      raise EArgumentException.Create('category muss eine Zeichenfolge sein.');
    Result.Category := LValue.Value;
  end;
  LValue := AArguments.GetValue('include_unavailable');
  if Assigned(LValue) then
  begin
    if not (LValue is TJSONBool) then
      raise EArgumentException.Create('include_unavailable muss ein Boolean sein.');
    Result.IncludeUnavailable := TJSONBool(LValue).AsBoolean;
  end;
  LValue := AArguments.GetValue('maximum_results');
  if Assigned(LValue) then
  begin
    if not (LValue is TJSONNumber) or not TryStrToInt(LValue.Value, Result.MaximumResults) then
      raise EArgumentException.Create('maximum_results muss eine ganze Zahl sein.');
    if (Result.MaximumResults < 1) or (Result.MaximumResults > CMaximumPaletteResults) then
      raise EArgumentOutOfRangeException.Create('maximum_results muss zwischen 1 und 4096 liegen.');
  end;
end;

function PaletteComponentsJson(const ABaseGroup: IOTAPaletteGroup; const AOptions: TDAIPaletteOptions): TJSONObject;
var
  LComponents: TJSONArray;
  LSeenGroups: TDictionary<Pointer, Boolean>;
  LResult: TJSONObject;
  LItemsExamined: Integer;
  LComponentsExamined: Integer;
  LMatched: Integer;
  LRepeatedGroups: Integer;
  LTraversalTruncated: Boolean;

  procedure VisitGroup(const AGroup: IOTAPaletteGroup; const ACategory: string; const AEnabled, AVisible: Boolean; const ADepth: Integer);
  var
    LCategory: string;
    LComponent: IOTAComponentPaletteItem;
    LCount: Integer;
    LEnabled: Boolean;
    LIdentity: IInterface;
    LIndex: Integer;
    LItem: IOTABasePaletteItem;
    LJson: TJSONObject;
    LSubGroup: IOTAPaletteGroup;
    LVisible: Boolean;
    LClassName: string;
    LDisplayName: string;
  begin
    if not Assigned(AGroup) then
      Exit;
    if ADepth > CMaximumPaletteDepth then
    begin
      LTraversalTruncated := True;
      Exit;
    end;
    if not Supports(AGroup, IInterface, LIdentity) then
      raise EInvalidOperation.Create('Eine Palettenkategorie liefert keine Interface-Identität.');
    if LSeenGroups.ContainsKey(Pointer(LIdentity)) then
    begin
      Inc(LRepeatedGroups);
      Exit;
    end;
    LSeenGroups.Add(Pointer(LIdentity), True);
    LCount := AGroup.Count;
    for LIndex := 0 to LCount - 1 do
    begin
      if LItemsExamined >= CMaximumPaletteItems then
      begin
        LTraversalTruncated := True;
        Exit;
      end;
      Inc(LItemsExamined);
      LItem := AGroup.Items[LIndex];
      if not Assigned(LItem) then
        Continue;
      LEnabled := AEnabled and LItem.Enabled;
      LVisible := AVisible and LItem.Visible;
      if Supports(LItem, IOTAPaletteGroup, LSubGroup) then
      begin
        LCategory := ACategory;
        if LCategory <> '' then
          LCategory := LCategory + '/';
        LCategory := LCategory + LSubGroup.Name;
        VisitGroup(LSubGroup, LCategory, LEnabled, LVisible, ADepth + 1);
        Continue;
      end;
      // Wizards, snippets and templates without a component interface are not components.
      if not Supports(LItem, IOTAComponentPaletteItem, LComponent) then
        Continue;
      Inc(LComponentsExamined);
      if not AOptions.IncludeUnavailable and not (LEnabled and LVisible) then
        Continue;
      LClassName := LComponent.ClassName;
      LDisplayName := LComponent.Name;
      if (AOptions.Query <> '') and not ContainsText(LClassName, AOptions.Query) and
        not ContainsText(LDisplayName, AOptions.Query) then
        Continue;
      if (AOptions.Category <> '') and not ContainsText(ACategory, AOptions.Category) then
        Continue;
      Inc(LMatched);
      if LComponents.Count >= AOptions.MaximumResults then
        Continue;
      LJson := TJSONObject.Create;
      LComponents.AddElement(LJson);
      LJson.AddPair('class_name', LClassName);
      LJson.AddPair('display_name', LDisplayName);
      LJson.AddPair('unit_name', LComponent.UnitName);
      LJson.AddPair('package_name', LComponent.PackageName);
      LJson.AddPair('category', ACategory);
      LJson.AddPair('enabled', TJSONBool.Create(LEnabled));
      LJson.AddPair('visible', TJSONBool.Create(LVisible));
      LJson.AddPair('item_enabled', TJSONBool.Create(LItem.Enabled));
      LJson.AddPair('item_visible', TJSONBool.Create(LItem.Visible));
    end;
  end;

begin
  if not Assigned(ABaseGroup) then
    raise EInvalidOperation.Create('Die IDE stellt keine Komponentenpalette bereit.');
  LResult := TJSONObject.Create;
  LSeenGroups := nil;
  try
    try
      LSeenGroups := TDictionary<Pointer, Boolean>.Create;
      LComponents := TJSONArray.Create;
      LResult.AddPair('components', LComponents);
      LItemsExamined := 0;
      LComponentsExamined := 0;
      LMatched := 0;
      LRepeatedGroups := 0;
      LTraversalTruncated := False;
      // The abstract base group is not a visible category; availability begins with its children.
      VisitGroup(ABaseGroup, '', True, True, 0);
      LResult.AddPair('count', TJSONNumber.Create(LComponents.Count));
      LResult.AddPair('total_examined', TJSONNumber.Create(LComponentsExamined));
      LResult.AddPair('matched_count', TJSONNumber.Create(LMatched));
      LResult.AddPair('palette_items_examined', TJSONNumber.Create(LItemsExamined));
      LResult.AddPair('repeated_groups_skipped', TJSONNumber.Create(LRepeatedGroups));
      LResult.AddPair('truncated', TJSONBool.Create(LTraversalTruncated or (LMatched > LComponents.Count)));
      LResult.AddPair('traversal_truncated', TJSONBool.Create(LTraversalTruncated));
      LResult.AddPair('query', AOptions.Query);
      LResult.AddPair('category', AOptions.Category);
      LResult.AddPair('include_unavailable', TJSONBool.Create(AOptions.IncludeUnavailable));
      LResult.AddPair('maximum_results', TJSONNumber.Create(AOptions.MaximumResults));
      LResult.AddPair('context_note', 'Die Verfügbarkeit entspricht dem aktuellen IDE-/Designer-Kontext. ' +
        'enabled und visible berücksichtigen auch die übergeordneten Kategorien; ' +
        'item_enabled und item_visible sind die eigenen Palettenwerte. ' +
        'query und category sind wörtliche Teilstringsuchen ohne Groß-/Kleinschreibung. ' +
        'total_examined zählt untersuchte Komponenten, matched_count die Treffer vor dem Ergebnislimit.');
      Result := LResult;
    except
      LResult.Free;
      raise;
    end;
  finally
    LSeenGroups.Free;
  end;
end;

class function TDAIPaletteService.ListComponents(const AArguments: TJSONObject): TJSONObject;
var
  LOptions: TDAIPaletteOptions;
  LResult: TJSONObject;
begin
  LOptions := ParsePaletteArguments(AArguments);
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LServices: IOTAPaletteServices270;
    begin
      // Use the original service GUID, also supported by Delphi 11; newer additions are unnecessary.
      if not Supports(BorlandIDEServices, IOTAPaletteServices270, LServices) then
        raise EInvalidOperation.Create('Die IDE unterstützt keine öffentliche PaletteAPI.');
      LResult := PaletteComponentsJson(LServices.BaseGroup, LOptions);
    end);
  Result := LResult;
end;

end.
