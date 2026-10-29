unit h5u.DAI.OTA.Files;

interface

uses System.JSON;

type
  TDAIFileService = class
  public
    class var EditorOpen, LastSave: Boolean;
    class var WriteCalls, ReadCalls, PermissionCountAtWrite, PermissionCountAtRead: Integer;
    class var LastMaximumCharacters: Integer;
    class var LastInterfacesOnly: Boolean;
    class var LastFile, LastContent, LastHash: string;
    class procedure Reset; static;
    class function ReadFile(const AFile: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject; static;
    class function EditFile(const AFile, AHash: string; const AEdits: TJSONValue; const ASave: Boolean; out AUsedEditorBuffer: Boolean): TJSONObject; static;
    class function WriteFile(const AFile, AContent, AHash: string; const ASave: Boolean; out AUsedEditorBuffer: Boolean): TJSONObject; static;
  end;

implementation

uses System.SysUtils, h5u.DAI.Permissions.Manager, h5u.DAI.Types;

class procedure TDAIFileService.Reset;
begin
  WriteCalls := 0;
  ReadCalls := 0;
  PermissionCountAtRead := 0;
  LastMaximumCharacters := 0;
  LastInterfacesOnly := True;
  PermissionCountAtWrite := 0;
  LastFile := '';
  LastContent := '';
  LastHash := '';
  LastSave := False;
end;

class function TDAIFileService.ReadFile(const AFile: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject;
begin
  // Simulate the independent service ownership boundary, not permission routing.
  // The production file service has separate native read-only-policy regressions.
  if AFile.StartsWith('C:\Foreign\', True) and not EditorOpen then
    raise EDAIAccessDenied.Create('Closed foreign file is outside the permitted roots.');
  Inc(ReadCalls);
  PermissionCountAtRead := Length(TDAIPermissionManager.Instance.Requests);
  LastFile := AFile;
  LastMaximumCharacters := AMaximumCharacters;
  LastInterfacesOnly := AInterfacesOnly;
  Result := TJSONObject.Create;
  Result.AddPair('content', 'synthetic source');
  if EditorOpen then
    Result.AddPair('source', 'editor_buffer')
  else
    Result.AddPair('source', 'disk');
end;

class function TDAIFileService.EditFile(const AFile, AHash: string; const AEdits: TJSONValue; const ASave: Boolean; out AUsedEditorBuffer: Boolean): TJSONObject;
begin
  Result := WriteFile(AFile, AEdits.ToJSON, AHash, ASave, AUsedEditorBuffer);
end;

class function TDAIFileService.WriteFile(const AFile, AContent, AHash: string; const ASave: Boolean; out AUsedEditorBuffer: Boolean): TJSONObject;
begin
  Inc(WriteCalls);
  PermissionCountAtWrite := Length(TDAIPermissionManager.Instance.Requests);
  LastFile := AFile;
  LastContent := AContent;
  LastHash := AHash;
  LastSave := ASave;
  AUsedEditorBuffer := EditorOpen;
  Result := TJSONObject.Create;
  if EditorOpen then
    Result.AddPair('target', 'editor_buffer')
  else
    Result.AddPair('target', 'disk');
end;

end.
