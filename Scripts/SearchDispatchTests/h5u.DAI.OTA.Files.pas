unit h5u.DAI.OTA.Files;

interface

uses
  System.JSON;

type
  TDAIFileService = class sealed
  public
    class var Calls: Integer;
    class var LastDirectory, LastSearchPattern, LastFilenameRegex, LastContentQuery: string;
    class var LastRecursive, LastContentUseRegex, LastCaseSensitive, LastWholeWord: Boolean;
    class var LastMaximumCount: Integer;
    class procedure Reset; static;
    class function DirectoryFiles(const ADirectory, ASearchPattern: string; const ARecursive: Boolean; const AMaximumCount: Integer;
      const AFilenameRegex, AContentQuery: string; const AContentUseRegex, ACaseSensitive, AWholeWord: Boolean): TJSONArray; static;
  end;

implementation

class procedure TDAIFileService.Reset;
begin
  Calls := 0;
  LastDirectory := '';
  LastSearchPattern := '';
  LastFilenameRegex := '';
  LastContentQuery := '';
  LastRecursive := False;
  LastContentUseRegex := False;
  LastCaseSensitive := False;
  LastWholeWord := False;
  LastMaximumCount := 0;
end;

class function TDAIFileService.DirectoryFiles(const ADirectory, ASearchPattern: string; const ARecursive: Boolean; const AMaximumCount: Integer;
  const AFilenameRegex, AContentQuery: string; const AContentUseRegex, ACaseSensitive, AWholeWord: Boolean): TJSONArray;
begin
  Inc(Calls);
  LastDirectory := ADirectory;
  LastSearchPattern := ASearchPattern;
  LastRecursive := ARecursive;
  LastMaximumCount := AMaximumCount;
  LastFilenameRegex := AFilenameRegex;
  LastContentQuery := AContentQuery;
  LastContentUseRegex := AContentUseRegex;
  LastCaseSensitive := ACaseSensitive;
  LastWholeWord := AWholeWord;
  Result := TJSONArray.Create;
  Result.Add('final-directory-service-response');
end;

end.
