unit h5u.DAI.OTA.Packages;

interface

uses
  System.JSON;

type
  TDAIPackageTarget = record
    ProjectFile: string;
    FileName: string;
    Configuration: string;
    Platform: string;
  end;

  TDAIPackageService = class sealed
  public
    class function Prepare(const AProject, AFile: string): TDAIPackageTarget; static;
    class function Status(const ATarget: TDAIPackageTarget): TJSONObject; static;
    class function Install(const ATarget: TDAIPackageTarget): TJSONObject; static;
    class function Uninstall(const ATarget: TDAIPackageTarget): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  ToolsAPI,
  Winapi.Windows,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.PackageSummary;

const
  CMaximumPackages = 10000;
  CPackageHeaderSize = 8;
  CPackageModuleMask = $C0000000;
  CPackageModule = $40000000;
  CPackageRuntimeOnly = $00000004;
  CPackageDesignOnly = $00000002;

type
  TPackagePathMatch = (pmUnknown, pmDifferent, pmSame);

function IsAbsolutePath(const AFileName: string): Boolean;
begin
  Result := AFileName.StartsWith('\\');
  if Length(AFileName) >= 3 then
    Result := Result or ((AFileName[2] = ':') and (AFileName[3] = '\'));
end;

function NormalizePackageFile(const AFileName, AProjectDirectory: string; const AAllowRelative: Boolean): string;
var
  LValue: string;
begin
  LValue := Trim(AFileName);
  if (LValue = '') or (Pos(#0, AFileName) > 0) then
    raise EArgumentException.Create('Für die Packageoperation wird ein vollständiger BPL-Dateipfad benötigt.');
  if LValue.Contains('$(') or LValue.Contains('@(') or LValue.Contains('%') then
    raise EArgumentException.Create('Der BPL-Dateipfad enthält nicht ausgewertete Makros.');
  LValue := StringReplace(LValue, '/', '\', [rfReplaceAll]);
  if not IsAbsolutePath(LValue) then
  begin
    if not AAllowRelative or (Trim(AProjectDirectory) = '') or (Pos(':', LValue) <> 0) or LValue.StartsWith('\') then
      raise EArgumentException.Create('file muss einen vollständig qualifizierten BPL-Dateipfad enthalten.');
    LValue := TPath.Combine(AProjectDirectory, LValue);
  end;
  if not IsAbsolutePath(LValue) then
    raise EArgumentException.Create('Der BPL-Dateipfad konnte nicht vollständig ausgewertet werden.');
  Result := TDAIOTA.NormalizeFileName(LValue);
  if not SameText(TPath.GetExtension(Result), '.bpl') then
    raise EArgumentException.Create('Packageoperationen erwarten eine Datei mit der Endung .bpl.');
end;

function PrepareProjectOnMainThread(const AProject: IOTAProject): TDAIPackageTarget;
var
  LOptions: IOTAProjectOptions;
begin
  if not Assigned(AProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
  if not SameText(AProject.ApplicationType, sPackage) then
    raise EArgumentException.Create('Das ausgewählte Projekt ist kein Package-Projekt.');
  Result := Default(TDAIPackageTarget);
  Result.ProjectFile := TDAIOTA.NormalizeFileName(AProject.FileName);
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  LOptions := AProject.ProjectOptions;
  if not Assigned(LOptions) then
    raise EInvalidOperation.Create('Die Package-Projektoptionen sind nicht verfügbar.');
  Result.FileName := NormalizePackageFile(LOptions.TargetName, TPath.GetDirectoryName(Result.ProjectFile), True);
end;

procedure RecheckTargetOnMainThread(const ATarget: TDAIPackageTarget);
var
  LCurrent: TDAIPackageTarget;
  LProject: IOTAProject;
begin
  if NormalizePackageFile(ATarget.FileName, '', False) <> ATarget.FileName then
    raise EInvalidOperation.Create('Das vorbereitete Packageziel ist nicht normalisiert.');
  if ATarget.ProjectFile = '' then
    Exit;
  LProject := TDAIOTA.ProjectByNameOrPath(ATarget.ProjectFile);
  LCurrent := PrepareProjectOnMainThread(LProject);
  if not TDAIOTA.SameFile(LCurrent.ProjectFile, ATarget.ProjectFile) or
    not SameText(LCurrent.Configuration, ATarget.Configuration) or not SameText(LCurrent.Platform, ATarget.Platform) or
    not TDAIOTA.SameFile(LCurrent.FileName, ATarget.FileName) then
    raise EInvalidOperation.Create('Das Package-Projektziel wurde seit der Vorbereitung geändert. Bitte die Operation erneut anfordern.');
end;

function FileIdentity(const AFileName: string; out AInfo: TByHandleFileInformation): DWORD;
var
  LHandle: THandle;
begin
  LHandle := CreateFileW(PWideChar(AFileName), FILE_READ_ATTRIBUTES, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if LHandle = INVALID_HANDLE_VALUE then
    Exit(GetLastError);
  try
    if GetFileInformationByHandle(LHandle, AInfo) then
      Result := ERROR_SUCCESS
    else
      Result := GetLastError;
  finally
    CloseHandle(LHandle);
  end;
end;

function MatchPackageFile(const ALeft, ARight: string): TPackagePathMatch;
var
  LLeft, LRight: string;
  LLeftInfo, LRightInfo: TByHandleFileInformation;
  LLeftError, LRightError: DWORD;
begin
  Result := pmUnknown;
  if (Trim(ALeft) = '') or (Trim(ARight) = '') or (Pos(#0, ALeft) > 0) or (Pos(#0, ARight) > 0) then
    Exit;
  try
    LLeft := TDAIOTA.NormalizeFileName(ALeft);
    LRight := TDAIOTA.NormalizeFileName(ARight);
  except
    Exit;
  end;
  if SameText(LLeft, LRight) then
    Exit(pmSame);
  LLeftError := FileIdentity(LLeft, LLeftInfo);
  LRightError := FileIdentity(LRight, LRightInfo);
  if (LLeftError = ERROR_FILE_NOT_FOUND) or (LLeftError = ERROR_PATH_NOT_FOUND) or
    (LRightError = ERROR_FILE_NOT_FOUND) or (LRightError = ERROR_PATH_NOT_FOUND) then
    Exit(pmDifferent);
  if (LLeftError <> ERROR_SUCCESS) or (LRightError <> ERROR_SUCCESS) then
    Exit;
  if (LLeftInfo.nFileIndexHigh = 0) and (LLeftInfo.nFileIndexLow = 0) then
    Exit;
  if (LRightInfo.nFileIndexHigh = 0) and (LRightInfo.nFileIndexLow = 0) then
    Exit;
  if (LLeftInfo.dwVolumeSerialNumber = LRightInfo.dwVolumeSerialNumber) and
    (LLeftInfo.nFileIndexHigh = LRightInfo.nFileIndexHigh) and (LLeftInfo.nFileIndexLow = LRightInfo.nFileIndexLow) then
    Result := pmSame
  else
    Result := pmDifferent;
end;

function OwnPackageFileName: string;
begin
  Result := GetModuleName(FindHInstance(@OwnPackageFileName));
end;

procedure ProtectOwnModule(const AFileName: string);
var
  LMatch: TPackagePathMatch;
  LOwnFile: string;
  LOwnInfo: TByHandleFileInformation;
begin
  LOwnFile := OwnPackageFileName;
  LMatch := MatchPackageFile(AFileName, LOwnFile);
  if LMatch = pmDifferent then
  begin
    // A renamed or removed module path cannot rule out a surviving alias to the running DAI binary.
    if FileIdentity(LOwnFile, LOwnInfo) <> ERROR_SUCCESS then
      LMatch := pmUnknown
    else if (LOwnInfo.nFileIndexHigh = 0) and (LOwnInfo.nFileIndexLow = 0) then
      LMatch := pmUnknown;
  end;
  if LMatch = pmSame then
    raise EInvalidOperation.Create('Das aktuell ausführende DAI-Package kann sich nicht selbst installieren oder deinstallieren.');
  if LMatch = pmUnknown then
    raise EInvalidOperation.Create('Das Packageziel konnte nicht sicher vom aktuell ausführenden DAI-Modul unterschieden werden.');
end;

function PackageServices: IOTAPackageServices210;
begin
  if not Supports(BorlandIDEServices, IOTAPackageServices210, Result) then
    raise EInvalidOperation.Create('Die Delphi-IDE stellt keine Dienste zum Installieren oder Deinstallieren von Packages bereit.');
end;

procedure ProtectIDEPackages(const AFileName: string; const AUninstall: Boolean; const AServices: IOTAPackageServices210);
var
  LCount, LIndex: Integer;
  LInfo: IOTAPackageInfo;
  LMatch: TPackagePathMatch;
  LRequiredBy: TStringList;
begin
  LCount := AServices.PackageCount;
  if (LCount < 0) or (LCount > CMaximumPackages) then
    raise EInvalidOperation.Create('Die IDE-Packageinformationen überschreiten das Prüflimit.');
  for LIndex := 0 to LCount - 1 do
  begin
    LInfo := AServices.Package[LIndex];
    if not Assigned(LInfo) then
      raise EInvalidOperation.Create('Die IDE-Packageinformationen sind nicht vollständig verfügbar.');
    LMatch := MatchPackageFile(AFileName, LInfo.FileName);
    if LMatch = pmUnknown then
      raise EInvalidOperation.Create('Die IDE-Packageinformationen erlauben keine sichere Zuordnung des Packageziels.');
    if LMatch <> pmSame then
      Continue;
    if LInfo.IDEPackage then
      raise EInvalidOperation.Create('Ein geschütztes IDE-Package kann nicht installiert oder deinstalliert werden.');
    if AUninstall then
    begin
      LRequiredBy := TStringList.Create;
      try
        LInfo.GetRequiredByList(LRequiredBy);
        if LRequiredBy.Count <> 0 then
          raise EInvalidOperation.Create('Das Package wird von geladenen Packages benötigt und kann nicht deinstalliert werden: ' +
            LRequiredBy.CommaText);
      finally
        LRequiredBy.Free;
      end;
    end;
  end;
end;

procedure ValidatePortableExecutable(const AStream: TStream);
var
  LDos: TImageDosHeader;
  LHeader: TImageFileHeader;
  LSignature: DWORD;
  LMagic: Word;
begin
  if AStream.Size < SizeOf(LDos) then
    raise EArgumentException.Create('Die BPL-Datei enthält keinen vollständigen PE-Dateikopf.');
  AStream.Position := 0;
  AStream.ReadBuffer(LDos, SizeOf(LDos));
  if (LDos.e_magic <> IMAGE_DOS_SIGNATURE) or (LDos._lfanew < SizeOf(LDos)) then
    raise EArgumentException.Create('Die BPL-Datei ist keine gültige Windows-PE-Datei.');
  if Int64(LDos._lfanew) > AStream.Size - SizeOf(LSignature) - SizeOf(LHeader) - SizeOf(LMagic) then
    raise EArgumentException.Create('Der PE-Dateikopf liegt außerhalb der BPL-Datei.');
  AStream.Position := LDos._lfanew;
  AStream.ReadBuffer(LSignature, SizeOf(LSignature));
  AStream.ReadBuffer(LHeader, SizeOf(LHeader));
  if LSignature <> IMAGE_NT_SIGNATURE then
    raise EArgumentException.Create('Die BPL-Datei enthält keine gültige PE-Signatur.');
  if (LHeader.Characteristics and IMAGE_FILE_DLL) = 0 then
    raise EArgumentException.Create('Das Packageziel ist keine DLL/BPL-Datei.');
  {$IFDEF WIN64}
  if LHeader.Machine <> IMAGE_FILE_MACHINE_AMD64 then
    raise EArgumentException.Create('Für diese 64-Bit-IDE wird ein Win64-Package benötigt.');
  {$ELSE}
  if LHeader.Machine <> IMAGE_FILE_MACHINE_I386 then
    raise EArgumentException.Create('Für diese 32-Bit-IDE wird ein Win32-Package benötigt.');
  {$ENDIF}
  if (LHeader.SizeOfOptionalHeader < SizeOf(LMagic)) or
    (Int64(LDos._lfanew) + SizeOf(LSignature) + SizeOf(LHeader) + LHeader.SizeOfOptionalHeader > AStream.Size) then
    raise EArgumentException.Create('Die BPL-Datei enthält keinen vollständigen optionalen PE-Dateikopf.');
  AStream.ReadBuffer(LMagic, SizeOf(LMagic));
  {$IFDEF WIN64}
  if LMagic <> IMAGE_NT_OPTIONAL_HDR64_MAGIC then
  {$ELSE}
  if LMagic <> IMAGE_NT_OPTIONAL_HDR32_MAGIC then
  {$ENDIF}
    raise EArgumentException.Create('Der optionale PE-Dateikopf passt nicht zur IDE-Architektur.');
end;

procedure ValidatePackageResource(const AFileName: string);
var
  LModule: HMODULE;
  LResource: HRSRC;
  LData: HGLOBAL;
  LSize, LFlags: DWORD;
  LBytes: Pointer;
begin
  // AS_DATAFILE reads resources without running package initialization or resolving imports.
  LModule := LoadLibraryExW(PWideChar(AFileName), 0, LOAD_LIBRARY_AS_DATAFILE);
  if LModule = 0 then
    raise EArgumentException.CreateFmt('Die BPL-Ressourcen konnten nicht gelesen werden (Windows-Fehler %d).', [GetLastError]);
  try
    LResource := FindResourceW(LModule, 'PACKAGEINFO', RT_RCDATA);
    if LResource = 0 then
      raise EArgumentException.Create('Die BPL-Datei enthält keine Delphi-PACKAGEINFO-Ressource.');
    LSize := SizeofResource(LModule, LResource);
    if LSize < CPackageHeaderSize then
      raise EArgumentException.Create('Die Delphi-PACKAGEINFO-Ressource ist unvollständig.');
    LData := LoadResource(LModule, LResource);
    if LData = 0 then
      raise EArgumentException.Create('Die Delphi-PACKAGEINFO-Ressource konnte nicht gelesen werden.');
    LBytes := LockResource(LData);
    if not Assigned(LBytes) then
      raise EArgumentException.Create('Die Delphi-PACKAGEINFO-Ressource konnte nicht geöffnet werden.');
    Move(LBytes^, LFlags, SizeOf(LFlags));
    if (LFlags and CPackageModuleMask) <> CPackageModule then
      raise EArgumentException.Create('Das Packageziel ist kein Delphi-Package-Modul.');
    if ((LFlags and CPackageRuntimeOnly) <> 0) and ((LFlags and CPackageDesignOnly) <> 0) then
      raise EArgumentException.Create('Die Delphi-PACKAGEINFO-Ressource enthält widersprüchliche Packageflags.');
    if (LFlags and CPackageRuntimeOnly) <> 0 then
      raise EArgumentException.Create('Ein Runtime-only-Package kann nicht in der IDE installiert werden.');
  finally
    FreeLibrary(LModule);
  end;
end;

function CloneStatusField(const AStatus: TJSONObject; const AName: string): TJSONValue;
var
  LValue: TJSONValue;
begin
  LValue := AStatus.GetValue(AName);
  if Assigned(LValue) then
    Result := LValue.Clone as TJSONValue
  else
    Result := TJSONNull.Create;
end;

function StatusOnMainThread(const ATarget: TDAIPackageTarget): TJSONObject;
var
  LSnapshot: TDAIPackageSummarySnapshot;
  LStatus: TJSONObject;
begin
  LSnapshot := TDAIPackageSummarySnapshot.Create;
  try
    LStatus := LSnapshot.ToJson(nil, ATarget.FileName, '');
    try
      Result := TJSONObject.Create;
      try
        Result.AddPair('file', ATarget.FileName);
        if ATarget.ProjectFile <> '' then
        begin
          Result.AddPair('project', ATarget.ProjectFile);
          Result.AddPair('configuration', ATarget.Configuration);
          Result.AddPair('platform', ATarget.Platform);
        end
        else
        begin
          Result.AddPair('project', TJSONNull.Create);
          Result.AddPair('configuration', TJSONNull.Create);
          Result.AddPair('platform', TJSONNull.Create);
        end;
        Result.AddPair('installed', CloneStatusField(LStatus, 'registered'));
        Result.AddPair('registered', CloneStatusField(LStatus, 'registered'));
        Result.AddPair('enabled', CloneStatusField(LStatus, 'enabled'));
        Result.AddPair('loaded', CloneStatusField(LStatus, 'loaded'));
      except
        Result.Free;
        raise;
      end;
    finally
      LStatus.Free;
    end;
  finally
    LSnapshot.Free;
  end;
end;

function ChangePackageOnMainThread(const ATarget: TDAIPackageTarget; const AInstall: Boolean): TJSONObject;
var
  LServices: IOTAPackageServices210;
  LFile: TFileStream;
  LSucceeded: Boolean;
  LOperation: string;
begin
  RecheckTargetOnMainThread(ATarget);
  ProtectOwnModule(ATarget.FileName);
  LServices := PackageServices;
  ProtectIDEPackages(ATarget.FileName, not AInstall, LServices);
  LFile := nil;
  try
    if AInstall then
    begin
      if not TFile.Exists(ATarget.FileName) then
        raise EArgumentException.Create('Die zu installierende BPL-Datei existiert nicht. Das Package zuerst kompilieren.');
      LFile := TFileStream.Create(ATarget.FileName, fmOpenRead or fmShareDenyWrite);
      ValidatePortableExecutable(LFile);
      ValidatePackageResource(ATarget.FileName);
      LOperation := 'install';
      LSucceeded := LServices.InstallPackage(ATarget.FileName);
    end
    else
    begin
      LOperation := 'uninstall';
      LSucceeded := LServices.UninstallPackage(ATarget.FileName);
    end;
    Result := StatusOnMainThread(ATarget);
    try
      Result.AddPair('operation', LOperation);
      Result.AddPair('succeeded', TJSONBool.Create(LSucceeded));
    except
      Result.Free;
      raise;
    end;
  finally
    LFile.Free;
  end;
end;

class function TDAIPackageService.Prepare(const AProject, AFile: string): TDAIPackageTarget;
var
  LResult: TDAIPackageTarget;
begin
  LResult := Default(TDAIPackageTarget);
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if (Pos(#0, AProject) > 0) or (Pos(#0, AFile) > 0) then
        raise EArgumentException.Create('project und file dürfen keine NUL-Zeichen enthalten.');
      if (Trim(AProject) <> '') and (Trim(AFile) <> '') then
        raise EArgumentException.Create('project und file können nicht gleichzeitig angegeben werden.');
      if Trim(AFile) <> '' then
        LResult.FileName := NormalizePackageFile(AFile, '', False)
      else
        LResult := PrepareProjectOnMainThread(TDAIOTA.ProjectByNameOrPath(AProject));
    end);
  Result := LResult;
end;

class function TDAIPackageService.Status(const ATarget: TDAIPackageTarget): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      RecheckTargetOnMainThread(ATarget);
      LResult := StatusOnMainThread(ATarget);
    end);
  Result := LResult;
end;

class function TDAIPackageService.Install(const ATarget: TDAIPackageTarget): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LResult := ChangePackageOnMainThread(ATarget, True);
    end);
  Result := LResult;
end;

class function TDAIPackageService.Uninstall(const ATarget: TDAIPackageTarget): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LResult := ChangePackageOnMainThread(ATarget, False);
    end);
  Result := LResult;
end;

end.
