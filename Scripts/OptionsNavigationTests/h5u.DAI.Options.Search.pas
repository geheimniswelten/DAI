unit h5u.DAI.Options.Search;
interface
type TDAIOptionsSearchService = class sealed
  public class function OptionLabels(const AName: string): TArray<string>; static;
end;
implementation
uses System.SysUtils;
class function TDAIOptionsSearchService.OptionLabels(const AName: string): TArray<string>;
begin
  if SameText(AName, 'DCC_UnitSearchPath') then Result := TArray<string>.Create('Search path', 'Suchpfad', AName)
  else Result := TArray<string>.Create(AName);
end;
end.
