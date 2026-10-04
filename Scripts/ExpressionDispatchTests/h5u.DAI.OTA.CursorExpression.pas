unit h5u.DAI.OTA.CursorExpression;
interface
uses System.JSON;
type TDAICursorExpressionService = class sealed
  public
    class var MetadataCalls, ReadCalls, ReadPermissionCount: Integer;
    class var LastResponse: TJSONObject;
    class procedure Reset; static;
    class function CurrentFileName: string; static;
    class function Read(const AExpectedFile: string = ''): TJSONObject; static;
  end;
implementation
uses System.Classes, System.SysUtils, DAI.ExpressionDispatch.TestState, h5u.DAI.Permissions.Manager;
class procedure TDAICursorExpressionService.Reset;
begin MetadataCalls := 0; ReadCalls := 0; ReadPermissionCount := -1; LastResponse := nil; end;
class function TDAICursorExpressionService.CurrentFileName: string;
begin Inc(MetadataCalls); RecordEvent('cursor:metadata'); Result := CurrentFile; end;
class function TDAICursorExpressionService.Read(const AExpectedFile: string): TJSONObject;
begin
  LastExpectedFile := AExpectedFile;
  if AExpectedFile <> CurrentFile then raise EInvalidOperation.Create('Expected-file mismatch before source read.');
  Inc(ReadCalls); ReadPermissionCount := Length(TDAIPermissionManager.Instance.Requests); RecordEvent('cursor:read');
  Result := TJSONObject.Create;
  Result.AddPair('available', TJSONBool.Create(CursorAvailable));
  Result.AddPair('expression', CursorExpression); Result.AddPair('file', CurrentFile); Result.AddPair('line', TJSONNumber.Create(71));
  Result.AddPair('source', 'selection'); LastResponse := Result;
end;
end.
