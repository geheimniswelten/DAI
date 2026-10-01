# DAI 1.2.3 – Prüfbericht vom 1. Oktober 2026

## Aktueller Stand

- 52 MCP-Werkzeuge; neue native Quellsuche in Projekt, Projektgruppe und ReadOnly-Referenzen mit Editor-/Designerpuffervorrang.
- Delphi-Source, ToolsAPI, Samples und beide GetIt-Kataloge sind lesbar. Ihre BDS-/GetIt-Aliase werden versionsbezogen aufgelöst.
- Referenzschreibschutz gilt auch für offene Dateien und überlappende Projektverzeichnisse. Speichern, Projektanlage, Entfernen und IDE-Builds
  prüfen Begleitdateien, Projektabhängigkeiten, Ausgabeziele sowie Reparse-Schreibpfade vor der Operation.
- Suchplan und betroffene Projekte werden vor Freigaben bestimmt; die Suche prüft neu hinzugekommene Projektbesitzer erneut, bevor Inhalte gelesen werden.
- Literal- und Dateimustersuche mit Mengen-, Größen- und Zeitgrenzen; eigener begrenzter Globmatcher für `*` und `?`.
- project_create kann über die OTA mit save=false ein ungespeichertes VCL-Projekt samt Hauptformular anlegen, ohne DAI-Speicheraufruf.
- ide_windows_list und debugger_windows_list lesen WinAPI-Fenster und VCL-Metadaten. Debuggee-Zuordnung über die Windows-PID der ToolsAPI.
- Korrektur des Editor-CRLF-Readbacks; Hash und Zeilenenden entsprechen dem tatsächlich zurückgelesenen Puffer.
- Generierter und installierter delphi-ide-Skill aktualisiert; keine neue GetIt-Laufzeitabhängigkeit.

## Aktuelle Verifikation

Release-Builds von DAI.bpl und DAI.McpBridge.exe für Win32 und Win64 mit Delphi 37.0 erfolgreich. Der Build prüft die vier PE-Ausgaben
auf Architektur sowie DLL-/EXE-Typ. Die bekannten W1002-Hinweise zu Windows-Plattformdefinitionen und H2077 zum YAML-Ergebniswert bleiben; keine Buildfehler.

| Native Testreihe | Checks je Architektur |
| --- | ---: |
| Test.SourceSearch: Literal-/Globsuche, Unicode, Pufferpriorität, Grenzen und Junctions | 107 |
| Test.SearchService: echter OTA-Suchadapter mit isolierten IDE-Diensten, Scopes, Besitzern und Suchplan | 123 |
| Test.SourcePaths: echte Settings, Aliase, Schrägstriche und Laufwerkswurzeln | 37 |
| Test.EditorWrite: echter Datei-/Editor-Dienst mit isolierten Editor-/Action-Doubles | 40 |
| Test.Windows: native Fenster, Cross-bitness, blockierte Fenster, Metadaten und Privatsphäre | 84 |
| Test.ReadOnlyPolicy: echte Datei-/Projekt-/Build-Dienste mit isolierten OTA-Diensten, Reparse-Schreibpfade | 51 |
| Test-ClientRegistration: Konfigurationsparser, Registrierung und Dateisicherung | 98 |
| Test.Protocol: HTTP-/MCP-Protokoll und Sessions | 67 |
| **Summe, jeweils Win32 und Win64** | **607** |

Alle 1.214 Checks erfolgreich. Isolierte OTA-Doubles prüfen die Dienstverträge; sie ersetzen keinen Live-Test im vollständigen IDE-Prozess.
Die unveränderten Instanz- und Sessiontests wurden im vorherigen Stand mit je 49 bzw. 69 Checks erfolgreich ausgeführt und diesmal nicht wiederholt.

Der Skill wurde gegen einen nativen Export der aktuellen Toolregistry geprüft: gültige YAML-Metadaten, 41 genannte Werkzeuge,
zwei JSON-Beispiele und elf dokumentierte Argumentverträge. Die installierte verwaltete Datei stimmt bytegenau mit dem frisch kompilierten
Delphi-Generator überein; vorheriger Skill als Backup erhalten.

Statische Prüfung: 37 Pascal-Units und 52 MCP-Werkzeuge, DPK-/DPROJ-Verweise, Schemas, Versionen, BOM/CRLF, Layout und Standardpaketgrenze.
git diff --check sauber; Manifest der ausgelieferten Quellen aktualisiert.

## Grenzen und Live-Stand

Die laufende 32-Bit-IDE verwendet weiterhin das zuvor geladene Win32-Debug-Package. Die neuen Release-Binaries wurden nicht geladen,
damit das offene ungespeicherte Testprojekt erhalten bleibt. Neue Werkzeuge, project_create(save=false), Hauptformular-/CreateForm-Injektion
und neue Fensterinspektion brauchen noch einen Live-Test nach Laden des neuen Packages. Win64 wurde kompiliert und nativ isoliert geprüft,
aber nicht im laufenden Win64-IDE-Prozess. Echte Clientkonfigurationen und Package-Registrierungsschlüssel wurden in diesem Schritt nicht verändert.

Die Quellsuche hat kooperative Grenzen. Synchronisierte OTA-Aufrufe können auf den IDE-Hauptthread warten; die Suche ist keine harte Zeit- oder
Dateisystem-Sandbox. Best-effort-Fensterinspektion kann fehlende Controltexte oder eine nicht verfügbare Debuggee-PID melden, wenn die IDE blockiert ist.
DAI-Berechtigungsdialoge und Eingabefeldtexte sind ausgeschlossen. VCL-Handles werden nicht erzeugt; der Debuggee wird nicht fortgesetzt.

Die Schreibschutzregeln kontrollieren DAI-Datei-/Projektoperationen. Ausdrücklich erlaubte Compilerargumente und benutzerdefinierte Buildskripte
können eigene Dateioperationen durchführen und werden ohne Dateisystem-Sandbox ausgeführt.

Junction-Schreibpfade wurden nativ geprüft. Der zusätzliche Test mit einem einzelnen Datei-Symlink blieb ungeprüft:
Die automatische Freigabeprüfung blockierte die Shellprobe mit „blocked by policy“ ohne nähere Begründung; Windows verweigerte danach die
Symlinkanlage mangels Administratorrechten. Der zusätzliche Test ist entfernt, ohne Erhöhung der Berechtigungen.

Der frühere Win32-Live-Test bestätigte Build, Debuggerstart, Quellhaltepunkt, Step over, Exception, Pause/Continue und Stop am ungespeicherten
VCL-Projekt. Bei Exceptions bleibt strukturierter Quellort, Exceptiontext und Aufrufstack eingeschränkt; siehe den historischen Test unten.

## Historischer Prüfstand 1.2.2 und Win32-Live-Test

Die folgenden Zahlen und Beobachtungen beziehen sich auf den früheren Stand 1.2.2.

### Änderungen seit 1.2.1

- Win32 und Win64 im DPROJ aktiviert, getrennte Build-Ausgaben und PE-Prüfung für Package/Bridge in beiden Architekturen.
- Eigene Delphi-Instanzsperre: ein aktiver DAI-Server je Windowsbenutzer, unabhängig von Port, IDE-Architektur und Delphi-Version.
- Die erste erfolgreiche Serverinstanz übernimmt. Nach sauberem Stop oder Prozessende kann eine andere IDE manuell übernehmen.
- Start-/Stop-Schaltflächen in den DAI-Optionen; Autostart gilt nur beim Laden des Packages. Übernehmen der Optionen bewahrt den manuellen Laufzustand.
- Portänderungen halten die Sperre durch den internen Neustart. Fehlgeschlagene Starts geben sie nach erfolgreicher Bereinigung frei;
  unvollständige Listenerbereinigung hält die Sperre und verlangt einen IDE-Neustart.
- ide_status nennt aktive IDE, Architektur, PID, EXE, BPL und den zur Architektur passenden Package-Registrierungsschlüssel.
- Sessions, Clientregistrierungen, Skill-Metadaten, Editor-/Projektzugriffe, Designerinspektion und Debuggerwerkzeuge bleiben enthalten.

### Verifikation

- Vollständiger Win32- und Win64-Release-Build von DAI.bpl und DAI.McpBridge.exe mit Delphi 37.0 erfolgreich.
- PE-Headerprüfung bestätigt die richtige Architektur und DLL-/EXE-Kennung aller vier Ausgaben.
- Je 49 native Instanzchecks unter Win32/Win64, einschließlich acht Threads mit 8.000 Acquire-Aufrufen,
  getrennten Prozessen, Übernahme zwischen den Architekturen und Freigabe nach Prozessabbruch.
- Je 67 native HTTP-/Protokollchecks unter Win32/Win64: Protokoll, Sessionablauf/DELETE, Auth/Origin/Version und Kapazität;
  zusätzlich Besitzerwechsel, anderer Port, Autostart/manueller Laufzustand, Portänderung und Freigabe nach Bindfehler.
- Beide kompilierten Bridges erfolgreich gegen einen isolierten HTTP-Server geprüft: UTF-8, Session-/Versionsheader,
  Notifications, EOF-DELETE, HTTP-Fehler und Endpoint-/Tokenvalidierung.
- PE-Importprüfung: DAI.bpl verwendet ausschließlich mit Delphi gelieferte Standard-BPLs und Windows-DLLs;
  die Bridges verwenden Windows-DLLs ohne BPL-Import. Keine zusätzliche GetIt-Laufzeitabhängigkeit.
- Statische Prüfung: 34 Pascal-Units, 49 MCP-Werkzeuge, Schemas, BOM/CRLF, Zeilenlayout, beide Plattformen und Standardpaketgrenze.
- Unabhängiger abschließender Code-Review ohne wesentliche verbleibende Befunde; git diff --check sauber und Manifest aktualisiert.

Die unveränderte Sessionverwaltung hatte in 1.2.1 je 69 erfolgreiche native Checks unter Win32/Win64; die unveränderte Registrierungslogik zuvor je 98.
Diese beiden separaten Tests wurden in diesem Schritt nicht erneut ausgeführt. Die aktuellen HTTP-Tests prüfen weiterhin den eingebundenen Sessionablauf.

### Installation und praktische Grenzen

32-Bit-IDE: bin\bds.exe, Win32-BPL, HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages.
64-Bit-IDE: bin64\bds.exe, Win64-BPL, HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages x64.
Die Bridge muss jeweils neben dem BPL liegen. Beide IDE-Architekturen teilen im selben BDS-Benutzerprofil die DAI-Einstellungen.
Andere Delphi-Versionen brauchen ein mit ihrer Toolchain gebautes Package; die Instanzsperre bleibt dabei gleich, API-Kompatibilität ist hier nicht geprüft.

Die Release-BPLs wurden beim Build nicht in eine laufende IDE geladen. Der nachfolgende Live-Test verwendete das bereits geladene Win32-Debug-Package
(siehe unten). Die sichtbare DAI-Optionsseite, DFM-Bearbeitung und die Win64-IDE brauchen weiterhin einen IDE-Praxistest.
Echte Clientkonfigurationen, Package-Registrierungsschlüssel und GetIt-Installationen wurden durch diese Prüfungen nicht verändert.
Die bekannten Compilerhinweise W1002 zum Windows-Flag und H2077 zum initialen YAML-Ergebniswert bleiben; keine Buildfehler.

Ressourcen- und Prompt-Endpunkte sowie eine gemeinsame Toolregistry sind dokumentierte Ideen und noch nicht implementiert.

### Nachfolgender Live-Test in der 32-Bit-IDE

- Laufende Delphi-13-IDE über DAI erkannt: Win32, bin\bds.exe, geladenes Build\Win32\Debug\Bpl\DAI.bpl.
- Ungespeicherte VCL-Anwendung Project1 mit Form1 über den nativen Delphi-Assistenten angelegt; offene Dateien und Designerinspektion über DAI gelesen.
- Editorpuffer mit save=false geändert und erneut gelesen. Vollständiger IDE-Build erfolgreich: 0 Fehler, 0 Warnungen und 0 Hinweise.
- Debuggerstart erfolgreich; Quellhaltepunkt an Unit1.pas:45 gültig und tatsächlich erreicht. Step over führte zu Zeile 46.
- Absichtliche Exception an Zeile 47 beobachtet. DAI meldete exception; nach Anhalten im IDE-Exceptiondialog über DAI fortgesetzt.
- Normaler VCL-Exceptiondialog bestätigt; pause/continue erfolgreich geprüft und Testprozess über project_stop beendet.
- Nach Build und nach Ende existierten Project1.dproj, Project1.dpr, Unit1.pas und Unit1.dfm nicht auf dem Datenträger.
  Das Testprojekt bleibt mit seinem Haltepunkt ungespeichert in der IDE geöffnet; has_current_process=false.

Damals gefunden: file_write meldete EInvalidOperation, obwohl der neue Code im Editorpuffer stand, weil Delphi ein zusätzliches CRLF ergänzte.
Dieser Fehler ist in 1.2.3 korrigiert und durch je 40 native Editor-Dateidienstprüfungen belegt; die laufende IDE verwendet noch den älteren Stand.
Bei der Exception lieferte debugger_status außerdem current_file leer/current_line=0; die IDE zeigte die Quellzeile über den Usercode-Stackframe.
Exceptiontext und Aufrufstack wurden in diesem Test über die native Oberfläche gelesen, nicht als strukturierte MCP-Daten.

Die Anlage testete den nativen VCL-Assistenten. Die neue Implementierung von project_create(save=false) mit VCL-Hauptformular ist in 1.2.3 enthalten.
Ihre tatsächliche Einbindung in der laufenden IDE ist durch diesen früheren Test noch nicht bestätigt.
