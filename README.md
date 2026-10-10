# DAI – Delphi AI

DAI ist ein Design-Time-Package für Delphi 13 / RAD Studio 13 (`BDS 37.0`). Es stellt lokal laufenden KI-Clients einen MCP-Server zur Verfügung und
vermittelt kontrollierte Zugriffe auf die Delphi OpenToolsAPI.

Zum Betrieb benötigt DAI sein zur IDE-Version und -Architektur passendes Package (bei Delphi 13: `DAI370.bpl`) und die mit Delphi installierten Runtime-/Design-Time-Packages.
Eigene PAS/DCU/DCP-Dateien oder GetIt-Packages werden nicht benötigt. Port, Token, Berechtigungsdateien und die Clientregistrierung bleiben Konfiguration.
Für Clients mit stdio-Anbindung wird zusätzlich die eigenständige `DAI.McpBridge.exe` neben der BPL bereitgestellt: Sie liest zeilenweise JSON-RPC von
stdin, sendet authentifizierte HTTP-Anfragen an den MCP-Server der laufenden IDE und gibt Antworten über stdout zurück.
Zusätzlich stellt dieselbe EXE mit `--launcher` den unabhängigen STDIO-Server `dai_start` bereit. Dieser kann Delphi starten, laufende IDEs prüfen
und eine IDE auch ohne aktives DAI schließen. Die regulären Werkzeuge bleiben unter `dai` über HTTP beziehungsweise die bestehende STDIO-Brücke erreichbar.

Die bestehende Fehlersuche-Toolbar (`sDebugToolBar`) erhält einen DAI-Schalter mit Serverzustand und Port im Tooltip. Ein Klick startet/stoppt den Server;
das Dropdown öffnet die DAI-Optionen/Berechtigungen oder setzt Sitzungsfreigaben zurück. DAI erstellt dafür keine eigene Toolbar.
Solange ein IDE-Menü geöffnet ist, werden Status- und Layoutaktualisierungen der DAI-Werkzeugleiste zurückgestellt.
Das DAI-Dropdown verwendet feste Tastenkürzel, damit der Statustimer keinen Neuaufbau des angezeigten Menüs auslöst.
Transparente Serversymbole zeigen eine graue Pause für inaktiv, ein grünes Play-Dreieck für aktiv und ein rotes X bei Fehlern.
Bei aktivem Server zeigt ein gelber Kreis MCP-Zugriff innerhalb der letzten 15 Sekunden, danach ein ockerfarbener Kreis bis 15 Minuten.
Ohne Zugriff oder nach mehr als 15 Minuten erscheint wieder Play. Inaktiv und Fehler haben Vorrang vor der Zugriffsanzeige.
Gezählt werden authentifizierte MCP-POSTs nach den Transport-/Sitzungsprüfungen und erfolgreiche Session-DELETEs, auch wenn ein Tool einen Fehler meldet.
Health-Abfragen und abgewiesene HTTP-Zugriffe verändern die Anzeige nicht. Der bestehende Statustimer aktualisiert sie alle 500 ms.
Die primäre Größe beträgt 16×16; weitere Auflösungen werden der IDE über `INTAServices280.AddImage` angeboten. Dafür wird Delphis Standardpackage `vclimg` verwendet.
Die DAI-Aktion hat denselben stabilen Besitzer wie die IDE-ActionList. Beim Entfernen werden auch Toolbar-Klone derselben Aktion beseitigt.
Ein öffentlicher ToolsAPI-Lesenotifier erfasst den ursprünglich benannten DAI-Button beim Toolbarrestore. Nach dem Lesen wird dieses
eigene Objekt wieder mit Aktion und Menü verbunden; auch ein Restore vor dem ersten UI-Aufbau erzeugt damit keinen zusätzlichen Button.
Nur unmittelbar nach dieser bestätigten Wiederverwendung darf außerdem ein einzelner vollständig inerter historischer Altrest entfernt werden.
Eine begrenzte Migration entfernt die bestätigten alten drei bis fünf vollständig inerten Dropdown-Buttons unmittelbar zwischen „Rückkehr“
und dem eigenen DAI-Button. Der Rückkehr-Button wird über die konkrete Aktion der offiziellen IDE-ActionList erkannt, da Delphi die
Komponentennamen beim Wiederherstellen verlieren kann. Die Prüfung berücksichtigt auch spätere Desktoprestores bei erhaltenen Controls;
abweichende Controls, fremde Aktionen und Objekte im Abbau bleiben erhalten.
Nach Einbinden und Bereinigen ergänzt DAI den fehlenden horizontalen Platz bis zum rechten Rand seines tatsächlichen nativen Buttonrechtecks.
Die feste Breite der IDE-Toolbar kann sonst einen vorhandenen VCL-sichtbaren Button vollständig abschneiden. Position, Höhe, DPI,
Größenbeschränkungen und bereits größere Breiten werden berücksichtigt; gewöhnliche Refreshes verändern die Breite nicht.
Die ReadOnly-Fensterinspektion liefert dafür Button-/Clientrechtecke, native Sichtbarkeit und Bildbestand. `visible` allein bezeichnet
die VCL-Eigenschaft; der native Clientbereich entscheidet, ob der Button tatsächlich Platz hat.
Die Optionsseite zeigt über „Skill und MCP-Werkzeuge“ den aktuellen dynamischen Katalog; Details zur Clientregistrierung sind um vier Leerzeichen eingerückt.

`ide_window_control(action)` bietet `minimize`, `restore`, `foreground`, `background` und `close`. Windows kann eine Vordergrundanforderung ablehnen;
die Antwort meldet den tatsächlichen Fensterzustand. `close` bestätigt vor `WM_CLOSE` den normalen Schließauftrag, keine abgeschlossene Beendigung.
Delphi behält seine Speicherrückfragen und kann das Schließen abbrechen. Das Werkzeug benötigt IDE-Bearbeitungsrechte, `close` zusätzlich Ausführungsrechte.

Die Debugger-ToolsAPI liefert die Windows-Prozess-ID, Threads, Debuggerzustand und Speicherzugriff. Fenster und Dialoge des Debuggees werden mit
`debugger_windows_list` über diese PID und die WinAPI gelesen; direkte fremde VCL-Formobjekte werden nicht angeboten. `Screen.ActiveCustomForm` gehört
zum VCL-Prozess der IDE. Beim angehaltenen Debuggee können dessen Controltexte wegen blockierter Nachrichtenverarbeitung fehlen.

## Unabhängiger Delphi-Starthelfer

Die lokale Clientregistrierung ergänzt `dai_start` neben `dai`. Der Helfer startet beim Verbinden des MCP-Clients, seine Werkzeuge funktionieren
auch ohne laufendes Delphi. Registriert wird der vollständige EXE-Pfad der gerade registrierenden IDE; die letzte Registrierung je Client legt
Version und Win32-/Win64-IDE fest. Ein ausdrücklich verwendetes `-r`-Profil wird gezielt übernommen; andere IDE-Startargumente werden nicht wiederholt.

In den DAI-Optionen ist **„KI darf die Delphi-IDE starten und beenden“** standardmäßig aktiviert. Diese Freigabe gilt gemeinsam für alle
Delphi-Versionen und Profile desselben Windows-Benutzers. Nach dem Speichern sperrt eine deaktivierte Option `delphi_start`, beide Modi von
`delphi_stop` und `ide_window_control` mit `action: close`. Andere Fensteraktionen bleiben verfügbar. Die bestehenden DAI-Berechtigungen gelten zusätzlich.
`dai_start` bleibt registriert; `delphi_status` und `ide_status` liefern unter `lifecycle_control` die aktuelle Freigabe und den Grund.
Bereits laufende Helfer lesen die gespeicherte Freigabe erneut; dafür ist weder eine erneute Registrierung noch ein Clientneustart erforderlich.
Der gemeinsame Wert `AllowIDEStartStop` liegt unter `HKEY_CURRENT_USER\Software\DelphiAI\DAI` in der 64-Bit-Registryansicht.
Fehlender Schlüssel/Wert bedeutet erlaubt; ein ungültiger oder unlesbarer Wert sperrt Start und Beenden. Ein unveränderter Optionsdialog oder
das Speichern anderer DAI-Einstellungen überschreibt die Freigabe nicht. Abbrechen verwirft ungespeicherte Checkboxänderungen.
Codex, Claude Code/Desktop, Gemini CLI/Code Assist, Hermes, LM Studio und OpenClaw erhalten den zusätzlichen lokalen STDIO-Eintrag.
Für Eigent wird eine manuelle Konfiguration beschrieben; für Gemini Desktop gibt es weiterhin keinen verifizierten lokalen MCP-Registrierungsweg.
OpenClaw benötigt einen lokalen Windows-Gateway, Hermes ein natives Windows-Profil. Der Helfer stellt keinen zusätzlichen HTTP-Listener bereit.

| Werkzeug | Funktion |
|---|---|
| `delphi_status` | Helferversion, registrierter DAI-Stand, registrierte IDE und laufende IDEs mit PID, EXE, Architektur, Version und Prozessstartzeit; DAI-Erreichbarkeit und tatsächlich antwortende Version. |
| `delphi_start` | Registrierte IDE starten oder eine eindeutig passende laufende Instanz wiederverwenden; begrenzt auf DAI-Bereitschaft warten. |
| `delphi_stop` | Externes normales Schließen mit `mode: close`; ausdrücklich erzwungenes Beenden mit `mode: terminate`; auf das Prozessende warten. |

Zuerst `dai/ide_window_control` mit `action: close` verwenden. Danach mit `dai_start` das Prozessende prüfen. Bei nicht erreichbarem DAI oder einer
blockierten IDE hilft `delphi_stop`. `close` sendet `WM_CLOSE` an das verifizierte IDE-Hauptfenster und bewahrt Speicherrückfragen sowie Abbruch.
`terminate` beendet ausschließlich den ausgewählten Prozess hart; ungespeicherte Änderungen gehen verloren. Es gibt keine automatische Eskalation
bei Timeout, Speicherrückfrage oder Abbruch. Erst `outcome: exited` beziehungsweise `not_running` bestätigt, dass die Zielinstanz beendet ist.
Ein verschwundener HTTP-Port genügt dafür nicht.

Die Standardauswahl verwendet die eindeutig laufende registrierte EXE. Bei mehreren passenden Instanzen oder besonderen IDE-Profilen zum Beenden
`process_id` und die unveränderte `creation_time` aus `delphi_status` angeben. Die Prozessstartzeit ist eine dezimale FILETIME-Zeichenfolge.
Der Helfer hält während Aktion und Wartephase einen geprüften Prozesshandle, damit eine erneut vergebene PID keine andere Instanz trifft.
Bei einem besonderen Profil wird eine schon laufende Instanz nur wiederverwendet, wenn sie von diesem Helfer mit diesem Profil gestartet wurde.
Der Helfer beendet keine IDE beim Schließen seiner STDIO-Eingabe und verwirft oder speichert beim normalen Schließen keine Änderungen selbst.

`ide_running` bedeutet, dass mindestens eine IDE-Instanz gefunden wurde; `registered_ide_running` bezeichnet die registrierte EXE.
`running_ides` enthält die Instanzen der aktuellen Windows-Sitzung. Nicht zugängliche Prozesse werden als unverifiziert gemeldet;
`enumeration_complete: false` kennzeichnet einen unvollständig feststellbaren Zustand. Eine weitere IDE wird dann nicht blind gestartet.
Der DAI-Status gilt für den registrierten Endpunkt: `active`, `unreachable`, `unauthorized` oder `unverified`. Der Token wird ausschließlich an einen
verifizierten Delphi-Listener gesendet. Andere laufende IDEs und ein nicht erreichbarer Endpunkt beweisen nicht, dass DAI insgesamt inaktiv ist.
Die tatsächliche DAI-Version stammt aus der MCP-Antwort, die registrierte Version bleibt separat. Nach dem Start kann ein zuvor fehlgeschlagener
HTTP-Eintrag ein erneutes Verbinden des KI-Clients benötigen. Bereits laufendes Delphi mit deaktiviertem DAI wird nicht automatisch neu gestartet.

`timeout_ms` ist optional: Start standardmäßig 20000, Stop 5000, jeweils maximal 30000 Millisekunden. Nach einer Wartezeit kann die IDE weiterhin
laufen; Status erneut prüfen. Auch ohne Token funktionieren die lokalen Prozesswerkzeuge, die DAI-Bereitschaft kann dann nicht bestätigt werden.
Manueller Aufruf (der Client kommuniziert anschließend über STDIN/STDOUT):

```text
DAI.McpBridge.exe --launcher --url http://127.0.0.1:7331/mcp --ide "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\bds.exe" --dai-version 1.2.25
```

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
bestimmen, welches BPL oder IDE-Plugin innerhalb dieses Prozesses den Socket geöffnet hat. Einen freien Port eintragen und im selben Dialog
mit „Server starten“ erneut starten; dauerhaftes Speichern kann danach erfolgen.

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

Start/Stop kehren erst nach Abschluss zurück. Während Stop werden erneute Start-/Übernahmeaufrufe abgewiesen. Auf dem IDE-Hauptthread schließt DAI
zuerst den Listener; ein Hilfsthread beendet danach die HTTP-Arbeiter, während `WaitFor` wartende `Synchronize`-Aufrufe verarbeitet. Socketbindungen
und die Instanzsperre werden erst nach vollständigem Abschluss freigegeben. Fehler enthalten den tatsächlichen Winsock-Code und, sofern vorhanden,
die eigenen Socketzustände vor/nach dem letzten Stop. Bei eingeschaltetem Zugriffslogging werden auch erfolgreiche Stopdiagnosen angezeigt.

Listener und angenommene HTTP-Sockets werden vor ihrer Verwendung als nicht vererbbar markiert und geprüft (`SetHandleInformation`).
Damit behalten IDE-Kindprozesse wie LSP-/Hilfsprogramme keinen DAI-Socket nach dessen Stop. Bereits von älteren Versionen vererbte Sockets
werden erst mit dem Ende der betreffenden Prozesse freigegeben; nach dem Package-Austausch ist deshalb eine frische IDE-Sitzung erforderlich.
Windows-Sockets sind standardmäßig vererbbar; siehe [Microsoft WSASocket](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsasocketw)
und [SetHandleInformation](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-sethandleinformation).
**MCP-Server beim IDE-Start automatisch starten** gilt nur beim Start der IDE bzw. beim Laden des Packages. Das Übernehmen der Optionen bewahrt den manuellen
Laufzustand. Bei einem laufenden Server werden Port- und Tokenänderungen mit einem Neustart des Listeners angewendet; dabei bleibt die Instanzsperre gehalten.

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

Der automatisch ausgelöste Fragedialog verwendet den Berechtigungsbereich der konkreten Anfrage: bei zugeordnetem Projekt dieses Projekt, sonst global.
„Immer“ und „Nie“ erzeugen auch bei geerbtem globalem „Nachfragen“ eine eigene Projektvorgabe. Explizite Projekt-/Dateiangaben können ein anderes
geladenes Projekt zuordnen; Debuggerauswertungen verwenden ausdrücklich den globalen Bereich. Der Dialog zeigt das Projekt beziehungsweise „global“ an.
„Nur diesmal“ und „Verweigern“ gelten nur für die Anfrage; „Für diese Session“ bleibt als Freigabe für den erkannten KI-Chat im jeweiligen Bereich im Speicher.

Die Funktionsgruppen werden getrennt behandelt:

- Lesezugriffe
- Bearbeiten innerhalb der IDE
- Dateien außerhalb der IDE bearbeiten
- Kompilieren
- Ausführen

Dauerhafte Projektentscheidungen werden neben der Projektdatei in `<Projektname>.dai.permissions.json` gespeichert. Die Optionsseite zeigt den globalen
Standard und das aktuelle Projekt nebeneinander mit jeweils 190 Pixel breiten ComboBoxen. Ohne aktives Projekt sind die Projektfelder deaktiviert.
Rechts jeder Zeile öffnet ein einzelner Schild-Iconbutton den Berechtigungsdialog für das angezeigte aktive Projekt, sonst für den globalen Standard.
Der Dialog nennt den Bereich ausdrücklich; seine Auswahl bleibt bis zum Speichern ein Entwurf. Globale Werte lassen sich jederzeit direkt in ihrer ComboBox ändern.

„Default“ in der Projektspalte bedeutet, dass die Berechtigung vom globalen Standard geerbt wird. Der Hinweistext nennt den geerbten Wert.
Die Auswahl „Default“ entfernt beim Speichern die eigene Projektvorgabe und ihre Laufzeitrechte; andere Projektberechtigungen bleiben erhalten.
Es werden nur bearbeitete Berechtigungen übernommen, sodass unveränderte geerbte Werte keine eigenen Projektvorgaben erzeugen.
„Verweigern“, „Nur einmal“ und „Session“ sind Laufzeitentscheidungen; „Nie“, „Nachfragen“ und „Immer“ werden persistent gespeichert.

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
Rohe Unicode-Zeichen in DFM-/FMX-Stringliteralen werden über die native Formularserialisierung als `#nnn` normalisiert, damit der Designer
UTF-8-Bytes nicht als ANSI-Zeichen übernimmt. `sha256` beschreibt anschließend den tatsächlichen Editorpuffer. Der Textmoduswechsel schützt
die PAS-Unit durch Vergleich ihres vollständigen Editorinhalts mit der gespeicherten Datei; alleinige DFM-Änderungen verhindern den Wechsel nicht.

`file_read` liefert zusätzlich `encoding` und `line_ending`. `file_write` meldet außerdem die ursprüngliche und die nach dem Schreibvorgang verwendete
Codierung sowie die ursprüngliche und resultierende Art des Zeilenumbruchs.

## Quelldateien und Referenzen finden

`source_search` sucht mit `query` wörtlichen Text, etwa `IOTADebuggerServices` oder `TButton`; `use_regex: true` interpretiert die Abfrage als RegEx.
Treffer liefern Datei, Zeile, Spalte und Ausschnitt. Ohne die neue Option bleibt die bisherige wörtliche Suche erhalten.
`interfaces_only` ist standardmäßig `true`: Pascal-Units werden vor der Suche ab dem echten `implementation`-Schlüsselwort abgeschnitten.
Treffer und Ausschnitte können deshalb keinen nachfolgenden Implementierungscode enthalten; ursprüngliche Zeilen und Spalten bleiben erhalten.
Für Methodenrümpfe und Verwendungen dort `interfaces_only: false` setzen. Kommentare, Direktiven, Strings und escaped identifiers lösen keinen Schnitt aus.
Andere Dateitypen sowie Inhalte ohne erkannten Unit-/Interface-Kopf bleiben unverändert. Die Filterung erfolgt lexikalisch ohne Compiler-Präprozessor.
Die Antwort nennt den angeforderten Modus und `implementation_files_omitted`, die Zahl tatsächlich gekürzter Dateien.
`scope` wählt `project`, `group`, `references` oder `all` (Standard); `project`, `directory` und `file_patterns` grenzen die Suche ein.
`filename_regex` prüft zusätzlich den Dateinamen ohne Verzeichnis; der bisherige Dateifilter und die RegEx müssen beide passen.
Aktuelle Editor- und Designerpuffer haben Vorrang vor Dateien auf dem Datenträger. Die Standardmuster sind `*.pas`, `*.inc`, `*.dpr` und `*.dpk`.
Dateimuster verwenden ausschließlich `*` und `?` auf dem Dateinamen, höchstens 100 Muster mit jeweils 256 Zeichen; Zeichenklassen werden abgelehnt.
`case_sensitive` ist standardmäßig `false` und gilt für den Suchtext sowie `filename_regex`. Die bisherigen Dateimuster bleiben unabhängig davon
ohne Beachtung der Groß-/Kleinschreibung. `whole_word` prüft bei wörtlicher und RegEx-Suche die Bezeichnergrenzen um den gesamten Inhaltstreffer.

Beispiel für `source_search`: Button-/Edit-Typen in den vollständigen DAI-Units suchen:

```json
{
  "query": "T(Button|Edit)",
  "use_regex": true,
  "scope": "project",
  "file_patterns": ["*.pas"],
  "filename_regex": "^h5u\\.DAI\\..*\\.pas$",
  "whole_word": true,
  "interfaces_only": false
}
```

`directory_files_list`, `project_directory_files_list` und `reference_files_list` unterstützen ebenfalls `filename_regex` sowie optional
`content_query`. Der Inhaltsfilter ist wörtlich; mit `content_use_regex: true` wird er als RegEx ausgewertet. `case_sensitive` gilt für beide
RegEx-Filter und den wörtlichen Inhaltsfilter; `whole_word` betrifft nur Inhaltstreffer. `search_pattern`, Dateinamen-RegEx und Inhaltsfilter
werden mit UND verknüpft. Der Inhaltsfilter liest den vollständigen aktuellen Editor-/Designertext, sonst die Datei mit ihrer erkannten Codierung.
Er schneidet keine Pascal-Implementierung ab. Nicht lesbare, binäre oder mehr als 16 MiB große Inhalte führen zu einem Fehler mit Dateipfad.

Beispiel für `project_directory_files_list`: DAI-Pascal-Dateien mit einer passenden Klassendeklaration auflisten:

```json
{
  "search_pattern": "*.pas",
  "recursive": true,
  "filename_regex": "^h5u\\.DAI\\..*\\.pas$",
  "content_query": "TDAI\\w+\\s*=\\s*class",
  "content_use_regex": true
}
```

RegEx-Filter suchen auch Teiltreffer; für einen vollständigen Dateinamen `^` und `$` verwenden. In JSON wird jeder RegEx-Backslash als `\\`
geschrieben. Inhalts-RegEx kann mehrere Zeilen umfassen: `(?m)` lässt `^`/`$` an Zeilengrenzen greifen, `(?s)` lässt `.` auch Zeilenumbrüche erfassen.
Ungültige RegEx-Syntax und überschrittene RegEx-Ausführungsgrenzen melden einen Fehler; sie werden nicht als „keine Treffer“ behandelt.
RegEx verwenden Delphis PCRE-Engine mit Unicode-Zeichenklassen, etwa für `\w` und `\d`. `\G` und die Scan-Steuerverben
`(*SKIP)`, `(*COMMIT)`, `(*PRUNE)` und `(*THEN)` werden ausdrücklich abgewiesen. Pro Matchversuch gelten Grenzen
von 100.000 Backtracking-Aufrufen und 256 Rekursionsebenen; zwischen Matchversuchen wird ein Scanbudget von 500 ms geprüft.
`content_use_regex: true` erfordert eine nicht leere `content_query`; ohne Inhaltsabfrage werden Dateien nicht dafür gelesen.

`source_search` endet standardmäßig nach 200 Treffern, 10.000 Dateien oder 5 Sekunden; die Obergrenzen liegen bei 1.000 Treffern, 100.000 Dateien und
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

`ide_logs_read` liest die vorhandenen Compilerzeilen mit `source: "build"` und das Debugger-Ereignislog mit `source: "events"` getrennt.
Standard sind die letzten 50 Einträge; `last_count` begrenzt auf 1–1000, `index` wählt stattdessen genau eine Zeile mit Index ab 0.
`maximum_characters` begrenzt den übertragenen Text, standardmäßig auf 20.000 Zeichen. `total_count` beschreibt die vorhandene Liste;
`returned_count`, Zeilenindizes, `truncated`, `text_truncated` und `timed_out` zeigen den Umfang und die Grenzen der Antwort.
Die Zeilen bleiben chronologisch. Nicht erstellte oder nicht unterstützte Logkontrollen melden `available: false` und einen Grund, keine angeblich leere Liste.

Die installierten öffentlichen OTA-Interfaces liefern Gruppenmetadaten und Ereignisbenachrichtigungen, aber keine Enumeration bestehender Logzeilen.
DAI liest deshalb die bekannten VCL-Logkontrollen über verifizierte öffentliche Baum-Getter der bereits geladenen Delphi-13-IDE-Bibliothek.
Der Adapter prüft Klassen und Exporte zur Laufzeit, behandelt Nodes nur als opaque Handles und verändert weder Tabwahl, Filter, Auswahl noch Loginhalt.

`ide_windows_list` liest native Fenster der IDE einschließlich MessageBox und TaskDialog sowie verfügbare VCL-Form-/Controlmetadaten.
`debugger_windows_list` verwendet die Windows-Prozess-ID des aktuellen OTA-Debuggerprozesses und liest dessen native Fenster.
Die ToolsAPI liefert keinen allgemeinen Katalog der Fenster des Debuggees; dafür verwendet DAI die WinAPI.

Die Werkzeuge lesen ausschließlich: kein Klick, Schließen, keine Steuernachrichten und kein Fortsetzen des Debuggees. Eigene DAI-Berechtigungsdialoge
und Eingabefeldtexte werden ausgelassen. Grenzen sind 100 Fenster, 500 Controls und 2 Sekunden; `text_status` und `truncated` zeigen fehlende
Texte oder abgebrochene Abfragen. Ein angehaltener oder nicht antwortender Prozess kann seine Controltexte nicht liefern.
VCL-Handles werden nur ausgelesen, wenn sie bereits angelegt sind; DAI erzeugt für die Inspektion keine neuen Fensterhandles.

## Aktive VCL-Dialoge

`ide_dialog_inspect` liest `Screen.ActiveCustomForm`, sofern es sich um einen sichtbaren aktiven modalen VCL-Dialog handelt.
Die Antwort enthält Formklasse/-name, Titel, Controls und Buttons sowie einen 30 Sekunden gültigen `snapshot_token`.
Jedes neue Auslesen ersetzt die vorherige Momentaufnahme.
`ide_dialog_click` betätigt einen sichtbaren aktivierten Button anhand seines tatsächlichen Namens; `ide_dialog_close` setzt `Form.ModalResult`.
Beide Aktionen erfordern IDE-Bearbeitungs- und Ausführungsrechte. Zwischen Auslesen und Aktion muss derselbe Dialog aktiv bleiben.
Geschlossene/ersetzte Dialoge, verbrauchte Tokens und ungültige Buttons werden abgewiesen. Nach einem Buttonklick werden keine Formobjekte mehr ausgelesen.
Texte aus Eingabefeldern werden ausgelassen; DAI-Berechtigungsdialoge sind von Auslesen und Aktionen ausgeschlossen. WinAPI-Dialoge sind hier nicht enthalten.

DAI-Builds verwenden den dokumentierten `IOTAProjectBuilder.BuildProject`-Parameter `Wait=False`:
Erfolgreiche Builds warten nicht auf „OK“ im Fortschrittsdialog. Fehler dürfen weiter sichtbar bleiben; die Rückgabe meldet den tatsächlichen Build-Erfolg.
`IOTACompileNotifier` meldet Projekt-/Gruppenstart und -ende, enthält aber keinen Parameter zum Ersetzen des Dialogs.
Debuggernotifier melden unter anderem `nrException`/`psException`; sie garantieren keine Unterdrückung des Exception-Dialogs.

## Projektübersicht

Pro Delphi-IDE-Instanz gibt es eine aktuelle Projektgruppe mit mehreren möglichen Projekten.
`projects_list` liefert deren Basisinformationen in einem Aufruf. Die bisherigen Felder `name`, `file`, `directory`,
`configuration` und `platform` bleiben erhalten; Konfiguration und Plattform gehören jeweils zur aktuellen Auswahl dieses Projekts.

| Feld | Bedeutung |
| --- | --- |
| `active` | Kennzeichnet das aktive Projekt der Gruppe. |
| `output_type` | Aufbereiteter Ausgabetyp: `EXE`, `DLL` oder `Package`. |
| `project_type`, `application_type`, `framework_type` | Unveränderte SDK-Typ- und Frameworkwerte, etwa Console, VCL, FMX oder None. |
| `target_name`, `target_file` | SDK-Zielname und aufgelöster vollständiger Ausgabepfad für die aktuelle Konfiguration und Plattform. |
| `project_version` | Formatversion der DPROJ; keine Produkt- oder Dateiversion. Vor Änderungen am Projektformat beachten. |
| `package.description` | Beschreibung des Packages. |
| `package.usage` | `runtime`, `design_time` oder `runtime_and_design`. |
| `package.build_mode` | `automatic` oder `manual`. |
| `package.registered`, `package.enabled`, `package.loaded` | Registrierung, Aktivierung und tatsächlicher Ladezustand des aktuellen Ausgabeziels in dieser IDE. |

Bei anderen Projekttypen ist `package` gleich `null`. Nicht ermittelbare Zusatzwerte sind ebenfalls `null`; unbekannt bedeutet nicht `false`.
Eine vorhandene BPL bestätigt weder ihre Registrierung noch den Ladezustand; ein registrierter anderer Ausgabepfad bestätigt das aktuelle Ziel nicht.
Die Übersicht aktiviert keine Projekte und verändert keine Optionen. `project_context` liefert bei Bedarf die ausführlicheren Projektdatei-/Compilerinformationen;
`project_options_configurations` bleibt für die vollständige Konfigurationsübersicht verfügbar. Einzelne Optionsabfragen sind für diese Basisinformationen nicht nötig.

## Packages in der IDE verwalten

`package_is_installed` liest den Registrierungs-, Aktivierungs- und Ladezustand eines Packages in der laufenden IDE.
`installed` entspricht `registered`; `enabled` und `loaded` sind eigenständige Zustände. Unbekannte Zustände sind `null`.
Die Abfrage benötigt Leserechte und funktioniert auch bei einer fehlenden BPL oder einem RuntimeOnly-Package.

`package_install` und `package_uninstall` verwenden die öffentliche `IOTAPackageServices210` zum Installieren und Deinstallieren.
Sie erfordern Lese-, IDE-Bearbeitungs- und Ausführungsrechte. Alle drei Werkzeuge wählen entweder ein geöffnetes Package über `project`
oder einen vollständigen `.bpl`-Pfad über `file`; beide Parameter zusammen werden abgewiesen. Ohne Parameter wird das aktive Package-Projekt verwendet.
Beim Projekt gilt der ausgewertete SDK-Zielpfad der aktuellen Konfiguration und Plattform. Die Werkzeuge aktivieren kein anderes Projekt und führen keinen Build aus;
zum Erstellen der BPL bei Bedarf zuvor `project_compile` verwenden.

Die Installation verlangt eine vorhandene BPL für die Architektur der laufenden IDE und ein DesignTime- oder Run+Design-Package.
RuntimeOnly-Packages werden nicht installiert. Das laufende DAI-Package einschließlich Pfadaliasen sowie feste IDE-Packages sind gegen Änderungen geschützt;
geladene abhängige Packages können eine Deinstallation zusätzlich verhindern. Die Deinstallation löscht die BPL nicht und kann auch eine verwaiste
Registrierung für eine nicht mehr vorhandene Datei entfernen. Die Werkzeuge schreiben keine Package-Registrierung direkt in die Registry.

Die Antworten nennen `file`, `project`, `configuration`, `platform` und die Package-Zustände. Mutationen liefern zusätzlich `operation` und `succeeded`;
`succeeded` gibt den tatsächlichen booleschen SDK-Rückgabewert wieder, auch bei einem fehlgeschlagenen Auftrag. Anschließend die zurückgegebenen Zustände beachten.

```json
{"project":"C:\\Projects\\Components\\DesignPackage.dpk"}
```

Dieses Argument kann beispielsweise an `package_is_installed`, nach einem erfolgreichen Build an `package_install` und später an `package_uninstall` gehen.
Eine echte Installation oder Deinstallation in der laufenden Benutzer-IDE gehört nicht zu den isolierten Tests; diese prüfen die produktive Implementierung
mit nativen OTA-Fixtures. Release-Builds prüfen zusätzlich die Anbindung an die tatsächlich installierte ToolsAPI.

## Optionen suchen und in der IDE öffnen

`options_search` findet technische Optionsnamen und Typen aus der öffentlichen ToolsAPI. Deutsche und englische Aliasnamen helfen beispielsweise,
mit „Ausgabepfad“ die Optionen `DCC_ExeOutput`, `DCC_DcuOutput`, `DCC_BplOutput` und `DCC_DcpOutput` zu finden. Die Suche liest keine Optionswerte
und öffnet kein Fenster. `scope` wählt `all` (Standard), `ide`, `project` oder `insight`; `query` mit 1 bis 256 Zeichen ist erforderlich, `project` optional,
`maximum_results` begrenzt die Antwort auf 1 bis 500 Einträge. Für Projekte gelten die bereits geöffneten SDK-Projekte.
Der IDE-Insight-Katalog enthält die aktuell verfügbaren gecachten Einträge; seine Vollständigkeit und Aktualität sind unbekannt.

`options_open` öffnet Projektoptionen (`scope: "project"`, Standard), IDE-Optionen (`"ide"`) oder die IDE-Insight-Suche (`"insight"`).
Für Projektoptionen muss das gewählte Projekt bereits aktiv sein; ein anderes geöffnetes Projekt zuvor mit `project_activate` aktivieren.
Die optionalen Parameter `area`, `page`, `control` und `option` wählen einen Bereich, eine Seite, ein Control oder eine Option.
`option` akzeptiert den tatsächlich gefundenen SDK-Namen oder den exakten Titel eines Options-Treffers aus IDE Insight;
dazu je nach Optionskategorie `scope: "project"` oder `"ide"` wählen.
Für eine ausdrücklich angeforderte Option bevorzugt DAI die IDE-eigene Navigation über `INTAIDEInsightItem.Execute`, wenn ein eindeutiger echter
Optionseintrag in einer IDE-/Projektoptionen-Kategorie gefunden wurde. Allgemeine Commands-, Datei- oder Build-Einträge werden dafür nicht ausgeführt.
Danach bzw. als Fallback verwendet DAI die SDK-Dialogaufrufe und sucht in den tatsächlich vorhandenen Standard-VCL-Controls: beschriftete Editfelder,
Baum-/Tabseiten und Zeilen eines `TValueListEditor` oder `TStringGrid`. Private Sondercontrols oder nicht zuordenbare Optionen können
`unsupported` melden. Die Rückgabe bestätigt den erreichten Zustand; eine beliebige Delphi-Optionsseite ist nicht allgemein garantiert.

Explizite `configuration` und `platform` ändern die wirkliche aktive SDK-Auswahl des Projekts. Eine konkrete vorhandene Konfiguration und Plattform
verwenden; `Base`, `all` und `active` sind hierfür keine Schreibziele. DAI schreibt dabei keine Optionswerte und speichert das Projekt nicht automatisch.
Für Insight setzt `query` den SDK-Suchfilter und fokussiert das Suchfeld. Die öffentliche SDK bietet keinen gefilterten Ergebnisindex zur Vorwahl;
Ein Insight-Aufruf nur mit `query` zeigt die Suche; die Ausführung einer Optionsnavigation setzt die ausdrückliche Auswahl über `option` voraus.

Die modale Öffnung läuft asynchron. `options_open` gibt eine `request_id` zurück; denselben Aufruf anschließend nur mit dieser ID ausführen,
um den Status zu lesen. Weitere Selektoren zusammen mit `request_id` werden abgewiesen. Die Zustände unterscheiden `queued`, `opened`,
`focused`, `unsupported`, `error`, `closed` und `cancelled`; `page_selected` und `option_focused` bestätigen die einzelnen Schritte.
Suche und Status benötigen Leserechte. Öffnen verlangt zusätzlich
IDE-Bearbeitungs- und Ausführungsrechte, weil die native Navigation einen ausgewählten Options-Insight-Eintrag ausführen kann.

Vor der ersten asynchronen Navigation wird das eigene Package im Prozess gehalten, damit ein modaler SDK-Aufruf bei einer
reentranten Deinstallation nicht in entladenen Code zurückkehrt. Zum Austausch der geladenen BPL die IDE neu starten.

Beispiel: Mit `options_search` zunächst die Ausgabepfad-Option finden:

```json
{"scope":"project","query":"Ausgabepfad","maximum_results":20}
```

Danach mit `options_open` die Option anzeigen und bei Bedarf die aktive Auswahl auf Release/Win64 ändern:

```json
{"scope":"project","option":"DCC_ExeOutput","configuration":"Release","platform":"Win64"}
```

Den technischen Namen aus dem tatsächlichen Suchergebnis verwenden: Liefert die SDK beispielsweise `OutputDir` statt `DCC_ExeOutput`,
ist dieser Name als `option` zu übergeben. Die genannten DCC-Namen sind Beispiele für SDK-Kataloge, die sie anbieten.

Zum Lesen des späteren Status nur die tatsächlich zurückgegebene ID übergeben:

```json
{"request_id":"<zurückgegebene ID>"}
```

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

Projektoptionen können gezielt gelesen und geändert werden:

- `project_options_configurations` nennt Konfigurationen einschließlich SDK-Schlüssel, Plattform und Elternkonfiguration.
- `project_options_read` liefert lokale und effektive Werte, `has_local_value`, die Herkunft und explizite Werte der Vorfahren.
  Standard ist die aktive Konfiguration/Plattform; mit `names` einzelne Optionen wählen. Ohne Namen werden nur explizite
  Eigenschaften der Eltern- und Plattformscopes aufgelistet, kein vollständiger Katalog aller denkbaren Standardoptionen.
- `project_option_set` und `project_option_remove` verlangen ausdrücklich Konfiguration, Plattform und Optionsname.
  Für gemeinsame Einstellungen `configuration: "Base"`, `platform: ""` angeben; ansonsten einen gelisteten Konfigurationsschlüssel
  und die konkrete Plattform verwenden. `active` ist bei Änderungen gesperrt.
- `value: ""` setzt mit ausdrücklich `merge_mode: "replace"` einen eigenen Leerwert für die neun bekannten Delphi-Listenoptionen:
  `DCC_Define`, `DCC_UnitSearchPath`, `DCC_IncludePath`, `DCC_ResourcePath`, `DCC_ObjPath`, `DCC_Namespace`,
  `DCC_UnitAlias`, `DCC_UsePackage` und `DCC_LibraryPath`. Andere leere Werte werden vor Änderungen abgewiesen, weil der native
  Setter sie sonst löschen kann. `project_option_remove` löscht den Eintrag ausdrücklich über `IOTABuildConfiguration.Remove`,
  sodass wieder die Vererbung greift. `merge_mode` ist `preserve` (Standard), `merge` oder `replace` für Listenoptionen.
- Änderungen markieren das IDE-Projekt als geändert; `project_save` speichert gesondert. Andere geladene Projekte vorher
  mit `project_activate` aktivieren. Der Optionszugriff wechselt Projekte nicht automatisch.

Die Werte stammen unverändert aus den ToolsAPI-Gettern und können unausgewertete Makros enthalten; `local_value` ist kein roher XML-Text. Nicht zuordenbare Standardwerte werden
mit `origin: "default_or_unset"` und ohne erfundene Konfigurationsquelle ausgegeben. Optionsnamen stehen beispielsweise in
`DCCStrs.pas` und `CommonOptionStrs.pas` der jeweiligen ToolsAPI-Installation.

Die SDK-Parent-Kette enthält nicht zwingend alle Plattformvererbungen. `sources` listet deshalb explizite Elternwerte und Plattformkandidaten.
Bei mehreren konkurrierenden Plattformquellen wird `source_resolution: "unknown"` und `origin_configuration: null` zurückgegeben.
Gleiche Werte belegen keine eindeutige Quelle. `merge_mode_applied` nennt, ob das SDK den verlangten Merge-Modus tatsächlich übernommen hat.

IDE-weite Einstellungen sind über `IOTAServices.GetEnvironmentOptions` und `IOTAOptions.GetOptionNames/GetOptionValue/SetOptionValue`
zugänglich. Diese Schnittstelle bietet kein allgemeines Löschen, Zurücksetzen oder Ermitteln einer Vererbungsquelle.
`options_search` und `options_open` ergänzen die Suche nach Optionsnamen und die Navigation im IDE-Dialog. Lesen oder Schreiben IDE-weiter Variantenwerte
benötigt weiterhin einen eigenen Zugriff; die Navigation setzt solche Werte nicht.

Code-Insight-Anfragen werden serialisiert, mit einem Timeout versehen und bei Zeitüberschreitung über `AsyncOperationCanceled` abgebrochen. Ein für Help
Insight gesetzter `SetQueryContext` wird anschließend stets mit `nil, nil` zurückgesetzt.
Jede Anfrage besitzt einen eigenen Callback-Empfänger. Verspätete Antworten bleiben damit ihrer ursprünglichen Anfrage zugeordnet, auch wenn der Provider
IDs erneut verwendet. Bis zum Abschluss hält DAI höchstens 256 Empfänger; bei erreichtem Limit werden weitere Anfragen mit einer Erklärung abgewiesen.
Liefert der Provider lediglich den Marker `HTML`, melden `success` und `found` den Wert `false`; dieser Marker enthält keinen verwendbaren Symboltext.
Beim dauerhaften Package-Abschluss werden neue Code-Insight-Anfragen gesperrt. Ausstehende Empfänger halten ihren eigenen Broker bis zum
tatsächlichen Callback gültig; sie greifen danach nicht auf finalisierte globale Sperren zu. Der Callbackcode wird vor Übergabe an OTA
im Prozess gehalten. Nach Nutzung von Code Insight erfordert ein Package-Austausch bzw. erneutes Laden daher einen IDE-Neustart.
Manuelles Stoppen und Starten des MCP-Servers bleibt möglich. Permanente Abschlüsse entfernen ausschließlich eigene wartende Logcallbacks;
eine fehlgeschlagene Serverbereinigung gibt den noch benötigten Server nicht frei.

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

- `debugger_stacktrace`: Stack des angehaltenen Threads, standardmäßig maximal 50 Frames; optional eine OS-Thread-ID auswählen.
- `debugger_threads_list`: Threads eines ausgewählten oder aller Debuggerprozesse; `debugger_status` listet die Prozesse einschließlich gedebuggter Subprozesse.
- `ide_logs_read`: Compiler-/Debuggerlog mit Anzahl-, Index- und Zeichenlimit.

- `ide_status`
- `open_files_list`
- `projects_list`
- `package_is_installed`
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
- `project_activate`
- `project_options_configurations`
- `project_options_read`
- `options_search`
- `project_option_set`
- `project_option_remove`
- `codex_registration_status`
- `clients_registration_status`
- `form_designer_inspect`
- `form_components_search`
- `form_component_properties`
- `form_palette_list`
- `debugger_status`
- `debugger_cursor_expression`
- `debugger_evaluation_status`
- `breakpoints_list`

### Bearbeiten und IDE-Steuerung

- `ide_window_control`: IDE-Fenster steuern; normaler Schließauftrag bewahrt Speicherrückfragen.

- `file_write`
- `project_create`
- `project_open`
- `project_save`
- `project_remove`
- `package_install`
- `package_uninstall`
- `options_open`: Dialog öffnen und navigieren; mit ausschließlich `request_id` den Zustand lesend abfragen.
- `debugger_expression_ui`: Native Watch-/Auswerten-/Inspektoraktion; mit ausschließlich `request_id` den Zustand lesend abfragen.
- `unit_create`
- `form_unit_create`
- `file_open`
- `file_activate`
- `file_close`
- `project_file_remove`
- `form_show_as_text`
- `form_show_designer`
- `form_components_select`
- `form_component_set_property`
- `form_component_move`
- `form_component_create`
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
- `debugger_evaluate`
- `debugger_modify`

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

Die native Delphi-Brücke muss **neben dem DAI-Package** liegen. `Build.ps1` baut beide. Claude Desktop erhält den Token als Umgebungsvariable, nicht als Befehlszeilenargument.
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
Der Skill nennt DAI ausdrücklich als Werkzeug für Delphi und die Delphi-IDE. Vor Dateiänderungen soll der KI-Client die DAI-Erreichbarkeit
und offene IDE-Puffer prüfen und diese bevorzugt über DAI bearbeiten. Ungespeicherte Benutzeränderungen dürfen dabei nicht ungefragt gespeichert,
verworfen oder überschrieben werden. Diese Kernhinweise liefert DAI auch über `instructions` bei `initialize` und `server/discover` an andere Clients.
Neue Registrierungen erhalten den aktuellen Skill; einen bereits von DAI verwalteten Skill aktualisiert erneutes `Registrieren`.

Ein vorhandener fremder `dai-delphi-ide`-Skill wird nicht überschrieben. Die automatische Skill-Erkennung ist hier für Codex eingerichtet; andere Clients benötigen ihre eigene Skill-Installation.

## Formdesigner und Debugger

`form_designer_inspect(file)` liest Komponenten, Auswahl und skalare veröffentlichte Eigenschaften aus einem geladenen Formularmodul.
`form_show_designer(file)` öffnet das Formular bei Bedarf und zeigt dessen Designer.
Die Komponentenwerkzeuge arbeiten mit diesem geladenen Designer; `file` bezeichnet dessen PAS-, DFM- oder FMX-Datei.

DFM-/FMX-Änderungen erfolgen bevorzugt über die Designerwerkzeuge oder als Text im IDE-Puffer. `form_show_as_text` schaltet normalerweise den
vorhandenen Editor-Tab der PAS-Unit auf Formulartext um; PAS und DFM erscheinen standardmäßig nicht in getrennten Tabs. Nach dem Wechsel die
gewünschte DFM-/FMX-Datei über ihren vollständigen Pfad erneut lesen und den tatsächlichen Inhalt prüfen. Ungespeicherte PAS-Änderungen
nicht ungefragt speichern oder verwerfen, um den Ansichtswechsel zu ermöglichen.

| Werkzeug | Funktion / Parameter |
| --- | --- |
| `form_components_search` | Namen mit `query` durchsuchen, optional `use_regex` und `case_sensitive`; `class_name` und `parent` filtern zusätzlich. `maximum_results`: 100, höchstens 4096. |
| `form_components_select` | Benannte `components` über ToolsAPI selektieren; `add_to_selection` erweitert die Auswahl, `focus` ist standardmäßig `true`. |
| `form_component_properties` | Properties von `component` lesen. Optional `properties` als Namensliste, auch verschachtelte Pfade wie `Font.Size`. |
| `form_component_set_property` | `component`, `property` und skalaren JSON-`value` über den offiziellen Designer-Propertyeditor setzen, einschließlich `Name`. |
| `form_component_move` | Position mit `x`/`y`, Größe mit `width`/`height` und optional Parent ändern. Nicht angegebene Werte bleiben erhalten. |
| `form_component_create` | Registrierte `class_name` über `IOTAFormEditor.CreateComponent` einfügen; optional `name`, Parent, Position/Größe und `select` (Standard `true`). |
| `form_palette_list` | Komponenten und Kategorien der IDE-Palette auslesen; `query`, `category`, `include_unavailable` und `maximum_results` (500, höchstens 4096). |

Beim Einfügen und Parentwechsel wählt `parent` einen expliziten Container. `parent_mode` erlaubt `explicit`, `selected`, `selected_parent` oder `root`.
Einfügen verwendet standardmäßig `selected`: Kann die ausgewählte Komponente keine Controls aufnehmen, wird ihr geeigneter Parent verwendet;
ohne Auswahl wird der Formularcontainer verwendet. `selected_parent` fügt neben der ausgewählten Komponente ein.
Beim Verschieben bleibt der bisherige Parent ohne `parent` oder abweichenden `parent_mode` erhalten.
Die Eignung des Containers wird geprüft; nichtvisuelle Komponenten haben keinen visuellen Parent.
Die Create-Koordinaten sind Ganzzahlen; `-1` überlässt den jeweiligen Wert dem Designer. Beim Move können FMX-Koordinaten Dezimalzahlen sein.

```json
{"file":"MainForm.pas","query":"^Button[0-9]+$","use_regex":true}
```

```json
{"file":"MainForm.pas","component":"Button1","property":"Name","value":"SaveButton"}
```

```json
{"file":"MainForm.pas","class_name":"TButton","name":"SaveButton","parent":"Panel1","x":16,"y":16}
```

Eigenschaftsänderungen und Umbenennungen verwenden die IDE-Propertyeditoren, Auswahl und Erzeugen die öffentliche ToolsAPI.
Bei Umbenennungen und beim Erzeugen wird der tatsächliche Komponentenname zurückgelesen. `source_declaration_verified: false` kennzeichnet,
dass DAI die Pascal-Felddeklaration nicht unabhängig verifiziert; insbesondere wird bei selbst umbenennenden Komponenten keine Synchronisierung aus `ValidateRename` abgeleitet.
Der Parentwechsel kann über die native Komponente erfolgen und meldet die Änderung dem Designer.
Die Werkzeuge speichern weder Formular noch PAS-Unit automatisch. Ergebnisse melden den tatsächlichen Designerzustand;
eine gemeinsame Undo-Transaktion für mehrere Änderungen wird nicht garantiert. Lesen benötigt Leserechte, Auswahl und Änderungen zusätzlich IDE-Bearbeitungsrechte.
Mutationen sind auf Workspace-Dateien beschränkt; schreibgeschützte Referenzformulare bleiben unverändert.
DFM-/FMX-Inhalte können auch den ungespeicherten Zustand liefern (`source: designer_buffer`). Für direkte Formtextänderungen weiterhin den IDE-Textpuffer verwenden.

`debugger_status` liefert Prozess-/Threadzustände; `breakpoints_list` die Quellhaltepunkte.
`debugger_threads_list` liest standardmäßig den aktuellen Debuggerprozess; `process_id` wählt eine gelistete Windows-Prozess-ID,
`all_processes: true` alle von Delphi gedebuggten Prozesse einschließlich gedebuggter Subprozesse. `maximum_threads` begrenzt die gesamte
Antwort auf standardmäßig 200 Threads, höchstens 5000; Gesamtzahlen und `truncated` bleiben sichtbar.
`debugger_stacktrace` verwendet den angehaltenen aktuellen Thread oder optional `process_id` und `thread_id` aus diesen Listen.
`maximum_frames` begrenzt auf standardmäßig 50 Frames (höchstens 500), `maximum_characters` auf standardmäßig 20.000 Zeichen.
Die Frame-Indizes beginnen bei 1. Fehlender beziehungsweise noch nicht zugänglicher Stack wird erklärt; `retryable` erlaubt erneutes Lesen.
Beide Werkzeuge verändern weder die aktuelle Prozess-/Threadauswahl noch die Ausführung. Per-Frame-Modul und -Adresse bleiben `null`,
weil die verwendeten öffentlichen ToolsAPI-Getter diese Angaben nicht liefern.
`breakpoint_set` erwartet `file`, eine einsbasierte `line`, optional `enabled` (Standard `true`), `condition` und `pass_count` (Standard `0`).
`breakpoint_remove(file, line)` entfernt passende Quellhaltepunkte. Änderungen sind auf Workspace-Dateien beschränkt.
`debugger_control(action)` unterstützt `pause`, `continue`, `step_into`, `step_over` und `step_out` mit Prüfung des aktuellen Prozesszustands.
Starten/Beenden erfolgt über `project_run` und `project_stop`. Ein bereits laufender Debugger wird durch `project_run` nicht unbeabsichtigt neu gestartet.
Haltepunkte gehören zur IDE-Bearbeitung, Debugger-Steuerung zur Ausführungsberechtigung; Status und Auflistungen zur Leseberechtigung.

### Ausdrücke auswerten und Werte ändern

`debugger_evaluate` wertet einen Delphi-Ausdruck im angehaltenen Debuggerthread aus, zum Beispiel:

```json
{"expression":"Self.Tag"}
```

`process_id` und `thread_id` wählen OS-IDs aus den Prozess-/Threadlisten. Ohne Angabe wird der aktuelle angehaltene Thread gewählt;
DAI bindet dieses Ziel vor Berechtigungsdialogen. `source_file` und `line` müssen gemeinsam angegeben werden und setzen den lexikalischen
Quellkontext der Auswertung. Damit wird kein Stackframe ausgewählt. Die unterstützte Ausdruckssprache bestimmt der Delphi-Debugger;
komplette Pascal-Anweisungsblöcke lassen sich damit nicht beliebig ausführen.

`side_effects` ist standardmäßig `"none"`. `"properties"` erlaubt Property-Auswertung, `"all"` die vom Debugger unterstützten Seiteneffekte
einschließlich Funktionsaufrufen. Beide verlangen zusätzlich Ausführungsrechte. `format_specifiers` übergibt bis zu 256 druckbare ASCII-Zeichen
an das SDK. `maximum_characters` begrenzt den Ergebnistext auf standardmäßig 4096, höchstens 65536 Zeichen; `truncated` zeigt die Begrenzung.

`debugger_cursor_expression` liest zunächst die sichtbare einzeilige Auswahl, andernfalls einen einfachen Delphi-Zugriff am Cursor,
etwa `Self.Tag`, `Obj.Field`, `Ptr^.Field` oder `Items[Index]`. Automatische Erkennung führt keine Funktionen aus und ignoriert Kommentare,
Strings und komplexe Ausdrücke. Solche Ausdrücke ausdrücklich markieren oder als `expression` angeben. Mehrzeilige und rechteckige Auswahlen
werden abgewiesen. `line`/`column` sind einsbasiert; `expression_start`/`expression_end` sind UTF-8-Bytepositionen ab 0, Ende exklusiv.
`source_sha256` bezeichnet den tatsächlich gelesenen Editorpuffer. Der Reader ist auf 16 MiB, eine Zeile auf 65536 Zeichen begrenzt.

`debugger_evaluate` und `debugger_modify` können diesen Ausdruck mit `{"use_cursor":true}` übernehmen; bei Modify zusätzlich `value` angeben.
`use_cursor` darf nicht mit `expression`, `source_file` oder `line` kombiniert werden. DAI prüft den aktiven Quelleditor und die Leseberechtigung
seines Projekts vor dem Lesen. Designer oder eine veraltete TopView liefern keinen vermeintlichen Cursorausdruck.

Zum Zuweisen eines neuen Werts:

```json
{"expression":"Self.Tag","value":"1"}
```

Diese Argumente gehören zu `debugger_modify`. `value` ist ein Delphi-Wertausdruck; für eine Stringkonstante beispielsweise `"'Hallo'"`.
DAI wertet den Zielausdruck unmittelbar vor Modify ohne Seiteneffekte aus und prüft `can_modify`. Eine erfolgreiche synchrone Vorprüfung
und die Zuweisung laufen im selben IDE-Thread ohne dazwischenliegende Dialoge oder Nachrichtenverarbeitung. Reentranz, Zielwechsel oder
eine verzögerte Vorprüfung verhindern die Zuweisung. Modify verlangt Lese- und Ausführungsrechte und ändert den Debuggee, keine Quelldatei.
Debuggerwerte, Wertzuweisungen und Ergebnisabfragen verwenden ausdrücklich den globalen Berechtigungskontext; das aktive Projekt oder eine
lexikalische Quelldatei beweisen keine Zugehörigkeit eines Debug-Prozesses. Bei `use_cursor` kommt die Leseberechtigung des tatsächlichen
Dateiprojekts hinzu. Alle nativen Ausdrucksaktionen benötigen ebenfalls globale Debuggerrechte zusätzlich zum Zugriff auf den Editor;
eine hinzugefügte Überwachung kann der Debugger sofort oder später automatisch auswerten.

Antworten enthalten `request_id`, `status`, `sdk_result`, `result_text` und bekannte SDK-Ergebnisdaten; unbekannte Werte bleiben `null`.
Bei `deferred` den Zustand mit `debugger_evaluation_status({"request_id":"..."})` abholen. `busy`/`retryable` erlauben einen erneuten Versuch.
`timeout_ms` liegt zwischen 100 und 30000 ms, Standard 5000. Ein Timeout beendet nur das Warten: Eine gestartete Funktion oder Zuweisung
kann weiterlaufen. `sdk_pending` meldet den weiterhin offenen SDK-Vorgang; derselbe Thread bleibt bis zum Callback oder seiner Zerstörung belegt.
Maximal 32 SDK-Vorgänge und 64 abgeschlossene Ergebnisse werden gehalten. Die Statusabfrage verarbeitet einmal anstehende Debuggerereignisse.
Bei Modify beschreibt `modify_attempted`, ob der Zuweisungsaufruf gestartet wurde; `modified` bleibt bei offenem Aufruf `null`.
Späte Callbacks ergänzen das tatsächliche SDK-Ergebnis und `modified`, auch wenn `status` weiterhin `timed_out` oder `cancelled` lautet.
`registration_uncertain` meldet eine ungewisse SDK-Notifierregistrierung; `receiver_retained` zeigt die weiterhin gebundene Receiverkapazität.
Eine verzögerte Vorprüfung startet nach ihrem Callback niemals automatisch Modify; die Änderung muss erneut ausdrücklich angefordert werden.

### Überwachungen und native Debuggerdialoge

`debugger_expression_ui` ruft die öffentlichen Editorbefehle der Delphi-IDE auf:

| `action` | IDE-Befehl |
| --- | --- |
| `add_watch` | Überwachten Ausdruck hinzufügen |
| `watch_at_cursor` | Ausdruck am Cursor anzeigen / in Überwachungen übernehmen |
| `evaluate_modify` | Auswerten/Ändern öffnen |
| `inspect_at_cursor` | Debug-Inspektor am Cursor öffnen |

Der Aufruf benötigt Lese-, IDE-Bearbeitungs- und Ausführungsrechte. Er verändert weder Cursor noch Auswahl und läuft asynchron:
`{"request_id":"..."}` fragt beim selben Werkzeug nur den Status ab. `queued`, `invoking`, `invoked`, `error` und `cancelled` beschreiben den Aufruf;
`action_invoked` bestätigt die Rückkehr des nativen Befehls. Daraus lässt sich weder ein hinzugefügter Watch noch ein geschlossener Dialog ableiten.
Auswerten/Ändern und Inspektor benötigen einen angehaltenen Debuggerthread. Native Dialoge bleiben durch den Benutzer bedienbar.

Die öffentliche ToolsAPI besitzt keine Schnittstelle zum Auflisten, Bearbeiten oder Löschen der IDE-Watchliste.
Diese Funktionen sind daher nicht verfügbar; `debugger_status.expression_capabilities` nennt die unterstützten SDK-Funktionen und diese Grenzen.
Einzelne bekannte Watch-Ausdrücke lassen sich mit `debugger_evaluate` auswerten. Der Debug-Inspektor ist ein nativer Dialog, keine strukturierte
Objektbaum-Abfrage. DAI hält das Package ab dem ersten Debugger-Notifier oder eingereihten Editorbefehl geladen; für einen BPL-Austausch die IDE neu starten.

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

Erwartete Ausgaben mit Delphi 13 / BDS 37.0:

```text
Build\Win32\DAI370.bpl
Build\Win32\DAI.McpBridge.exe
Build\Win32\DAI.dcp
Build\Win64\DAI370.bpl
Build\Win64\DAI.McpBridge.exe
Build\Win64\DAI.dcp
```

EXE, BPL und DCP liegen unabhängig von Debug/Release gemeinsam in `Build\Win32` beziehungsweise `Build\Win64`.
Ein Konfigurationswechsel ersetzt die Ausgabe derselben Plattform. DCUs bleiben unter `Build\<Plattform>-<Konfiguration>-Dcu` getrennt;
die Bridge verwendet `Build\<Plattform>-<Konfiguration>-BridgeDcu`.
Auch Testausgaben verwenden flache Namen wie `Build\Tests-CodeInsight-Win64` und `Build\Tests-CodeInsight-Win64-Dcu`.
Alle Ausgabeverzeichnisse liegen direkt unter `Build`; Testdaten mit eigenen Unterverzeichnissen liegen im temporären Verzeichnis.

Win32 und Win64 sind im DPROJ aktiviert. Mit `-Platform Win32` oder `-Platform Win64` kann auch nur eine Architektur gebaut werden.
`-Platform IDE` baut nur die Architekturen der installierten IDEs. Dazu werden die Registrywerte `App` und `App x64` sowie die Existenz der jeweiligen
`bds.exe` geprüft. Ein vorhandener Win64-Compiler allein bedeutet keine installierte 64-Bit-IDE.
`DllSuffix=$(Auto)` im DPROJ und `{$LIBSUFFIX AUTO}` im DPK verwenden automatisch das Package-Versionssuffix des Compilers.
Die Ausgabeverzeichnisse bleiben gleich; BPLs verschiedener Delphi-Versionen erhalten unterschiedliche Namen. DCP-/DCU-Dateien bleiben ohne Versionssuffix.
DCP, Importbibliotheken und Bridge derselben Plattform werden jeweils durch den letzten Build ersetzt, auch bei einem Wechsel der Delphi-Version.
`Build.ps1` prüft die beim aktuellen Build neu geschriebene versionierte BPL sowie die Bridge auf PE-Signatur, Zielarchitektur und DLL-/EXE-Typ.
Eine vorhandene alte `DAI.bpl` oder eine unveränderte BPL eines früheren Builds zählt dabei nicht als erfolgreiches Build-Ergebnis.

Kann der Compiler die aktuelle BPL wegen einer Dateisperre nicht erstellen (`F2039`), versucht `Build.ps1`, sie nach
`DAI<Version>.bpl.deleted` umzubenennen, und wiederholt den Package-Build einmal. Eine vorhandene Sicherung wird gelöscht;
ist auch sie gesperrt, wird ein nummerierter Name wie `DAI370.1.bpl.deleted` verwendet. Andere Compilerfehler lösen diesen
Versuch nicht aus. Die laufende IDE verwendet weiterhin das bereits geladene Package; zum Laden des neuen Builds die IDE neu starten.
Scheitert der wiederholte Build, bleibt die bisherige BPL unter dem gemeldeten Sicherungsnamen erhalten.

Mit `-DelphiVersion 11`, `12` oder `13` wird die passende Installation anhand ihrer BDS-Registryversion gesucht:

| Delphi | BDS-Registryversion | AUTO-Suffix / Package |
| --- | --- | --- |
| 11 Alexandria | `22.0` | `280` / `DAI280.bpl` |
| 12 Athens | `23.0` | `290` / `DAI290.bpl` |
| 13 Florence | `37.0` | `370` / `DAI370.bpl` |

Die Suche berücksichtigt die Installationswerte unter HKCU und HKLM in beiden Registryansichten. Mit `-DelphiVersion` wird ein geerbtes `%BDS%`
ignoriert, damit beispielsweise Delphi 11 nicht versehentlich mit der Delphi-13-Toolchain gebaut wird. Ein ausdrücklich angegebenes `-BdsRoot`
wählt das Installationsverzeichnis; zusammen mit `-DelphiVersion` muss es zu dieser Version passen.
`-SkipMissing` überspringt eine nicht installierte Version mit einer Meldung und ohne Fehler. Build- oder Registrierungsfehler bleiben Fehler.

## Installation in der 32- und 64-Bit-IDE

Das Design-Time-Package muss zur Architektur der **IDE** passen. Die Zielplattform eines geöffneten Anwendungsprojekts ist dafür nicht maßgeblich.

| IDE | Programm relativ zu `%BDS%` | Package relativ zum DAI-Projekt | Package-Schlüssel unter dem BDS-Benutzerprofil |
| --- | --- | --- | --- |
| 32 Bit | `bin\bds.exe` | `Build\Win32\DAI370.bpl` | `Known Packages` |
| 64 Bit | `bin64\bds.exe` | `Build\Win64\DAI370.bpl` | `Known Packages x64` |

Bei der vorliegenden Installation lauten die Schlüssel:

```text
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages x64
```

Die Tabelle zeigt Delphi 13; andere Compiler erzeugen ihr eigenes AUTO-Suffix.
In der jeweiligen IDE über `Component → Install Packages → Add` das passende BPL auswählen. Eine zuvor installierte unsuffigierte `DAI.bpl` dabei ersetzen,
damit DAI nicht doppelt geladen wird. Die native Bridge aus demselben Buildverzeichnis neben dem BPL belassen.
Die Package-Zuordnung erfolgt über die verschiedenen Schlüsselnamen; ein Wechsel der Registry-View allein ersetzt sie nicht.

Alternativ kann `Build.ps1` das Package nach einem erfolgreichen Build für den aktuellen Windowsbenutzer registrieren:

```powershell
.\Build.ps1 -Configuration Release -Platform IDE -DelphiVersion 13 -Register
```

`-Register` ist optional; ohne diesen Schalter baut das Skript ausschließlich. Die Registrierung schreibt den vollständigen Pfad der beim aktuellen
Build neu erzeugten und geprüften BPL als Zeichenfolgenwert mit einer DAI-Beschreibung in den passenden `Known Packages`-Schlüssel unter
`HKEY_CURRENT_USER\Software\Embarcadero\BDS\<BDS-Version>`. Sie erfolgt erst, nachdem alle angeforderten Package- und Bridge-Builds erfolgreich waren.
Alte Einträge mit demselben BPL-Namen oder dem früheren `DAI.bpl` aus dem gemeinsamen Ausgabeordner sowie den bisherigen
Debug-/Release-Ausgaben dieses Projekts und derselben Architektur werden ersetzt;
zugehörige deaktivierte DAI-Einträge werden entfernt.
Andere Packages bleiben erhalten. Es werden keine HKLM-Schlüssel geschrieben und keine Administratorrechte benötigt.
Die betreffende IDE vor Build und Registrierung schließen und anschließend wieder öffnen, damit sie das Package lädt und keine alten Registrierungen
beim Beenden zurückschreibt. Eine fehlende 64-Bit-IDE wird bei `-Platform IDE` übersprungen.

Für Delphi 11 bis 13 gemeinsam:

```bat
BUILD+REGISTER.cmd
```

Die CMD-Datei ruft für jede Version `Build.ps1 -Configuration Release -Platform IDE -DelphiVersion <Version> -Register -SkipMissing` auf.
Nicht installierte Versionen werden übersprungen. Nach einem Fehler werden die übrigen Versionen trotzdem versucht; der abschließende Exitcode
ist `1`, wenn mindestens ein Build oder eine Registrierung fehlschlug, sonst `0`. Standardmäßig bleibt das Fenster mit `pause` geöffnet.
Für unbeaufsichtigte Aufrufe entfällt die Pause:

```bat
BUILD+REGISTER.cmd --no-pause
```

Beide vollständigen Package-Builds wurden mit Delphi 13 / BDS 37.0 geprüft. Der Nutzer bestätigte außerdem Build und Package-Installation unter Delphi 11.
Jedes Package muss mit der Toolchain und den ToolsAPI-Units seiner IDE-Version gebaut werden. Der Delphi-12-Build und die vollständigen Funktionstests
unter Delphi 11/12 stehen noch aus. Die globale Instanzsperre selbst ist versionsunabhängig.

Referenzen: [64-Bit-IDE](https://docwiki.embarcadero.com/RADStudio/Florence/en/64-bit_IDE),
[Package-Installation](https://docwiki.embarcadero.com/RADStudio/Florence/en/InstallIDEPackage),
[Compiler- und Package-Versionen](https://docwiki.embarcadero.com/RADStudio/Florence/en/Compiler_Versions_Table).

## Verbindungstest

```powershell
.\Test-MCP.ps1 -Port 7331 -Token '<Bearer-Token>'
.\Test-MCP.ps1 -Mode Modern -Port 7331 -Token '<Bearer-Token>'
```

Im Standardmodus führt das Skript `initialize`, `notifications/initialized`, `tools/list` und `tools/call → ide_status` aus.
Mit `-Mode Modern` verwendet es `server/discover` und die erforderlichen MCP-Metadaten und HTTP-Header. In der Delphi-IDE können Berechtigungsdialoge erscheinen.

Die isolierten Tests verwenden eigene Fixtures und IDE-/Settings-Stubs:

```powershell
.\Scripts\Test.BuildRegistration.ps1
.\Scripts\Test.BuildOutput.ps1
.\Scripts\Test-ClientRegistration.ps1 -Platform Win32
.\Scripts\Test-ClientRegistration.ps1 -Platform Win64
.\Scripts\Test.Protocol.ps1 -Platform Win32
.\Scripts\Test.Protocol.ps1 -Platform Win64
.\Scripts\Test.Sessions.ps1 -Platform Win32
.\Scripts\Test.Sessions.ps1 -Platform Win64
.\Scripts\Test.Instance.ps1 -Platform Both
.\Scripts\Test.ServerLifecycle.ps1 -Platform Both -Linkage Both -HostPeers
.\Scripts\Test.SourceView.ps1 -Platform Both
.\Scripts\Test.SourceSearch.ps1 -Platform Both
.\Scripts\Test.SearchService.ps1 -Platform Both
.\Scripts\Test.DirectorySearch.ps1 -Platform Both
.\Scripts\Test.SearchDispatch.ps1 -Platform Both
.\Scripts\Test.SourcePaths.ps1 -Platform Both -StrictSeparators
.\Scripts\Test.EditorWrite.ps1 -Platform Both
.\Scripts\Test.ProjectSummary.ps1 -Platform Both
.\Scripts\Test.PackageSummary.ps1 -Platform Both
.\Scripts\Test.Packages.ps1 -Platform Both
.\Scripts\Test.PackageDispatch.ps1 -Platform Both
.\Scripts\Test.Windows.ps1 -Platform Both
.\Scripts\Test.ReadOnlyPolicy.ps1 -Platform Both
.\Scripts\Test.CodeInsight.ps1 -Platform Both
.\Scripts\Test.Designer.ps1 -Platform Both
.\Scripts\Test.Build.ps1 -Platform Both
.\Scripts\Test.Dialogs.ps1 -Platform Both
.\Scripts\Test.Log.ps1 -Platform Both
.\Scripts\Test.Runtime.ps1 -Platform Both
.\Scripts\Test.Options.ps1 -Platform Both
.\Scripts\Test.Toolbar.ps1 -Platform Both
.\Scripts\Test.Toolbar.ps1 -Platform Both -Focus Popup
.\Scripts\Test.IDEControl.ps1 -Platform Both
.\Scripts\Test.Messages.ps1 -Platform Both
.\Scripts\Test.Stack.ps1 -Platform Both
.\Scripts\Test.Threads.ps1 -Platform Both
.\Scripts\Test.CursorExpression.ps1 -Platform Both
.\Scripts\Test.Evaluation.ps1 -Platform Both
.\Scripts\Test.ExpressionUI.ps1 -Platform Both
.\Scripts\Test.ExpressionDispatch.ps1 -Platform Both
.\Scripts\Test.ToolDispatch.ps1 -Platform Both
python .\Scripts\test_bridge.py
```

Die Instanztests verwenden eigene zufällige Objektnamen und prüfen auch getrennte Win32-/Win64-Prozesse sowie Prozessabbruch.
Dabei werden keine tatsächlichen Client-Konfigurationen verändert und keine Designer-/Debuggeraktionen in der laufenden IDE ausgelöst.

## Statische Prüfung

```powershell
python .\Scripts\verify.py
```

Geprüft werden unter anderem Dateinamen, Unit-Namen, DPK-/DPROJ-Referenzen, XML, erforderliche MCP-Werkzeuge, bekannte ungültige Delphi-Typen, fehlende DAI-Typdeklarationen, Altbezeichnungen, unqualifizierte `TMonitor`-Aufrufe, Tabulatoren, gemischte Zeilenenden und die maximale Zeilenlänge von 180 Zeichen.

Die Standardpaket-Abhängigkeit `xmlrtl` stellt den XML-Parser für die DPROJ-Formatversion in der Projektübersicht bereit.

## Hinweis zur Binärprüfung

Der überarbeitete Stand wurde mit der lokal installierten Delphi-13-Toolchain kompiliert. Die IDE-Integration von Designer, Debugger und Dialogen
muss zusätzlich im laufenden RAD Studio geprüft werden; Compiler- und isolierte Protokolltests ersetzen diesen Praxistest nicht.
