unit h5u.DAI.OTA.Files;

interface

uses
  System.JSON;

type
  TDAIFileService = class
  public
    class function ProjectFiles(const AProject: string): TJSONArray; static;
    class function OpenFiles: TJSONArray; static;
    class function ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean = True): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Helpers;

class function TDAIFileService.ProjectFiles(const AProject: string): TJSONArray;
var
  LFile: string;
  LProject: IOTAProject;
begin
  Inc(TDAIOTA.TestProjectReadCount);
  TDAIOTA.TestProjectReadKeys := TDAIOTA.TestProjectReadKeys + [AProject];
  if TDAIOTA.TestProjectReadDelayMs > 0 then
    Sleep(TDAIOTA.TestProjectReadDelayMs);
  LProject := TDAIOTA.ProjectByNameOrPath(AProject);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Unknown isolated test project.');
  Result := TJSONArray.Create;
  Result.Add(LProject.FileName);
  for LFile in LProject.Files do
    Result.Add(LFile);
end;

class function TDAIFileService.OpenFiles: TJSONArray;
var
  LFile: string;
begin
  Result := TJSONArray.Create;
  for LFile in TDAIOTA.TestBuffers.Keys do
    Result.Add(LFile);
end;

class function TDAIFileService.ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject;
var
  LBuffer: TTestBuffer;
begin
  Inc(TDAIOTA.TestReadCount);
  // Snapshot collection must retain full content; the real search engine applies the requested view.
  if AInterfacesOnly then
    raise EInvalidOperation.Create('Search snapshots require interfaces_only=false.');
  if not TDAIOTA.TestBuffers.TryGetValue(TDAIOTA.NormalizeFileName(AFileName), LBuffer) or LBuffer.ReadFails then
    raise EReadError.Create('Isolated editor buffer is unavailable.');
  Result := TJSONObject.Create;
  Result.AddPair('content', Copy(LBuffer.Content, 1, AMaximumCharacters));
  Result.AddPair('source', LBuffer.Source);
  Result.AddPair('truncated', TJSONBool.Create(LBuffer.Truncated or (Length(LBuffer.Content) > AMaximumCharacters)));
end;

end.
