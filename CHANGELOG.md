# Änderungsprotokoll

## 1.1.13

- alle Synchronisationszugriffe von `TMonitor.Enter/Exit` auf `System.TMonitor.Enter/Exit` umgestellt
- Namenskollision mit `Vcl.Forms.TMonitor`, das die Bildschirmdarstellung beschreibt, zuverlässig ausgeschlossen
- statische Prüfung ergänzt, die unqualifizierte `TMonitor`-Aufrufe in Pascal-Sourcen und im Package zurückweist

## 1.1.12

- Standardport `7331` direkt neben dem Portfeld im Options-Frame ausgewiesen
- Bearer-Token-Eingabefeld von 500 auf 330 Pixel verkürzt und daneben die Schaltfläche `Token erzeugen` ergänzt
- vorhandene GUID-basierte Token-Erzeugung aus `TDAISettings` für den Options-Frame öffentlich bereitgestellt
- Hinweis ergänzt, dass eine vorhandene Codex-Registrierung nach einem Tokenwechsel über `Registrieren` aktualisiert werden muss

## 1.1.11

- bei einem belegten MCP-Port wird der Listener-Besitzer über `GetExtendedTcpTable` aus `iphlpapi.dll` ermittelt
- die Fehlermeldung nennt die PID und, soweit über `QueryFullProcessImageNameW` lesbar, den Prozessnamen
- gehört der Listener zur aktuellen `bds.exe`, weist DAI ausdrücklich darauf hin, dass die TCP-Tabelle kein einzelnes BPL oder IDE-Plugin zuordnen kann
- die Listener-Ermittlung ist rein diagnostisch und darf einen fehlgeschlagenen Serverstart nicht selbst mit einer weiteren Exception überlagern

## 1.1.10

- eigene `TScrollBox` aus dem DAI-Options-Frame entfernt; der von der Delphi-IDE bereitgestellte scrollbare Options-Host übernimmt das Scrollen
- alle dynamisch erzeugten Steuerelemente liegen nun direkt auf `TDAIOptionsFrame`
- der Frame verwendet am Ende von `BuildControls` `Align := alTop` und `Height := LTop`, damit der IDE-Dialog seine Inhaltsgröße korrekt bestimmen kann
- doppelte vertikale Scrollbar beseitigt und Mausrad-Scrollen über das Standardverhalten des IDE-Einstellungsdialogs ermöglicht

## 1.1.9

- Zugriff auf den bereits von Delphi 13 verwendeten Code-Insight-/LSP-Provider über die öffentliche OpenToolsAPI ergänzt
- fünf neue read-only MCP-Werkzeuge: `code_insight_status`, `code_definition`, `code_hover`, `file_diagnostics` und `project_context`
- `code_definition` verwendet `IOTAAsyncCodeInsightManager290.AsyncGotoDefinitionEx`, sofern verfügbar, sonst die kompatible Basisfunktion
- `code_hover` setzt den zur Datei gehörenden `IOTAEditView` als Query-Kontext und stellt den ursprünglichen IDE-Zustand anschließend wieder her
- asynchrone Code-Insight-Anfragen werden serialisiert, zeitlich begrenzt und bei Timeout über `AsyncOperationCanceled` abgebrochen
- `file_diagnostics` liest die von Error Insight bereitgestellten Fehler, Warnungen und Hinweise über `IOTAModuleErrors`
- `project_context` liefert aktive Plattform, Konfiguration, Framework, vollständige Projektdateiliste und ausgewertete DCC-Suchpfade/-Defines
- Analyse der verwendeten Delphi-13-OpenToolsAPI in `OPENTOOLSAPI_CODE_INSIGHT.md` dokumentiert

## 1.1.8

- ein belegter MCP-Port löst während der Package-Registrierung keine ungefangene `EIdCouldNotBindSocket` mehr aus
- fehlgeschlagene Bind- und Startvorgänge lassen das Package geladen und werden als Serverstatus sowie im IDE-Meldungsfenster ausgegeben
- automatischer Portwechsel bleibt bewusst ausgeschlossen, damit die Codex-Konfiguration nicht unbemerkt auf eine andere IDE zeigt
- DAI-Optionsseite zeigt den aktuellen Serverstatus und meldet Startfehler beim Übernehmen der Einstellungen
- Logging ist gegen Fehler von `IOTAMessageServices` abgesichert und fällt auf `OutputDebugString` zurück

## 1.1.7

- minimale DFM-Ressource für `TDAIOptionsFrame` ergänzt; `TCustomFrame.Create` kann den Options-Frame damit über `INTAAddInOptions` laden
- `{$R *.dfm}` in `h5u.DAI.Options.Frame.pas` ergänzt
- DPROJ-Metadaten des Frames um `Form`, `FormType=dfm` und `DesignClass=TFrame` ergänzt
- statische Prüfung erkennt künftig von `TFrame` abgeleitete Klassen ohne passende DFM-Ressource oder ohne DPROJ-Frame-Metadaten

## 1.1.6

- vorhandenes einheitliches CRLF beziehungsweise LF wird beim Schreiben beibehalten; eine pauschale Konvertierung des Projektbestands findet nicht statt
- gemischte Zeilenenden und alleinstehendes CR werden auf das vorhandene Format normalisiert; ohne eindeutige Vorgabe dient CRLF als Windows-/Delphi-Fallback
- tatsächliche Tabulatorzeichen werden in Pascal-Sourcen (`.pas`, `.dpr`, `.dpk`, `.inc`) beim Schreiben durch zwei Leerzeichen ersetzt
- die statische Prüfung weist gemischte Zeilenenden, alleinstehendes CR und Tabulatoren in den ausgelieferten Pascal-Sourcen zurück

## 1.1.5

- PAS-Dateien des DAI-Pakets werden als UTF-8 mit BOM ausgeliefert; bestehende Zeilenenden werden dabei nicht verändert
- neue, direkt auf dem Datenträger erzeugte `.pas`-Dateien verwenden standardmäßig UTF-8 mit BOM
- vorhandene geschlossene `.pas`-Dateien behalten ANSI beziehungsweise UTF-8 mit BOM; ANSI wird nur bei nicht darstellbaren Zeichen auf UTF-8 mit BOM angehoben
- bestehende Zeilenenden werden bei vollständigen Dateiänderungen beibehalten, statt projektweit auf LF oder CRLF normalisiert zu werden
- DFM-Dateien werden niemals nach der PAS-Regel direkt gespeichert, sondern ausschließlich über den IDE-Textpuffer; Delphi entscheidet beim Speichern selbst zwischen ANSI und UTF-8
- `file_read` und `file_write` melden die erkannte beziehungsweise verwendete Codierung und Art des Zeilenumbruchs

## 1.1.4

- die vom Benutzer in Delphi 13 bestätigten Compilerfixes übernommen: `Vcl.Graphics` für `fsBold`, gültige `TStreamReader.Create`-Überladung und direkter `nil`-Vergleich für `TDAIOTA.MainProjectGroup`
- unbenutzten privaten Setter `SetCustomReadDirectories` entfernt
- unbenutzte Variablen in `TDAIIDENotifier.FileNotification` entfernt
- drei vom Compiler beanstandete, vor der tatsächlichen Rückgabe überschriebene `Result`-Initialisierungen entfernt
- veraltete statische `TCharacter`-Aufrufe durch `TCharHelper`-Aufrufe ersetzt
- Zeilenlänge und Deklarationsformatierung weiterhin auf maximal 180 Zeichen geprüft

## 1.1.3

- Pascal-Quellcode auf eine maximale Zeilenlänge von 180 Zeichen neu formatiert
- Property-Deklarationen und Methodensignaturen bleiben bis einschließlich 180 Zeichen in einer Zeile
- längere Funktionssignaturen werden möglichst spät, bevorzugt vor dem Rückgabetyp oder am letzten passenden Parametertrenner, umgebrochen
- fehlende `initialization`-Abschnitte vor `finalization` in `h5u.DAI.UI`, `h5u.DAI.Options.Page` und `h5u.DAI.Runtime` ergänzt
- statische Prüfung erkennt künftig unnötig früh umgebrochene Deklarationen und `finalization` ohne vorheriges `initialization`

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
