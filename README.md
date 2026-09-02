# Codex MCP for Delphi IDE

`CodexMCPIDE` ist ein Design-Time-Package für **Delphi 13 / RAD Studio 13 (BDS 37.0)**. Es stellt die aktuell laufende Delphi-IDE über einen lokal gebundenen MCP-Server für Codex bereit.

## Funktionsumfang

- Streamable-HTTP-MCP-Endpunkt unter `http://127.0.0.1:<Port>/mcp`
- Bearer-Authentifizierung mit automatisch erzeugtem Token
- Ein-/Ausschalten, Port, Token, Logging und Zusatzpfade in den IDE-Optionen
- Eintrag im Delphi-Splashscreen über `SplashScreenServices.AddPluginBitmap`
- Registrierung in `%USERPROFILE%\.codex\config.toml`
- Registrierung eines Agent-Skills in `%USERPROFILE%\.agents\skills\delphi-ide\SKILL.md`
- Zugriff auf geöffnete Dateien, Projekte, Projektdateien und Projektverzeichnisse
- Editorpuffer-bewusstes Lesen und Schreiben: ungespeicherter IDE-Inhalt hat Vorrang vor der Festplatte
- Projekt-, Unit-, Form-, Build-, Run-, Stop- und Benutzerinteraktionsfunktionen
- optionales Zugriffslogging über `IOTAMessageServices.AddTitleMessage`

## Voraussetzungen

- Windows
- Delphi 13 / RAD Studio 13, Installationsversion `37.0`
- installierte Delphi-Design-Time-Pakete `designide`, `IndySystem`, `IndyCore` und `IndyProtocols`
- für die 64-Bit-IDE das als Win64 gebaute Package, für die 32-Bit-IDE das als Win32 gebaute Package

## Bauen

In einer PowerShell im Projektverzeichnis:

```powershell
.\Build.ps1 -Configuration Release -Platform Both
```

Optional kann die Delphi-Installation explizit angegeben werden:

```powershell
.\Build.ps1 -Configuration Release -Platform Both `
  -BdsRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Ausgaben:

```text
Build\Win32\Release\Bpl\CodexMCPIDE.bpl
Build\Win64\Release\Bpl\CodexMCPIDE.bpl
```

Alternativ `CodexMCPIDE.dproj` in Delphi 13 öffnen, die zur IDE passende Plattform auswählen, bauen und das Design-Time-Package installieren.

## Installation in der IDE

1. Das Package für die Architektur der laufenden IDE bauen.
2. `CodexMCPIDE.bpl` über die Package-Verwaltung der IDE hinzufügen oder das geöffnete Package-Projekt installieren.
3. Die Optionen unter `Tools > Options > Third Party > Codex MCP für Delphi IDE` öffnen.
4. Den Server aktivieren, Port und Token prüfen und die Optionen mit **OK** übernehmen.
5. **Codex registrieren** und **Skill registrieren** ausführen.

Beim Laden des Packages wird ein Splashscreen-Eintrag angezeigt. Der Server startet nur, wenn er in den Optionen aktiviert ist.

## Codex-Registrierung

Die Schaltfläche **Codex registrieren** schreibt einen gekennzeichneten, verwalteten Block nach:

```text
%USERPROFILE%\.codex\config.toml
```

Beispiel:

```toml
# BEGIN CodexMCPIDE (managed by the Delphi IDE package)
[mcp_servers.delphi_ide]
url = "http://127.0.0.1:7331/mcp"
http_headers = { Authorization = "Bearer <Token>" }
enabled = true
# END CodexMCPIDE
```

Ein bereits vorhandener, nicht vom Package verwalteter Abschnitt `[mcp_servers.delphi_ide]` wird nicht überschrieben. Die Deregistrierung entfernt ausschließlich den gekennzeichneten Block.

Der Skill wird unter folgendem Pfad angelegt:

```text
%USERPROFILE%\.agents\skills\delphi-ide\SKILL.md
```

Die Optionen zeigen für beide Ziele jeweils `FileExists` und den erkannten Registrierungsstatus an.

## Schreib- und Sicherheitsregeln

Der HTTP-Server bindet ausschließlich an `127.0.0.1`. Requests benötigen den konfigurierten Bearer-Token. Ein vorhandener `Origin`-Header wird nur für Loopback-Ursprünge akzeptiert.

Schreibzugriff ist nur für den aktuellen IDE-Arbeitsbereich möglich:

- geöffnete Editor-Dateien
- Dateien, die Mitglied eines geöffneten Projekts sind
- Dateien innerhalb eines geöffneten Projektverzeichnisses

Die folgenden Wurzeln sind stets schreibgeschützt und haben Vorrang vor einer möglichen Workspace-Zuordnung:

```text
%BDS%\source
%BDSCatalogRepository%
%BDSCatalogRepositoryAllUsers%
%PUBLIC%\Documents\Embarcadero\Studio\37.0\Samples
```

Zusätzliche schreibgeschützte Verzeichnisse können zeilenweise in den Optionen hinterlegt werden. Umgebungsvariablen wie `%USERPROFILE%` werden expandiert.

Weitere Schutzmaßnahmen:

- maximal 32 MiB pro MCP-Request
- maximal 16 MiB pro gelesener oder geschriebener Textdatei
- `expected_sha256` ermöglicht optimistische Konkurrenzkontrolle bei Schreibzugriffen
- ein geladener `IOTASourceEditor` ist die maßgebliche Quelle, auch wenn ein Festplattenpfad angefragt wurde
- Änderungen im Editor erfolgen über einen undo-fähigen `IOTAEditWriter`
- bei aktivem visuellen Form-Designer wird eine DFM nicht stillschweigend aus einer möglicherweise veralteten Festplattendatei gelesen oder überschrieben
- beim Speichern eines Projekts werden verknüpfte Module aus schreibgeschützten Referenzpfaden übersprungen

## MCP-Tools

### Status und Lesen

- `ide_status`
- `ide_list_open_files`
- `ide_list_projects`
- `ide_list_project_files`
- `ide_list_directory_files`
- `ide_read_file`
- `ide_list_readonly_roots`
- `ide_list_readonly_files`
- `ide_read_readonly_file`

### Dateien und Projekte

- `ide_write_file`
- `ide_create_project`
- `ide_open_project`
- `ide_save_project`
- `ide_remove_project`
- `ide_create_unit`
- `ide_create_form_unit`
- `ide_open_file`
- `ide_activate_file`
- `ide_close_file`
- `ide_remove_file_from_project`
- `ide_show_form_as_text`

### Build und Ausführung

- `ide_compile_project`
- `ide_compile_project_group`
- `ide_run_project`
- `ide_stop_project`

### Nutzerinteraktion

- `ide_message_box`
- `ide_input_box`
- `ide_balloon_hint`

Die Tool-Schemas und Annotationen werden dynamisch über `tools/list` geliefert.

## Verhalten wichtiger Operationen

### Lesen und Schreiben

`ide_read_file` liefert neben dem vollständigen Text unter anderem die Herkunft (`editor_buffer` oder `disk`), den Zugriffsmodus und einen SHA-256-Hash. `ide_write_file` ersetzt den gesamten Inhalt. Bei geöffneten Dateien wird der Editorpuffer geändert; mit `save=true` wird anschließend über die IDE gespeichert.

### DFM-Textmodus

`ide_show_form_as_text` aktiviert die DFM und führt den passenden IDE-Befehl beziehungsweise `Alt+F12` aus. Erst nach erfolgreicher Bereitstellung eines `IOTASourceEditor` gilt die Umschaltung als erfolgreich.

### Projektstart

Mit `debugger=true` wird das ausgewählte Projekt zum aktiven Projekt gemacht und über den IDE-Startbefehl ausgeführt. Mit `debugger=false` wird das lokale Windows-Ziel direkt über `CreateProcess` gestartet. Der direkte Start setzt daher eine vorhandene lokale ausführbare Zieldatei voraus.

## Verbindung testen

Bei laufender IDE und aktiviertem Server:

```powershell
.\Test-MCP.ps1 -Port 7331 -Token '<Bearer-Token>'
```

Ohne `-Token` verwendet das Skript zuerst `DELPHI_IDE_MCP_TOKEN` und versucht danach, den vom Package verwalteten Token aus `%USERPROFILE%\.codex\config.toml` zu lesen.

Das Skript führt `initialize`, `notifications/initialized`, `tools/list` und `ide_status` aus.

## Statische Prüfung

```powershell
python .\StaticCheck.py
```

Die Prüfung kontrolliert unter anderem Unit-/Dateinamen, DPK-/DPROJ-Referenzen, DPROJ-XML, MCP-Tool-Parität, Methodendeklarationen und einfache lexikalische Fehler.

## Technischer Hinweis

Dieses Archiv enthält den vollständigen Quellcode, jedoch keine vorcompilierte BPL. Die tatsächliche Binärkompatibilität muss mit der installierten Delphi-13-Toolchain und der konkret verwendeten 32- beziehungsweise 64-Bit-IDE geprüft werden.
