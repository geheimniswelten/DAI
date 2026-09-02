# DAI 1.1.2 – Prüfbericht

Prüfdatum: 2. September 2026

## Ergebnis

Der Quellstand besteht die verfügbaren statischen Prüfungen.

```text
DAI-Prüfung erfolgreich: 24 Pascal-Units, 34 MCP-Werkzeuge.
```

## Korrektur der Dateiausnahmen

`EFOpenError` und `EFCreateError` stammen von `EFileStreamError`. Diese Klasse deklariert ausschließlich folgenden Konstruktor neu:

```pascal
constructor Create(ResStringRec: PResStringRec; const FileName: string);
```

Da bei dieser Deklaration `overload` fehlt, wird insbesondere `Exception.Create(const Msg: string)` für Aufrufe über `EFOpenError` und `EFCreateError` verdeckt. Der Aufruf `EFOpenError.Create('…')` führt deshalb zum Fehler E2010.

DAI verwendet nun eigene Ausnahmen ohne eigene Konstruktordeklaration:

```pascal
EDAIError = class(Exception);
EDAIFileNotFound = class(EDAIError);
EDAIFileAlreadyExists = class(EDAIError);
EDAIExecutableNotFound = class(EDAIFileNotFound);
```

Damit sind sowohl `Create(string)` als auch `CreateFmt(string, array of const)` unverändert von `Exception` verfügbar.

## Geänderte Stellen

- Auflösung von `MSBuild.exe` und `dcc32.exe`: `EDAIExecutableNotFound`
- fehlende Projekt-, Unit-, DFM- und Ausgabedateien: `EDAIFileNotFound`
- bereits vorhandene Projekt- oder Unit-Dateien: `EDAIFileAlreadyExists`
- Statischer Prüfer verbietet `EFileNotFoundException`, `EFileExistsException`, `EFOpenError` und `EFCreateError` im DAI-Quellcode.

## Weitere enthaltene Korrekturen

- `h5u.DAI.OTA.Creators.pas` ist vorhanden und in DPK/DPROJ eingetragen.
- `TDAIModuleCreator`, `TDAIProjectCreator`, `TDAIProjectKind`, `pkConsole` und `pkVCL` sind deklariert.
- Maximale Zeilenlänge: 180 Zeichen in Pascal-Dateien und DPK.
- Alle 34 vorgesehenen MCP-Werkzeuge sind statisch registriert.
- DPROJ-XML, DPK-/DPROJ-Unitreferenzen und SHA-256-Manifest werden geprüft.

## Einschränkung

In der Ausführungsumgebung ist keine Delphi-13-Toolchain mit `dcc32.exe`, `designide.dcp` und der Delphi-13-Version von `ToolsAPI.pas` installiert. Deshalb konnte kein echter Delphi-Binärbuild durchgeführt werden. Der endgültige Nachweis erfolgt durch den lokalen Build in Delphi 13.
