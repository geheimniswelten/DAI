program Test.Localization;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Localization;

const
  TEXTS: array[TDAILanguage] of string = (
    '&Permission: %s (%d) - English',
    '&Berechtigung: %s (%d) - ÄÖÜ äöü ß',
    '&Autorisation : %s (%d) - Éèê àç œ',
    'アクセス許可(&P): %s (%d) - 日本語');
  CODES: array[TDAILanguage] of string = ('en', 'de', 'fr', 'ja');

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure CheckModule(const AHost, AModule: string; const AExpected: TDAILanguage);
begin
  Check(DAILanguageFromResourceModule(AHost, AModule) = AExpected, 'Unexpected IDE language: ' + AHost + ' / ' + AModule);
end;

procedure TestSelectedResources;
begin
  // Only the selected IDE resource module is an input; OS preferences cannot override it.
  CheckModule('C:\Delphi\bds.exe', '\Device\HarddiskVolume3\Delphi\bds.de', dlGerman);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.fr', dlFrench);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.ja', dlJapanese);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.exe', dlEnglish);
  CheckModule('C:\Delphi\bds.exe', '', dlEnglish);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.en', dlEnglish);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.es', dlEnglish);
  CheckModule('C:\Delphi\BDS.EXE', 'C:\Delphi\BDS.DE', dlGerman);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.DEU', dlGerman);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.FRA', dlFrench);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.JPN', dlJapanese);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.de-DE', dlGerman);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.fr-FR', dlFrench);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\bds.ja-JP', dlJapanese);
  CheckModule('C:\開発\bds.exe', 'C:\開発\bds.ja', dlJapanese);
  CheckModule('C:\Delphi\bds.exe', 'C:\Delphi\other.de', dlEnglish);
  CheckModule('C:\Delphi\test.exe', 'C:\Delphi\bds.de', dlEnglish);
  CheckModule('', 'C:\Delphi\bds.fr', dlEnglish);
end;

procedure TestTranslations;
var
  LLanguage: TDAILanguage;
  LText: string;
begin
  for LLanguage := Low(TDAILanguage) to High(TDAILanguage) do
  begin
    DAISetLanguageForTests(LLanguage);
    Check(DAILanguage = LLanguage, 'Explicit language override was ignored');
    Check(DAILanguageCode = CODES[LLanguage], 'Unexpected language code');
    LText := DAIText(TEXTS[dlGerman], TEXTS[dlEnglish], TEXTS[dlFrench], TEXTS[dlJapanese]);
    Check(LText = TEXTS[LLanguage], 'Unicode, accelerator or format placeholder changed');
    Check(Format(LText, ['DAI 日本語', 42]) = Format(TEXTS[LLanguage], ['DAI 日本語', 42]), 'Formatting changed');
    Check(DAIText('', '', '', '') = '', 'Empty translations changed');
  end;
end;

procedure TestHostFallbackAndReset;
var
  LDefault: TDAILanguage;
begin
  DAIResetLanguageForTests;
  LDefault := DAILanguage;
  Check(LDefault = dlEnglish, 'Non-IDE host must fall back to English, independent of Windows UI language');
  Check(DAILanguageCode = 'en', 'English host fallback code changed');
  DAISetLanguageForTests(dlGerman);
  Check(DAIText('Deutsch', 'English', 'Français', '日本語') = 'Deutsch', 'German fixture is not deterministic');
  DAIResetLanguageForTests;
  Check(DAILanguage = LDefault, 'Reset did not restore the cached host language');
  Check(DAIText('Deutsch', 'English', 'Français', '日本語') = 'English', 'Unknown host did not select English text');
end;

procedure TestLazyLoadedIDE(const ACode: string);
var
  LExpected: TDAILanguage;
  LHost: HMODULE;
  LModule: PLibModule;
begin
  if ACode = 'de' then
    LExpected := dlGerman
  else if ACode = 'fr' then
    LExpected := dlFrench
  else if ACode = 'ja' then
    LExpected := dlJapanese
  else
    LExpected := dlEnglish;
  // This affects only this disposable test process, never the registry or IDE.
  System.SetLocaleOverride(ACode);
  LHost := GetModuleHandle(nil);
  LModule := LibModuleList;
  while LModule <> nil do
  begin
    if (LModule.Instance = LHost) or (LModule.CodeInstance = LHost) or (LModule.DataInstance = LHost) then
      Break;
    LModule := LModule.Next;
  end;
  Check(LModule <> nil, 'Test host was not registered with the RTL');
  // RTL startup may have requested host resources before the program body.
  // Recreate the pending native state in this disposable process only.
  if (LModule.ResInstance <> 0) and (LModule.ResInstance <> LHost) then
    if not FreeLibrary(LModule.ResInstance) then
      RaiseLastOSError;
  LModule.ResInstance := 0;
  Check(LModule.ResInstance = 0, 'Regression requires an unresolved host resource module');
  Check(DAILanguage = LExpected, 'Lazy resource resolution selected the wrong IDE language');
  Check(LModule.ResInstance <> 0, 'IDE language detection left the host resource module unresolved');
  if LExpected = dlEnglish then
    Check(LModule.ResInstance = LHost, 'A missing satellite did not resolve to the host resources')
  else
    Check(LModule.ResInstance <> LHost, 'The selected satellite was not loaded');
  // A later preference change does not change the already loaded effective language.
  System.SetLocaleOverride('en');
  Check(DAILanguage = LExpected, 'A later preference change replaced the cached effective language');
  Check(DAILanguageCode = CODES[LExpected], 'Lazy-loaded language code changed');
end;

begin
  try
    if (ParamCount = 2) and (ParamStr(1) = 'lazy') then
      TestLazyLoadedIDE(ParamStr(2))
    else
    begin
      TestSelectedResources;
      TestTranslations;
      TestHostFallbackAndReset;
    end;
    Writeln(CheckCount, ' localization checks passed. Windows UI LANGID: ', GetUserDefaultUILanguage);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
