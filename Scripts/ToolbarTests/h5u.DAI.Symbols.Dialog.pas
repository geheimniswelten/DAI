unit h5u.DAI.Symbols.Dialog;

interface

type
  TDAISymbolIndexDialog = class sealed
  public
    class var ShowCount: Integer;
    class var LastScope: string;
    class procedure Show(const AScope: string = ''); static;
    class procedure Shutdown; static;
  end;

implementation

class procedure TDAISymbolIndexDialog.Show(const AScope: string);
begin
  Inc(ShowCount);
  LastScope := AScope;
end;

class procedure TDAISymbolIndexDialog.Shutdown;
begin
end;

end.
