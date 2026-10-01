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

Der Zugriff ist mit einem Bearer-Token geschützt. Autostart, Port, Token, Logging, zusätzliche Referenzverzeichnisse und Berechtigungen werden unter
`Tools → Options → Third Party → DAI` verwaltet. Der Options-Frame zeigt neben dem frei änderbaren Port den Standardwert `7331`.

DAI registriert `Bearer` über Indys `OnParseAuthentication`. Dadurch erreicht der Authorization-Header den MCP-Handler, der den Token prüft und bei einem falschen Wert kontrolliert HTTP 401 zurückgibt.

Ein Bearer-Token muss keine GUID sein. DAI erzeugt standardmäßig eine kleingeschriebene GUID ohne geschweifte Klammern, weil dieses Format kompakt,
zufällig sowie problemlos in HTTP-Headern und der verwalteten Codex-TOML-Konfiguration verwendbar ist. Über `Token erzeugen` kann ein neuer Wert erstellt
werden. Bei einer vorhandenen Codex-Registrierung ist danach `Registrieren` aufzurufen, damit der neue Token dort ebenfalls gespeichert wird.

Kann der konfigurierte Port nicht gebunden werden, bleibt das Design-Time-Package geladen. DAI wechselt den Port nicht automatisch, weil Codex sonst
unbemerkt mit einer anderen IDE-Instanz verbunden werden könnte. Über die Windows-TCP-Tabelle werden PID und Prozessname des vorhandenen Listeners ermittelt
und im IDE-Meldungsfenster sowie auf der DAI-Optionsseite angezeigt. Gehört der Listener zur aktuellen `bds.exe`, kann die TCP-Tabelle nicht zusätzlich
bestimmen, welches BPL oder IDE-Plugin innerhalb dieses Prozesses den Socket geöffnet hat. Nach Auswahl eines freien Ports die Optionen übernehmen und
anschließend mit „Server starten“ erneut starten.

DAI unterstützt den klassischen MCP-Initialisierungsablauf und die moderne `server/discover`-Methode. Bei Codex-Anfragen wird `_meta.threadId` ausgewertet.
Dadurch können Session-Freigaben nach Projekt und Codex-Chat getrennt werden. Fehlt die Chat-ID, verwendet DAI ersatzweise die MCP-Transport-Session.
Fehlen beide Identitäten, wird „Für diese Session“ aus Sicherheitsgründen wie eine einmalige Freigabe behandelt.

Klassische Transport-Sitzungen laufen nach 30 Minuten ohne Anfrage ab. Laufende Anfragen zählen als aktiv; das Zeitlimit beginnt erneut nach ihrer Antwort.
DAI entfernt abgelaufene Sitzungen beim nächsten Sessionzugriff oder Initialisieren gezielt. Bei 1.024 aktiven Sitzungen erhalten neue Initialisierungen
HTTP 503 mit `Retry-After: 60`; bestehende Sitzungen bleiben gültig. Authentifiziertes `DELETE /mcp` mit `Mcp-Session-Id` beendet eine klassische Sitzung
mit HTTP 204. Abgelaufene oder beendete IDs erhalten HTTP 404; der Client muss neu initialisieren. Moderne Anfragen bleiben ohne Transport-Sitzung.
Die native stdio-Brücke versucht beim Schließen ihrer Eingabe, die klassische HTTP-Sitzung zu beenden.

## Eine aktive IDE und manueller Wechsel

Je Windowsbenutzer darf genau ein DAI-MCP-Server laufen. Die erste IDE, in der der Server erfolgreich startet, übernimmt. Andere IDE-Instanzen bleiben
geladen und melden, dass DAI bereits in einer anderen IDE aktiv ist. Dies gilt auch zwischen Win32 und Win64, bei anderen Ports und über Delphi-Versionen
hinweg, sofern die dort geladenen DAI-Packages diese Instanzsperre verwenden. Die Sperre enthält weder Port noch Architektur noch BDS-Versionsnummer.

Die Umsetzung liegt vollständig in Delphi: Ein globales benanntes Windows-Kernelobjekt mit Benutzer-SID wird während der Serverlaufzeit gehalten.
Ein normaler Stop gibt es nach vollständiger Listenerbereinigung frei; beim Prozessende schließt Windows die Handles. Wartende IDEs übernehmen nicht automatisch.

Zum Wechseln unter `Tools → Options → Third Party → DAI` in der aktiven IDE **Server stoppen**, danach in der gewünschten IDE **Server starten** wählen.
**Server starten** verwendet den aktuell eingetragenen Port und Bearer-Token, ohne den Optionsdialog zu schließen. Bei einem belegten Port kann direkt
im selben Dialog ein anderer Wert ausprobiert werden. Der Status zeigt den tatsächlich laufenden Port. Port und Token werden mit **Speichern** oder **Registrieren**
dauerhaft übernommen; Starten/Stoppen wirkt sofort und wird durch **Abbrechen** nicht rückgängig gemacht.
Die Schaltflächen verändern weder die gespeicherte Autostart-Einstellung noch Berechtigungen oder Clientregistrierungen.
**MCP-Server beim IDE-Start automatisch starten** gilt nur beim Start der IDE bzw. beim Laden des Packages. Das Übernehmen der Optionen bewahrt den manuellen
Laufzustand. Bei einem laufenden Server wird nur eine Portänderung mit einem Neustart des Listeners angewendet; dabei bleibt die Instanzsperre gehalten.

Win32 und Win64 verwenden bei gleichem BDS-Benutzerprofil weiterhin dieselben DAI-Einstellungen für Port und Token. Andere Delphi-Versionen bzw. eigene
IDE-Profile können andere Einstellungen besitzen. Nach einem Wechsel müssen die Clientregistrierungen zum Port, Token und Bridge-Pfad der neuen aktiven IDE passen.
`ide_status` zeigt dazu `active`, `ide_architecture`, `ide_process_id`, `ide_executable`, `package_file` und `package_registry_key`.

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

`file_read` und `reference_file_read` verwenden standardmäßig `interfaces_only: true`. Bei `.pas`-Units liefern sie den Text vor dem echten
`implementation`-Schlüsselwort. Für vollständige Änderungen immer mit `interfaces_only: false` und `maximum_characters: 0` lesen.
`implementation_omitted` zeigt den tatsächlichen Schnitt, `truncated` ausschließlich das Zeichenlimit; nur `content_complete: true` bestätigt
den vollständigen aktuellen Inhalt. `original_characters` und `sha256` bleiben auf diesen vollständigen Inhalt bezogen (`sha256_scope: complete_content`);
`view_characters` zählt die gewählte Ansicht vor dem Zeichenlimit. Der Hash einer Interfaceansicht macht ihren Text nicht zum vollständigen Schreibinhalt.

Vor jedem vollständigen `.pas`-Ersetzen prüft DAI lexikalisch Unit-Kopf, `interface`, `implementation` und abschließendes `end.`.
Unvollständige Inhalte, unterminierte Kommentare/Strings und versehentlich zurückgeschriebene Interfaceansichten werden vor jeder Mutation abgewiesen.
Leere Interfaces mit gültigem Unit-Abschluss bleiben erlaubt. Diese Strukturprüfung ersetzt keinen Delphi-Compiler und wertet keine Präprozessorsymbole aus.

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

## Quelldateien und Referenzen finden

`source_search` sucht wörtlichen Text, etwa `IOTADebuggerServices` oder `TButton`, mit Datei, Zeile, Spalte und Ausschnitt als Ergebnis.
`interfaces_only` ist standardmäßig `true`: Pascal-Units werden vor der Suche ab dem echten `implementation`-Schlüsselwort abgeschnitten.
Treffer und Ausschnitte können deshalb keinen nachfolgenden Implementierungscode enthalten; ursprüngliche Zeilen und Spalten bleiben erhalten.
Für Methodenrümpfe und Verwendungen dort `interfaces_only: false` setzen. Kommentare, Direktiven, Strings und escaped identifiers lösen keinen Schnitt aus.
Andere Dateitypen sowie Inhalte ohne erkannten Unit-/Interface-Kopf bleiben unverändert. Die Filterung erfolgt lexikalisch ohne Compiler-Präprozessor.
Die Antwort nennt den angeforderten Modus und `implementation_files_omitted`, die Zahl tatsächlich gekürzter Dateien.
`scope` wählt `project`, `group`, `references` oder `all` (Standard); `project`, `directory` und `file_patterns` grenzen die Suche ein.
Aktuelle Editor- und Designerpuffer haben Vorrang vor Dateien auf dem Datenträger. Die Standardmuster sind `*.pas`, `*.inc`, `*.dpr` und `*.dpk`.
Dateimuster verwenden ausschließlich `*` und `?` auf dem Dateinamen, höchstens 100 Muster mit jeweils 256 Zeichen; Zeichenklassen werden abgelehnt.
Mit `whole_word` lässt sich ein vollständiger Bezeichner suchen, mit `case_sensitive` die Groß-/Kleinschreibung beachten.

Standardmäßig endet die Suche nach 200 Treffern, 10.000 Dateien oder 5 Sekunden; die Obergrenzen liegen bei 1.000 Treffern, 100.000 Dateien und
30 Sekunden. Dateien über 2 MiB, binäre Inhalte und Reparse-Verknüpfungen werden übersprungen. `truncated`, `limit_reason`, `files_skipped`
und `snapshot_files_skipped` zeigen Grenzen und ausgelassene Dateien an. Eine begrenzte Suche bestätigt nicht die Abwesenheit eines Symbols.
Die Sammlung der IDE-Metadaten wird separat als `preparation_ms` ausgewiesen; deren bestehende OTA-Hauptthreadaufrufe können auf eine beschäftigte IDE warten.
Trefferausschnitte ersetzen nicht das Lesen der tatsächlichen Deklaration mit `file_read` beziehungsweise `reference_file_read`.

`reference_roots_list` zeigt die tatsächlichen Pfade und ihre Aliase. Sämtliche Referenzverzeichnisse sind ReadOnly, auch wenn sie gleichzeitig
in einer Projektgruppe oder im Editor geöffnet sind. `file_write` und die Projekt-/Unit-Ersteller lehnen dort Änderungen ab.
Speichern und Entfernen prüfen außerdem Projekt-, Gruppen- und Begleitdateien, einschließlich `.dproj` und `.dproj.local`.
IDE-Builds prüfen geänderte Editorpuffer, Projektabhängigkeiten und Ausgabeziele vor dem Start. Schreibpfade über Reparse-Verknüpfungen
werden auch dann abgelehnt, wenn erst eine neue Datei unterhalb einer Junction entstehen würde.

Diese Regeln kontrollieren die DAI-Datei-/Projektoperationen. Ausdrücklich freigegebene Compilerargumente und benutzerdefinierte Buildskripte
laufen ohne Dateisystem-Sandbox; ihre eigenen Dateioperationen kann DAI damit nicht vollständig beschränken.

| Alias | Referenzquelle |
| --- | --- |
| `%BDS%\source` | Delphi-/VCL-/FMX-Quellen der laufenden IDE |
| `%BDS%\source\ToolsAPI` | OpenToolsAPI |
| `%BDS%\Samples` | Öffentlicher Samplesordner der IDE-Version |
| `%BDSCatalogRepositoryAllUsers%` | GetIt für alle Benutzer |
| `%BDSCatalogRepository%` | GetIt im Benutzerprofil |

Die GetIt-Aliase verwenden die Umgebungsvariable, soweit vorhanden, sonst den zur IDE-Version passenden Ordner unter `%PUBLIC%` beziehungsweise
`%USERPROFILE%`. GetIt-Pakete werden dadurch weder eingebunden noch als DAI-Abhängigkeit benötigt.

`project_create` unterstützt `save:false`. Ein VCL-Projekt entsteht dann über die OTA mit Hauptformular und ungespeicherten Projekt-/Unit-/DFM-Puffern.
DAI legt dabei keine Verzeichnisse an und ruft keine Speicherfunktion auf. Ohne `save` gilt weiterhin `true`; spätere IDE-Builds beachten Delphis eigene
Option zum automatischen Speichern. Die tatsächliche Projektdatei und Hauptformpfade stehen in der Antwort.

## IDE- und Anwendungsfenster lesen

`ide_windows_list` liest native Fenster der IDE einschließlich MessageBox und TaskDialog sowie verfügbare VCL-Form-/Controlmetadaten.
`debugger_windows_list` verwendet die Windows-Prozess-ID des aktuellen OTA-Debuggerprozesses und liest dessen native Fenster.
Die ToolsAPI liefert keinen allgemeinen Katalog der Fenster des Debuggees; dafür verwendet DAI die WinAPI.

Die Werkzeuge lesen ausschließlich: kein Klick, Schließen, keine Steuernachrichten und kein Fortsetzen des Debuggees. Eigene DAI-Berechtigungsdialoge
und Eingabefeldtexte werden ausgelassen. Grenzen sind 100 Fenster, 500 Controls und 2 Sekunden; `text_status` und `truncated` zeigen fehlende
Texte oder abgebrochene Abfragen. Ein angehaltener oder nicht antwortender Prozess kann seine Controltexte nicht liefern.
VCL-Handles werden nur ausgelesen, wenn sie bereits angelegt sind; DAI erzeugt für die Inspektion keine neuen Fensterhandles.

## Code Insight und Delphi-LSP

DAI greift nicht als zweiter JSON-RPC-Client auf die privaten Standard-I/O-Pipes der von Delphi gestarteten `DelphiLSP.exe` zu. Stattdessen verwendet es den
bereits von der IDE verwalteten Provider über `IOTACodeInsightServices` und `IOTAAsyncCodeInsightManager`. Dadurch gelten dieselbe Projektkonfiguration,
dieselben Suchpfade und der von Delphi synchronisierte aktuelle Editorstand.

Die Integration ist ausschließlich lesend:

- `code_insight_status` listet Provider, Bereitschaft und unterstützte Operationen auf.
- `code_definition` ermittelt die Definition eines Symbols. `line` ist einsbasiert, `character` ist der nullbasierte Zeichenindex vor Tabulator-Expansion.
- `code_hover` liefert das IDE-Help-Insight. `line` und `column` sind einsbasierte Editorpositionen; die Datei muss sichtbar in einem Code-Editor geöffnet sein.
- `file_diagnostics` liest Fehler, Warnungen und Hinweise über `IOTAModuleErrors`; die Datei muss von der IDE geladen sein.
  `diagnostics_api` nennt `IOTAModuleErrors.GetErrors`; `diagnostics_freshness` ist `unknown` bei vorhandener Schnittstelle, sonst `unavailable`.
  Die ToolsAPI liefert keine Diagnoseversion und keine Prüfung eines beliebigen übergebenen Texts. Eine leere Liste beweist daher keine abgeschlossene
  Prüfung des neuesten Editorpuffers; für eine verbindliche Syntax-/Semantikprüfung den aktuellen Projektstand kompilieren.
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
%USERPROFILE%\.agents\skills\dai-delphi-ide\SKILL.md
```

Ohne `CODEX_HOME` verwendet DAI ausdrücklich `%USERPROFILE%`. `TPath.GetHomePath` zeigt unter Windows auf `%APPDATA%` und ist für diese benutzerspezifischen Codex-Pfade ungeeignet.
Beim nächsten Registrieren entfernt DAI ausschließlich eigene markierte Altinhalte unter `%APPDATA%`.

Der persönliche Skill liegt unter `.agents\skills`; ein Verzeichnis `.skills` wird von DAI nicht verwendet. Der Skill enthält nur Arbeitsanweisungen. Port und Bearer-Token stehen ausschließlich im verwalteten Block der `.codex\config.toml`. Nach einer Änderung von Port oder Token ist erneut `Registrieren` auszuführen und Codex neu zu starten.

„Registrieren“ ergänzt ausschließlich einen markierten DAI-Block und den verwalteten Skill. „Deregistrieren“ entfernt nur diese verwalteten Inhalte.

Der verwaltete Skill heißt `dai-delphi-ide`, einschließlich seines Verzeichnis- und YAML-Namens. `SKILL.md` bleibt der vorgeschriebene Einstiegsdateiname.
Registrieren migriert eigene ältere `delphi-ide\SKILL.md`-Dateien unter `%USERPROFILE%` und `%APPDATA%` nach erfolgreichem Schreiben des neuen Skills.
Status und Deregistrierung erkennen beide alten Pfade. `MigrateSkillFiles` führt nur diese Skillmigration durch, ohne Einstellungen oder Clientkonfigurationen zu schreiben.
Fremde Inhalte werden anhand fehlender DAI-Marker erhalten; ein fremdes neues Ziel führt vor Änderung der Clientkonfiguration zum Konflikt.
Eigene Verwaltungsdateien heißen `<Clientkonfiguration>.dai-registration.json`; Sicherungen/temporäre Dateien enthalten `.dai-<GUID>.bak` bzw. `.tmp`.
Vorgeschriebene gemeinsame Clientdateinamen wie `config.toml`, `settings.json`, `mcp.json` und `config.yaml` behalten ihren Namen.
Ein bereits vorhandener, nicht markierter `[mcp_servers.dai]`-Abschnitt wird nicht überschrieben.

Der erzeugte `SKILL.md` enthält gültige YAML-Metadaten (`name`, `description`), aktuelle Werkzeugnamen, Parameter, Hashkonfliktbehandlung und Zugriffsgrenzen.
Ein vorhandener fremder `dai-delphi-ide`-Skill wird nicht überschrieben. Die automatische Skill-Erkennung ist hier für Codex eingerichtet; andere Clients benötigen ihre eigene Skill-Installation.

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
.\Build.ps1 -Configuration Release -Platform Both
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
Build\Win64\Release\Bpl\DAI.bpl
Build\Win64\Release\Bpl\DAI.McpBridge.exe
```

Win32 und Win64 sind im DPROJ aktiviert. Mit `-Platform Win32` oder `-Platform Win64` kann auch nur eine Architektur gebaut werden.
`Build.ps1` prüft nach jedem Build PE-Signatur, Zielarchitektur und DLL-/EXE-Typ der Ausgaben.

## Installation in der 32- und 64-Bit-IDE

Das Design-Time-Package muss zur Architektur der **IDE** passen. Die Zielplattform eines geöffneten Anwendungsprojekts ist dafür nicht maßgeblich.

| IDE | Programm relativ zu `%BDS%` | Package relativ zum DAI-Projekt | Package-Schlüssel unter dem BDS-Benutzerprofil |
| --- | --- | --- | --- |
| 32 Bit | `bin\bds.exe` | `Build\Win32\Release\Bpl\DAI.bpl` | `Known Packages` |
| 64 Bit | `bin64\bds.exe` | `Build\Win64\Release\Bpl\DAI.bpl` | `Known Packages x64` |

Bei der vorliegenden Installation lauten die Schlüssel:

```text
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages x64
```

In der jeweiligen IDE über `Component → Install Packages → Add` das passende BPL auswählen. Die native Bridge aus demselben Buildverzeichnis neben dem BPL belassen.
Die Package-Zuordnung erfolgt über die verschiedenen Schlüsselnamen; ein Wechsel der Registry-View allein ersetzt sie nicht. DAI verändert diese Schlüssel nicht selbst.
Beide vollständigen Package-Builds wurden mit Delphi 13 / BDS 37.0 geprüft. Packages für andere Delphi-Versionen müssen mit deren passender Toolchain gebaut werden;
deren API-Kompatibilität ist hier nicht verifiziert. Die globale Instanzsperre selbst ist versionsunabhängig.

Referenzen: [64-Bit-IDE](https://docwiki.embarcadero.com/RADStudio/Florence/en/64-bit_IDE),
[Package-Installation](https://docwiki.embarcadero.com/RADStudio/Florence/en/InstallIDEPackage).

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
.\Scripts\Test.Instance.ps1 -Platform Both
.\Scripts\Test.SourceView.ps1 -Platform Both
.\Scripts\Test.SourceSearch.ps1 -Platform Both
.\Scripts\Test.SearchService.ps1 -Platform Both
.\Scripts\Test.SourcePaths.ps1 -Platform Both -StrictSeparators
.\Scripts\Test.EditorWrite.ps1 -Platform Both
.\Scripts\Test.Windows.ps1 -Platform Both
.\Scripts\Test.ReadOnlyPolicy.ps1 -Platform Both
python .\Scripts\test_bridge.py
```

Die Instanztests verwenden eigene zufällige Objektnamen und prüfen auch getrennte Win32-/Win64-Prozesse sowie Prozessabbruch.
Dabei werden keine tatsächlichen Client-Konfigurationen verändert und keine Designer-/Debuggeraktionen in der laufenden IDE ausgelöst.

## Statische Prüfung

```powershell
python .\Scripts\verify.py
```

Geprüft werden unter anderem Dateinamen, Unit-Namen, DPK-/DPROJ-Referenzen, XML, erforderliche MCP-Werkzeuge, bekannte ungültige Delphi-Typen, fehlende DAI-Typdeklarationen, Altbezeichnungen, unqualifizierte `TMonitor`-Aufrufe, Tabulatoren, gemischte Zeilenenden und die maximale Zeilenlänge von 180 Zeichen.

## Hinweis zur Binärprüfung

Der überarbeitete Stand wurde mit der lokal installierten Delphi-13-Toolchain kompiliert. Die IDE-Integration von Designer, Debugger und Dialogen
muss zusätzlich im laufenden RAD Studio geprüft werden; Compiler- und isolierte Protokolltests ersetzen diesen Praxistest nicht.
