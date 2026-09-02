# Änderungsprotokoll

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
