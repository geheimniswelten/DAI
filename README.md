# DAI – Delphi AI

DAI ist ein Design-Time-Package für Delphi 13 / RAD Studio 13 (`BDS 37.0`). Es stellt der lokal laufenden Codex-Instanz einen MCP-Server zur Verfügung und
vermittelt kontrollierte Zugriffe auf die Delphi OpenToolsAPI.

## Benennung

- Package und Projekt: `DAI`
- Anzeigename: `Delphi AI`
- Alle Pascal-Units und Unit-Dateien beginnen mit dem kleingeschriebenen Namespace-Präfix `h5u.`
- Unterfunktionen sind in Dateinamen und Unit-Namen mit Punkten getrennt, zum Beispiel `h5u.DAI.Permissions.Manager.pas`
- Pascal-Quellzeilen sind auf höchstens 180 Zeichen begrenzt
- Tabulatoren sind in Pascal-Sourcen nicht zulässig und werden durch zwei Leerzeichen ersetzt

## MCP-Server

Der Server lauscht ausschließlich auf `127.0.0.1`, standardmäßig unter:

```text
http://127.0.0.1:7331/mcp
```

Der Zugriff ist mit einem Bearer-Token geschützt. Aktivierung, Port, Token, Logging, zusätzliche Referenzverzeichnisse und Berechtigungen werden unter
`Tools → Options → Third Party → DAI` verwaltet.

DAI unterstützt den klassischen MCP-Initialisierungsablauf und die moderne `server/discover`-Methode. Bei Codex-Anfragen wird `_meta.threadId` ausgewertet.
Dadurch können Session-Freigaben nach Projekt und Codex-Chat getrennt werden. Fehlt die Chat-ID, verwendet DAI ersatzweise die MCP-Transport-Session.
Fehlen beide Identitäten, wird „Für diese Session“ aus Sicherheitsgründen wie eine einmalige Freigabe behandelt.

## Berechtigungen

Vor geschützten Operationen erscheint in der Delphi-IDE ein `TTaskDialog` mit fünf Command-Link-Schaltflächen:

1. **Nie erlauben** – dauerhaft für das aktuelle Projekt beziehungsweise global sperren
2. **Verweigern** – nur die aktuelle Anfrage ablehnen
3. **Nur diesmal** – nur die aktuelle Anfrage zulassen
4. **Für diese Session** – bis zum Schließen des Projekts oder der IDE für den erkannten KI-Chat zulassen
5. **Immer erlauben** – dauerhaft für das aktuelle Projekt beziehungsweise global zulassen

Die Verification-Checkbox übernimmt die Entscheidung für alle anderen Funktionsgruppen, deren aktuelle Erlaubnisstufe niedriger ist.

Die Funktionsgruppen werden getrennt behandelt:

- Lesezugriffe
- Bearbeiten innerhalb der IDE
- Dateien außerhalb der IDE bearbeiten
- Kompilieren
- Ausführen

Dauerhafte Projektentscheidungen werden neben der Projektdatei in `<Projektname>.dai.permissions.json` gespeichert. Auf der Optionsseite kann zwischen dem
globalen Standard und den Berechtigungen des aktuell geöffneten Projekts gewechselt werden. „Verweigern“, „Nur einmal“ und „Session“ sind
Laufzeitentscheidungen; „Nie“, „Nachfragen“ und „Immer“ werden persistent gespeichert.

## Projekt- und Chat-Sessions

Eine Session-Freigabe besitzt den Schlüssel:

```text
<Projektdatei> + <Codex threadId oder MCP-Session-ID> + <Funktionsgruppe>
```

Beim Schließen eines Projekts werden dessen Laufzeitfreigaben verworfen. Beim Schließen einer Projektgruppe oder der IDE werden alle Laufzeitfreigaben
verworfen. Ein anderer Codex-Chat erhält daher keine Freigabe aus einem vorherigen Chat, sofern Codex die `threadId` mitsendet.

## Datei- und Editorzugriffe

Für geöffnete Dateien ist immer der aktuelle `IOTASourceEditor` maßgeblich. Das gilt auch dann, wenn das MCP-Werkzeug die Datei über ihren
Festplattenpfad adressiert. Schreibvorgänge verwenden einen Undo-fähigen `IOTAEditWriter`; beim Speichern behandelt die IDE die Dateicodierung.

Geschlossene Dateien werden nur geschrieben, wenn sie innerhalb eines geöffneten Projektverzeichnisses liegen. Bei vorhandenen Dateien behält DAI
einheitliches CRLF beziehungsweise LF bei. Für neue Dateien bleibt ein bereits einheitliches CRLF oder LF aus dem übergebenen Inhalt erhalten. Gemischte
Zeilenenden sowie alleinstehendes CR werden auf das vorhandene einheitliche Format normalisiert; fehlt ein eindeutiges Format, wird CRLF verwendet. Es gibt
keine projektweite oder repositoryweite Umstellung zwischen CRLF und LF.

Für `.pas` gilt: Neue Dateien werden standardmäßig als UTF-8 mit BOM angelegt. Vorhandene Dateien behalten ANSI beziehungsweise ihre BOM-basierte
Codierung. Reicht die aktuelle ANSI-Codepage für den neuen Inhalt nicht aus, wird eine vorhandene ANSI-PAS-Datei auf UTF-8 mit BOM angehoben. Eine
PAS-Datei ohne BOM wird entsprechend dem Verhalten der Delphi-IDE als ANSI interpretiert, nicht als UTF-8 ohne BOM.

Bei Schreibzugriffen auf Pascal-Sourcen (`.pas`, `.dpr`, `.dpk`, `.inc`) ersetzt DAI echte Tabulatorzeichen durch jeweils zwei Leerzeichen. Diese Regel
wird nicht auf DFM-Dateien angewendet.

Diese PAS-Regel gilt ausdrücklich nicht für DFM-Dateien. DAI überschreibt DFM-Dateien niemals direkt auf dem Datenträger, sondern bearbeitet sie nur im
IDE-Textpuffer. Delphi entscheidet anschließend beim Speichern anhand der enthaltenen Property-Werte selbst, ob die DFM als ANSI oder UTF-8 gespeichert
wird. Ist kein DFM-Textpuffer verfügbar, wird der Schreibvorgang abgelehnt; bei Bedarf ist vorher `form_show_as_text` aufzurufen.

`file_read` liefert zusätzlich `encoding` und `line_ending`. `file_write` meldet außerdem die ursprüngliche und die nach dem Schreibvorgang verwendete
Codierung sowie die ursprüngliche und resultierende Art des Zeilenumbruchs.

Schreibgeschützt bleiben:

```text
%BDS%\source
%BDSCatalogRepository%
%BDSCatalogRepositoryAllUsers%
%PUBLIC%\Documents\Embarcadero\Studio\37.0\Samples
```

Zusätzliche Verzeichnisse aus den Optionen sind ebenfalls ausschließlich lesbar.

Der Vorschlag für das persönliche Projektverzeichnis wird anhand der Windows-UI-Sprache und vorhandener Verzeichnisse ermittelt:

```text
Englisch:   %USERPROFILE%\Documents\Embarcadero\Studio\37.0\Projects
Deutsch:    %USERPROFILE%\Documents\Embarcadero\Studio\37.0\Projekte
Italienisch:%USERPROFILE%\Documents\Embarcadero\Studio\37.0\Progetti
Japanisch:  %USERPROFILE%\Documents\Embarcadero\Studio\37.0\プロジェクト
```

## Projektoperationen

DAI kann Projekte erstellen, öffnen, speichern und aus einer Projektgruppe entfernen. Units und Form-Units können erstellt, geöffnet, aktiviert,
geschlossen und aus einem Projekt entfernt werden.

Vor einer Operation, die eine bestehende Projektbelegung beeinflussen könnte, zeigt DAI unabhängig von der allgemeinen Berechtigung eine zusätzliche
Sicherheitsabfrage. Bereits geöffnete Projekte oder Projektgruppen werden niemals stillschweigend geschlossen. Wird ein Wechsel von der IDE selbst
verlangt, bleibt auch deren eigener Bestätigungsdialog aktiv.

## Kompilieren und Ausführen

Verfügbare Werkzeuge:

- `project_compile`
- `project_group_compile`
- `project_run`
- `project_stop`
- `msbuild_execute`
- `dcc32_execute`

`msbuild_execute` startet ausschließlich eine bekannte oder explizit angegebene `MSBuild.exe`. Ein expliziter Pfad muss unter `%BDS%`, `%WINDIR%`,
`%ProgramFiles%` oder `%ProgramFiles(x86)%` liegen. `dcc32_execute` verwendet ausschließlich `%BDS%\bin\dcc32.exe`.

Beide Compiler werden direkt mit `CreateProcess` gestartet. Es gibt keine Shell-Interpretation der Argumente. Standardausgabe und Standardfehler werden
begrenzt erfasst und als MCP-Ergebnis zurückgegeben.

## MCP-Werkzeuge

### Lesen

- `ide_status`
- `open_files_list`
- `projects_list`
- `project_files_list`
- `project_directory_files_list`
- `directory_files_list`
- `reference_roots_list`
- `reference_files_list`
- `file_read`
- `reference_file_read`
- `codex_registration_status`

### Bearbeiten und IDE-Steuerung

- `file_write`
- `project_create`
- `project_open`
- `project_save`
- `project_remove`
- `unit_create`
- `form_unit_create`
- `file_open`
- `file_activate`
- `file_close`
- `project_file_remove`
- `form_show_as_text`
- `ui_message_box`
- `ui_input_box`
- `ui_balloon_hint`
- `codex_register`
- `codex_unregister`

### Build und Laufzeit

- `project_compile`
- `project_group_compile`
- `project_run`
- `project_stop`
- `msbuild_execute`
- `dcc32_execute`

## Codex-Registrierung

Die Optionsseite zeigt den Status folgender Dateien über `FileExists` und die DAI-Verwaltungsmarker an:

```text
%USERPROFILE%\.codex\config.toml
%USERPROFILE%\.agents\skills\delphi-ide\SKILL.md
```

„Registrieren“ ergänzt ausschließlich einen markierten DAI-Block und den verwalteten Skill. „Deregistrieren“ entfernt nur diese verwalteten Inhalte.
Ein bereits vorhandener, nicht markierter `[mcp_servers.dai]`-Abschnitt wird nicht überschrieben.

## Build

PowerShell:

```powershell
.\Build.ps1 -Configuration Release -Platform Win32
```

Mit explizitem BDS-Verzeichnis:

```powershell
.\Build.ps1 `
  -Configuration Release `
  -Platform Win32 `
  -BdsRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Erwartete Ausgaben:

```text
Build\Win32\Release\Bpl\DAI.bpl
```

Das mitgelieferte DPROJ ist entsprechend dem vom Benutzer korrigierten Projektstand zunächst für Win32 aktiviert. Für die 64-Bit-IDE kann Win64 im Projektmanager als Zielplattform ergänzt und anschließend mit `-Platform Win64` gebaut werden.

## Verbindungstest

```powershell
.\Test-MCP.ps1 -Port 7331 -Token '<Bearer-Token>'
```

Das Skript führt `initialize`, `notifications/initialized`, `tools/list` und `tools/call → ide_status` aus. Dabei können in der Delphi-IDE
Berechtigungsdialoge erscheinen.

## Statische Prüfung

```powershell
python .\Scripts\verify.py
```

Geprüft werden unter anderem Dateinamen, Unit-Namen, DPK-/DPROJ-Referenzen, XML, erforderliche MCP-Werkzeuge, bekannte ungültige Delphi-Typen, fehlende DAI-Typdeklarationen, Altbezeichnungen, Tabulatoren, gemischte Zeilenenden und die maximale Zeilenlänge von 180 Zeichen.

## Hinweis zur Binärprüfung

Das Archiv enthält Quellcode und Buildskripte, aber keine vorgefertigte BPL. Die abschließende Binärprüfung muss mit der konkret installierten Delphi-13-
Toolchain erfolgen.
