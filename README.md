# DAI – Delphi AI

DAI ist ein Design-Time-Package für Delphi 13 / RAD Studio 13 (`BDS 37.0`). Es stellt lokal laufenden KI-Clients einen MCP-Server zur Verfügung und
vermittelt kontrollierte Zugriffe auf die Delphi OpenToolsAPI.

## Benennung

- Package und Projekt: `DAI`
- Anzeigename: `Delphi AI`
- Alle Pascal-Units und Unit-Dateien beginnen mit dem kleingeschriebenen Namespace-Präfix `h5u.`
- Unterfunktionen sind in Dateinamen und Unit-Namen mit Punkten getrennt, zum Beispiel `h5u.DAI.Permissions.Manager.pas`
- Pascal-Quellzeilen sind auf höchstens 180 Zeichen begrenzt
- Tabulatoren sind in Pascal-Sourcen nicht zulässig und werden durch zwei Leerzeichen ersetzt
- Zugriffe auf die RTL-Sperrklasse werden immer als `System.TMonitor` qualifiziert, damit keine Kollision mit `Vcl.Forms.TMonitor` entsteht

## MCP-Server

Der Server lauscht ausschließlich auf `127.0.0.1`, standardmäßig unter:

```text
http://127.0.0.1:7331/mcp
```

Der Zugriff ist mit einem Bearer-Token geschützt. Aktivierung, Port, Token, Logging, zusätzliche Referenzverzeichnisse und Berechtigungen werden unter
`Tools → Options → Third Party → DAI` verwaltet. Der Options-Frame zeigt neben dem frei änderbaren Port den Standardwert `7331`.

DAI registriert `Bearer` über Indys `OnParseAuthentication`. Dadurch erreicht der Authorization-Header den MCP-Handler, der den Token prüft und bei einem falschen Wert kontrolliert HTTP 401 zurückgibt.

Ein Bearer-Token muss keine GUID sein. DAI erzeugt standardmäßig eine kleingeschriebene GUID ohne geschweifte Klammern, weil dieses Format kompakt,
zufällig sowie problemlos in HTTP-Headern und der verwalteten Codex-TOML-Konfiguration verwendbar ist. Über `Token erzeugen` kann ein neuer Wert erstellt
werden. Bei einer vorhandenen Codex-Registrierung ist danach `Registrieren` aufzurufen, damit der neue Token dort ebenfalls gespeichert wird.

Kann der konfigurierte Port nicht gebunden werden, bleibt das Design-Time-Package geladen. DAI wechselt den Port nicht automatisch, weil Codex sonst
unbemerkt mit einer anderen IDE-Instanz verbunden werden könnte. Über die Windows-TCP-Tabelle werden PID und Prozessname des vorhandenen Listeners ermittelt
und im IDE-Meldungsfenster sowie auf der DAI-Optionsseite angezeigt. Gehört der Listener zur aktuellen `bds.exe`, kann die TCP-Tabelle nicht zusätzlich
bestimmen, welches BPL oder IDE-Plugin innerhalb dieses Prozesses den Socket geöffnet hat. Nach Auswahl eines freien Ports kann der Server durch Übernehmen
der Optionen erneut gestartet werden.

DAI unterstützt den klassischen MCP-Initialisierungsablauf und die moderne `server/discover`-Methode. Bei Codex-Anfragen wird `_meta.threadId` ausgewertet.
Dadurch können Session-Freigaben nach Projekt und Codex-Chat getrennt werden. Fehlt die Chat-ID, verwendet DAI ersatzweise die MCP-Transport-Session.
Fehlen beide Identitäten, wird „Für diese Session“ aus Sicherheitsgründen wie eine einmalige Freigabe behandelt.

Klassische Transport-Sitzungen laufen nach 30 Minuten ohne Anfrage ab. Laufende Anfragen zählen als aktiv; das Zeitlimit beginnt erneut nach ihrer Antwort.
DAI entfernt abgelaufene Sitzungen beim nächsten Sessionzugriff oder Initialisieren gezielt. Bei 1.024 aktiven Sitzungen erhalten neue Initialisierungen
HTTP 503 mit `Retry-After: 60`; bestehende Sitzungen bleiben gültig. Authentifiziertes `DELETE /mcp` mit `Mcp-Session-Id` beendet eine klassische Sitzung
mit HTTP 204. Abgelaufene oder beendete IDs erhalten HTTP 404; der Client muss neu initialisieren. Moderne Anfragen bleiben ohne Transport-Sitzung.
Die native stdio-Brücke versucht beim Schließen ihrer Eingabe, die klassische HTTP-Sitzung zu beenden.

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
Bei einer expliziten Projekt- oder Dateiangabe wird die Berechtigung dem zugehörigen geöffneten Projekt zugeordnet. Ein Gruppen-Build prüft jedes Projekt vor dem Start.

## Datei- und Editorzugriffe

Für geöffnete Dateien ist immer der aktuelle `IOTASourceEditor` maßgeblich. Das gilt auch dann, wenn das MCP-Werkzeug die Datei über ihren
Festplattenpfad adressiert. Schreibvorgänge verwenden einen Undo-fähigen `IOTAEditWriter`; beim Speichern behandelt die IDE die Dateicodierung.
`save: false` setzt einen vorhandenen Editorpuffer voraus. Für geschlossene Dateien ist `save: true` ausdrücklich erforderlich.

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

## Code Insight und Delphi-LSP

DAI greift nicht als zweiter JSON-RPC-Client auf die privaten Standard-I/O-Pipes der von Delphi gestarteten `DelphiLSP.exe` zu. Stattdessen verwendet es den
bereits von der IDE verwalteten Provider über `IOTACodeInsightServices` und `IOTAAsyncCodeInsightManager`. Dadurch gelten dieselbe Projektkonfiguration,
dieselben Suchpfade und der von Delphi synchronisierte aktuelle Editorstand.

Die Integration ist ausschließlich lesend:

- `code_insight_status` listet Provider, Bereitschaft und unterstützte Operationen auf.
- `code_definition` ermittelt die Definition eines Symbols. `line` ist einsbasiert, `character` ist der nullbasierte Zeichenindex vor Tabulator-Expansion.
- `code_hover` liefert das IDE-Help-Insight. `line` und `column` sind einsbasierte Editorpositionen; die Datei muss sichtbar in einem Code-Editor geöffnet sein.
- `file_diagnostics` liest Fehler, Warnungen und Hinweise über `IOTAModuleErrors`; die Datei muss von der IDE geladen sein.
- `project_context` liefert aktive Konfiguration, Plattform, Framework, Ziel, Projektdateien und ausgewählte ausgewertete DCC-Optionen.

Code-Insight-Anfragen werden serialisiert, mit einem Timeout versehen und bei Zeitüberschreitung über `AsyncOperationCanceled` abgebrochen. Ein für Help
Insight gesetzter `SetQueryContext` wird anschließend stets mit `nil, nil` zurückgesetzt.

Die öffentliche OpenToolsAPI stellt keinen allgemeinen Zugriff auf alle LSP-Methoden bereit. Insbesondere „Find all references“, Workspace-/Document-Symbole,
Rename, Call Hierarchy, Type Hierarchy und Semantic Tokens sind in dieser Stufe nicht enthalten. Dafür wäre zusätzlich eine eigene, von DAI verwaltete
LSP-Instanz pro Projekt erforderlich.

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
- `code_insight_status`
- `code_definition`
- `code_hover`
- `file_diagnostics`
- `project_context`
- `codex_registration_status`
- `clients_registration_status`
- `form_designer_inspect`
- `debugger_status`
- `breakpoints_list`

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
- `form_show_designer`
- `breakpoint_set`
- `breakpoint_remove`
- `ui_message_box`
- `ui_input_box`
- `ui_balloon_hint`
- `codex_register`
- `codex_unregister`
- `clients_register`
- `clients_unregister`

### Build und Laufzeit

- `project_compile`
- `project_group_compile`
- `project_run`
- `project_stop`
- `msbuild_execute`
- `dcc32_execute`
- `debugger_control`

## KI-Client-Registrierung

Die Optionsseite bietet eine Clientauswahl und eine Ergebnisliste mit Status, Pfad, Hinweisen und Sicherungsdateien. Alle Registrierungsoperationen sind Delphi-Code.
`clients_registration_status`, `clients_register` und `clients_unregister` nehmen optional `client` entgegen. Ohne Angabe bzw. mit `all` werden alle bekannten Clients geprüft;
bei der Registrierung werden nur erkannte Clients eingerichtet. Mit einer konkreten Client-ID ist eine ausdrückliche Einrichtung auch ohne vorhandene Konfigurationsdatei möglich.

| Client-ID | Client | Standardkonfiguration / Anschluss |
| --- | --- | --- |
| `codex` | Codex App / CLI / IDE | `%USERPROFILE%\.codex\config.toml`; HTTP mit Bearer-Header |
| `claude-code` | Claude Code CLI / VS Code | `%USERPROFILE%\.claude.json`; `mcpServers.dai`, `type: http` |
| `claude-desktop` | Claude Desktop | `%APPDATA%\Claude\claude_desktop_config.json`; native `DAI.McpBridge.exe` über stdio |
| `gemini` | Gemini CLI / Code Assist | `%USERPROFILE%\.gemini\settings.json`; `mcpServers.dai`, `httpUrl` |
| `hermes` | Hermes Agent / Desktop | `%LOCALAPPDATA%\hermes\config.yaml`; `mcp_servers.dai`, HTTP |
| `lm-studio` | LM Studio | `%USERPROFILE%\.lmstudio\mcp.json`; `mcpServers.dai`, HTTP |
| `openclaw` | OpenClaw | `%USERPROFILE%\.openclaw\openclaw.json`; `mcp.servers.dai`, `streamable-http` |
| `eigent` | Eigent | Einrichtung über die MCP-Oberfläche; kein belegtes automatisch beschreibbares Dateischema |
| `gemini-desktop` | Gemini Desktop / Consumer | Kein belegter allgemeiner lokaler MCP-Konfigurationsweg; verständlicher Hinweis statt Konfigurationsdatei |

Eigent kann den lokalen DAI-HTTP-Endpunkt mit `Authorization: Bearer <Token>` verwenden, soweit die installierte Version HTTP unterstützt. Bei stdio-Einrichtung:
`DAI.McpBridge.exe --url http://127.0.0.1:7331/mcp` und Umgebungsvariable `DAI_MCP_TOKEN`. Den aktuellen Port und Token aus den DAI-Optionen übernehmen.

Pfadüberschreibungen werden berücksichtigt: `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `GEMINI_CLI_HOME`, `HERMES_HOME`, `OPENCLAW_CONFIG_PATH` und `OPENCLAW_STATE_DIR`.
`GEMINI_CLI_HOME` bezeichnet den Elternordner von `.gemini`. Mehrdeutige Hermes-/OpenClaw-Profile und schreibgeschützte OpenClaw-Konfigurationen werden mit Hinweis ausgelassen.

Vor vorhandenen Änderungen wird eine Sicherung angelegt. JSON-, JSON5- und unterstützte YAML-Konfigurationen werden gezielt ergänzt; andere Einstellungen bleiben erhalten.
Unmarkierte DAI-Einträge und nachträglich geänderte verwaltete Einträge gelten als Konflikt. Ein Eigent-Pfad wird nicht aus dem Firefox-Vorbild übernommen, ohne dessen Schema zu belegen.
Neue Dateien und Sicherungen mit Token erhalten private Windows-Dateirechte. Der Status enthält keine Tokenwerte.

Die native Delphi-Brücke muss **neben `DAI.bpl`** liegen. `Build.ps1` baut beide. Claude Desktop erhält den Token als Umgebungsvariable, nicht als Befehlszeilenargument.
Nach Änderungen von Port, Token oder Registrierung die betroffenen MCP-Verbindungen neu laden bzw. den KI-Client neu starten.

Dokumentation: [Codex](https://developers.openai.com/codex/mcp/), [Claude Code](https://code.claude.com/docs/en/mcp),
[Claude Desktop](https://modelcontextprotocol.io/docs/develop/connect-local-servers), [Gemini CLI](https://geminicli.com/docs/tools/mcp-server/),
[LM Studio](https://lmstudio.ai/docs/app/mcp), [Hermes](https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference),
[OpenClaw](https://docs.openclaw.ai/gateway/config-extensions), [Eigent](https://www.eigent.ai/blog/eigent-how-to-setting-up-your-first-custom-mcp-server).

### Codex und vorhandener Skill

Die Optionsseite zeigt den Status folgender Dateien über `FileExists` und die DAI-Verwaltungsmarker an:

```text
%USERPROFILE%\.codex\config.toml
%USERPROFILE%\.agents\skills\delphi-ide\SKILL.md
```

Ohne `CODEX_HOME` verwendet DAI ausdrücklich `%USERPROFILE%`. `TPath.GetHomePath` zeigt unter Windows auf `%APPDATA%` und ist für diese benutzerspezifischen Codex-Pfade ungeeignet.
Beim nächsten Registrieren entfernt DAI ausschließlich eigene markierte Altinhalte unter `%APPDATA%`.

Der persönliche Skill liegt unter `.agents\skills`; ein Verzeichnis `.skills` wird von DAI nicht verwendet. Der Skill enthält nur Arbeitsanweisungen. Port und Bearer-Token stehen ausschließlich im verwalteten Block der `.codex\config.toml`. Nach einer Änderung von Port oder Token ist erneut `Registrieren` auszuführen und Codex neu zu starten.

„Registrieren“ ergänzt ausschließlich einen markierten DAI-Block und den verwalteten Skill. „Deregistrieren“ entfernt nur diese verwalteten Inhalte.
Ein bereits vorhandener, nicht markierter `[mcp_servers.dai]`-Abschnitt wird nicht überschrieben.

Der erzeugte `SKILL.md` enthält gültige YAML-Metadaten (`name`, `description`), aktuelle Werkzeugnamen, Parameter, Hashkonfliktbehandlung und Zugriffsgrenzen.
Ein vorhandener fremder `delphi-ide`-Skill wird nicht überschrieben. Die automatische Skill-Erkennung ist hier für Codex eingerichtet; andere Clients benötigen ihre eigene Skill-Installation.

## Formdesigner und Debugger

`form_designer_inspect(file)` liest Komponenten, Auswahl und skalare veröffentlichte Eigenschaften aus einem geladenen Formularmodul.
`form_show_designer(file)` öffnet das Formular bei Bedarf und zeigt dessen Designer. Komplexe Objekte und Ereignisse werden nicht als frei beschreibbare Eigenschaften angeboten.
DFM-/FMX-Inhalte können bei geladenem Designer auch dessen ungespeicherten Zustand liefern (`source: designer_buffer`). Für Änderungen weiterhin den IDE-Textpuffer verwenden.

`debugger_status` liefert Prozess-/Threadzustände; `breakpoints_list` die Quellhaltepunkte.
`breakpoint_set` erwartet `file`, eine einsbasierte `line`, optional `enabled` (Standard `true`), `condition` und `pass_count` (Standard `0`).
`breakpoint_remove(file, line)` entfernt passende Quellhaltepunkte. Änderungen sind auf Workspace-Dateien beschränkt.
`debugger_control(action)` unterstützt `pause`, `continue`, `step_into`, `step_over` und `step_out` mit Prüfung des aktuellen Prozesszustands.
Starten/Beenden erfolgt über `project_run` und `project_stop`. Ein bereits laufender Debugger wird durch `project_run` nicht unbeabsichtigt neu gestartet.
Haltepunkte gehören zur IDE-Bearbeitung, Debugger-Steuerung zur Ausführungsberechtigung; Status und Auflistungen zur Leseberechtigung.

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
Build\Win32\Release\Bpl\DAI.McpBridge.exe
```

Das mitgelieferte DPROJ ist entsprechend dem vom Benutzer korrigierten Projektstand zunächst für Win32 aktiviert. Für die 64-Bit-IDE kann Win64 im Projektmanager als Zielplattform ergänzt und anschließend mit `-Platform Win64` gebaut werden.

## Verbindungstest

```powershell
.\Test-MCP.ps1 -Port 7331 -Token '<Bearer-Token>'
.\Test-MCP.ps1 -Mode Modern -Port 7331 -Token '<Bearer-Token>'
```

Im Standardmodus führt das Skript `initialize`, `notifications/initialized`, `tools/list` und `tools/call → ide_status` aus.
Mit `-Mode Modern` verwendet es `server/discover` und die erforderlichen MCP-Metadaten und HTTP-Header. In der Delphi-IDE können Berechtigungsdialoge erscheinen.

Die isolierten Tests verwenden eigene Fixtures und IDE-/Settings-Stubs:

```powershell
.\Scripts\Test-ClientRegistration.ps1 -Platform Win32
.\Scripts\Test-ClientRegistration.ps1 -Platform Win64
.\Scripts\Test.Protocol.ps1 -Platform Win32
.\Scripts\Test.Protocol.ps1 -Platform Win64
.\Scripts\Test.Sessions.ps1 -Platform Win32
.\Scripts\Test.Sessions.ps1 -Platform Win64
python .\Scripts\test_bridge.py
```

Dabei werden keine tatsächlichen Client-Konfigurationen verändert und keine Designer-/Debuggeraktionen in der laufenden IDE ausgelöst.

## Statische Prüfung

```powershell
python .\Scripts\verify.py
```

Geprüft werden unter anderem Dateinamen, Unit-Namen, DPK-/DPROJ-Referenzen, XML, erforderliche MCP-Werkzeuge, bekannte ungültige Delphi-Typen, fehlende DAI-Typdeklarationen, Altbezeichnungen, unqualifizierte `TMonitor`-Aufrufe, Tabulatoren, gemischte Zeilenenden und die maximale Zeilenlänge von 180 Zeichen.

## Hinweis zur Binärprüfung

Der überarbeitete Stand wurde mit der lokal installierten Delphi-13-Toolchain kompiliert. Die IDE-Integration von Designer, Debugger und Dialogen
muss zusätzlich im laufenden RAD Studio geprüft werden; Compiler- und isolierte Protokolltests ersetzen diesen Praxistest nicht.
