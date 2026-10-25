unit h5u.DAI.Localization;

interface

type
  TDAILanguage = (dlEnglish, dlGerman, dlFrench, dlJapanese);

function DAIText(const AGerman, AEnglish, AFrench, AJapanese: string): string;
function DAILanguage: TDAILanguage;
function DAILanguageCode: string;
function DAILanguageFromResourceModule(const AHostExecutable, AResourceModule: string): TDAILanguage;
procedure DAISetLanguageForTests(const ALanguage: TDAILanguage);
procedure DAIResetLanguageForTests;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.PsAPI;

var
  FCachedLanguage: Integer = -1;
  FTestLanguage: Integer = -1;

function DAILanguageFromResourceModule(const AHostExecutable, AResourceModule: string): TDAILanguage;
var
  LHost, LResource, LExtension: string;
begin
  Result := dlEnglish;
  LHost := ExtractFileName(AHostExecutable);
  LResource := ExtractFileName(AResourceModule);
  if not SameText(LHost, 'bds.exe') then
    Exit;
  if not SameText(ChangeFileExt(LResource, ''), ChangeFileExt(LHost, '')) then
    Exit;
  LExtension := LowerCase(ExtractFileExt(LResource));
  if (LExtension = '.de') or (LExtension = '.deu') or (LExtension = '.de-de') then
    Result := dlGerman
  else if (LExtension = '.fr') or (LExtension = '.fra') or (LExtension = '.fr-fr') then
    Result := dlFrench
  else if (LExtension = '.ja') or (LExtension = '.jpn') or (LExtension = '.ja-jp') then
    Result := dlJapanese;
end;

function LoadedModuleFileName(const AModule: HMODULE): string;
var
  LBuffer: array[0..4095] of Char;
  LLength: DWORD;
begin
  Result := '';
  if AModule = 0 then
    Exit;
  LLength := GetModuleFileName(AModule, LBuffer, Length(LBuffer));
  if LLength = 0 then
    // RTL resource satellites are mapped as data files; the low two bits tag the mapping.
    LLength := GetMappedFileName(GetCurrentProcess, Pointer(NativeUInt(AModule) and not NativeUInt(3)), LBuffer, Length(LBuffer));
  if (LLength > 0) and (LLength < DWORD(Length(LBuffer))) then
    SetString(Result, LBuffer, LLength);
end;

function DetectIDELanguage: TDAILanguage;
var
  LHostInstance: HMODULE;
  LHostName: string;
begin
  Result := dlEnglish;
  LHostInstance := GetModuleHandle(nil);
  LHostName := LoadedModuleFileName(LHostInstance);
  if not SameText(ExtractFileName(LHostName), 'bds.exe') then
    Exit;
  // Let the RTL resolve its actual satellite, including a pending lazy load.
  // A missing or unloadable satellite resolves to the host's English resources.
  // Reading an unresolved ResInstance directly would cache a false English fallback.
  Result := DAILanguageFromResourceModule(LHostName, LoadedModuleFileName(System.FindResourceHInstance(LHostInstance)));
end;

function DAILanguage: TDAILanguage;
var
  LLanguage: Integer;
begin
  LLanguage := InterlockedCompareExchange(FTestLanguage, -1, -1);
  if LLanguage < 0 then
  begin
    LLanguage := InterlockedCompareExchange(FCachedLanguage, -1, -1);
    if LLanguage < 0 then
    begin
      LLanguage := Ord(DetectIDELanguage);
      InterlockedCompareExchange(FCachedLanguage, LLanguage, -1);
      LLanguage := InterlockedCompareExchange(FCachedLanguage, -1, -1);
    end;
  end;
  Result := TDAILanguage(LLanguage);
end;

function DAILanguageCode: string;
const
  LANGUAGE_CODES: array[TDAILanguage] of string = ('en', 'de', 'fr', 'ja');
begin
  Result := LANGUAGE_CODES[DAILanguage];
end;

function DAIText(const AGerman, AEnglish, AFrench, AJapanese: string): string;
begin
  case DAILanguage of
    dlGerman: Result := AGerman;
    dlFrench: Result := AFrench;
    dlJapanese: Result := AJapanese;
  else
    Result := AEnglish;
  end;
end;

procedure DAISetLanguageForTests(const ALanguage: TDAILanguage);
begin
  InterlockedExchange(FTestLanguage, Ord(ALanguage));
end;

procedure DAIResetLanguageForTests;
begin
  InterlockedExchange(FTestLanguage, -1);
end;

end.
