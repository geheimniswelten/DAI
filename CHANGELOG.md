# Änderungsprotokoll

## 1.1.2

- `EFOpenError` und `EFCreateError` aus dem DAI-Quellcode entfernt. `EFileStreamError.Create(PResStringRec, string)` verdeckt mangels `overload` insbesondere `Exception.Create(string)`.
- Eigene Ausnahmen `EDAIFileNotFound`, `EDAIFileAlreadyExists` und `EDAIExecutableNotFound` ergänzt; sie deklarieren keinen Konstruktor und erben daher `Exception.Create` sowie `Exception.CreateFmt` unverändert.
- Statische Prüfung erkennt künftig die nicht vorhandenen Typen `EFileNotFoundException`/`EFileExistsException` und verhindert im DAI-Code die ungeeigneten RTL-Typen `EFOpenError`/`EFCreateError`.

## 1.1.1

- vom Benutzer korrigierte `uses`-Listen und Win32-Projektdatei übernommen
- fehlende Unit `h5u.DAI.OTA.Creators.pas` ergänzt und in DPK/DPROJ eingebunden
- `TDAIModuleCreator`, `TDAIProjectCreator`, `TDAIProjectKind`, `pkConsole` und `pkVCL` vollständig implementiert
- nicht vorhandene `EFileExistsException` und `EFileNotFoundException` entfernt
- `EFCreateError` für Erstellkollisionen und `EFOpenError` für nicht auffindbare beziehungsweise nicht zu öffnende Dateien verwendet
- sprachabhängigen Projektverzeichnisvorschlag um die ermittelte Studio-Version ergänzt
- statischen Prüfer um ungültige Delphi-Typen, fehlende DAI-Typen und Creator-Referenzen erweitert
- Versionsangaben auf 1.1.1 aktualisiert

## 1.1.0

- Projekt und Package in `DAI` umbenannt
- Anzeigename `Delphi AI`
- alle Pascal-Dateien auf den Namespace-Präfix `h5u.` und punktgetrennte Unterfunktionen umgestellt
- fünfstufige, kategorisierte Berechtigungsabfrage mit `TTaskDialog`
- Verification-Checkbox zur Übernahme auf niedrigere Erlaubnisstufen
- Session-Trennung nach Projekt und Codex-`threadId`
- Projektberechtigungen über die DAI-Optionsseite und `.dai.permissions.json`
- zusätzliche Sicherheitsabfrage vor potenziell verdrängenden Projektoperationen
- sprachabhängiger Projektverzeichnisvorschlag für Englisch, Deutsch, Italienisch und Japanisch
- direkte MCP-Werkzeuge für `MSBuild.exe` und `%BDS%\bin\dcc32.exe`
- maximale Pascal-Zeilenlänge auf 180 Zeichen festgelegt
