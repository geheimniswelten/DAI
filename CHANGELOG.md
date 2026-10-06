# Änderungsprotokoll

## 1.2.21

- Die DAI-Werkzeugleiste stellt Status- und Layoutaktualisierungen während geöffneter IDE-Menüs zurück. Nach dem Schließen übernimmt der nächste Refresh den aktuellen Zustand.
- Das DAI-Dropdown verwendet feste Tastenkürzel. Der 500-ms-Statustimer entfernt dadurch keine von der VCL ergänzten Kürzel und baut das angezeigte Menü nicht wiederholt neu auf.
- Isolierte VCL-Tests prüfen echte native Popups über mehrere Timerzyklen sowie nachgeholte Statusänderungen ohne Eingriffe in die laufende Delphi-IDE.
- Der Toolbar-Test-Runner liest Prozessausgaben asynchron und meldet bei Zeitüberschreitungen die erreichten Prüfabschnitte. Die Gesamtsuite ist auf 300 Sekunden je Architektur begrenzt, gezielte Tests auf 120 Sekunden.

## 1.2.20

- Build.ps1 benennt eine durch Dateisperren blockierte Ausgabe-BPL bei Compilerfehler F2039 nach *.bpl.deleted um und wiederholt den Package-Build einmal. Vorhandene Sicherungen werden ersetzt; ebenfalls gesperrte Sicherungen erhalten einen nummerierten Ausweichnamen.
- form_components_search und form_components_select suchen beziehungsweise selektieren geladene Designerkomponenten; Namenssuche unterstützt optional RegEx, Klasse und Parent sind zusätzliche Filter.
- form_component_properties liest einzelne und verschachtelte Properties; form_component_set_property setzt Werte einschließlich Name über die offiziellen Designer-Propertyeditoren.
- form_component_move ändert Position und Größe sowie optional den visuellen Parent. Native Parentwechsel werden dem Designer als Änderung gemeldet.
- form_palette_list liest Komponenten und Kategorien der IDE-Palette; form_component_create fügt registrierte Klassen über IOTAFormEditor.CreateComponent ein.
- Parentwahl unterstützt explizite Container, aktuelle Auswahl, deren Parent und Formularwurzel. Auswahlfallback und Containereignung werden geprüft.
- Die Werkzeuge arbeiten im geladenen Designer und speichern weder Formular noch PAS-Unit automatisch. Mutationen benötigen Lese- und IDE-Bearbeitungsrechte und bleiben auf Workspace-Dateien beschränkt.
- README und generierter IDE-Skill beschreiben die Designeroperationen und ihre Grenzen; isolierte SDK- und MCP-Fixtures prüfen Verhalten und Berechtigungsreihenfolge ohne Änderungen an Benutzerformularen.

## 1.2.19

- debugger_evaluate wertet Ausdrücke im angehaltenen Prozess/Thread über ToolsAPI aus. debugger_modify prüft die Beschreibbarkeit und weist im selben SDK-Vorgang einen neuen Wert zu.
- debugger_cursor_expression liest eine sichtbare einzeilige Auswahl oder einen einfachen Delphi-Zugriff am Cursor; use_cursor übernimmt Ausdruck und Quellkontext in Auswertung oder Änderung.
- debugger_evaluation_status liefert verzögerte Ergebnisse über request_id, einschließlich Fehlern, Zeitüberschreitung und Änderungsstatus. Ein Timeout bricht die Debuggee-Operation nicht ab.
- Seiteneffekte sind beim Auswerten standardmäßig abgeschaltet; Properties/Funktionsaufrufe und Wertzuweisungen verlangen Ausführungsrechte. Prozess-/Threadziele werden vor Berechtigungsdialogen gebunden.
- debugger_expression_ui ruft die nativen Editoraktionen zum Hinzufügen einer Überwachung, Übernehmen des Cursorausdrucks, Auswerten/Ändern und Untersuchen auf; asynchrone Statusabfragen melden die tatsächliche Ausführung.
- Die öffentliche ToolsAPI bietet keine CRUD-Schnittstelle für die IDE-Watchliste. Auflisten, Bearbeiten und Löschen werden deshalb ausdrücklich als nicht unterstützt ausgewiesen.
- README und generierter IDE-Skill erläutern Ausdrucksparameter, Cursorgrenzen und verzögerte Änderungen. Native SDK-Fixtures prüfen die Funktionen ohne Eingriffe in einen echten Benutzer-Debuggee.

## 1.2.18

- options_search liest echte IDE-/Projekt-Optionsnamen und Typen mit deutschen/englischen Suchaliasen; die Suche öffnet kein UI und liest keine Werte. Der gecachte IDE-Insight-Katalog kennzeichnet unbekannte Vollständigkeit/Aktualität.
- options_open öffnet Projekt-/IDE-Optionen oder IDE Insight über die öffentliche SDK. Explizite Optionen bevorzugen die IDE-eigene Navigation eines eindeutigen echten Options-Insight-Eintrags; Standard-VCL-Controls ergänzen Seiten-, Editfeld- und Zeilenfokus.
- Modale Optionsdialoge öffnen asynchron; request_id ermöglicht eine lesende Statusabfrage einschließlich erreichtem Fokus, Fehlern und geschlossenem Dialog.
- Explizite Konfiguration/Plattform ändern die aktive Projektauswahl; Optionenwerte und Projektdateien werden dabei nicht automatisch geschrieben. Projektwechsel bleiben über project_activate ausdrücklich.
- IDE Insight unterstützt Suchfilter und Suchfeldfokus. Ein reiner Suchaufruf führt nichts aus; native Optionsnavigation führt ausschließlich einen eindeutig angeforderten Optionseintrag aus, keine allgemeinen Commands-/Datei-/Build-Einträge. Öffnen benötigt Lese-, IDE-Bearbeitungs- und Ausführungsrechte.
- Private Sondercontrols melden einen ausdrücklichen Status; ein öffentlicher Popup-Ergebnisindex wird nicht behauptet. README und generierter IDE-Skill erläutern Parameter, Status und Ausgabepfad-Beispiele.

## 1.2.17

- projects_list bündelt die Basisinformationen aller geöffneten Projekte: aktive Auswahl, EXE/DLL/Package, SDK-Anwendungs-/Frameworktyp, aktive Konfiguration/Plattform und Ausgabeziel.
- ProjectVersion nennt das DPROJ-Format. Packages ergänzen Description, Runtime-/DesignTime-Verwendung, automatischen/manuellen Build sowie Registrierung, Aktivierung und Ladezustand des aktuellen Ausgabeziels in dieser IDE.
- Vorhandene Felder bleiben erhalten; unbekannte Zusatzwerte werden ausdrücklich als null zurückgegeben. Ausführliche Konfigurations-/Plattform- und Optionsabfragen bleiben separat verfügbar.
- package_is_installed liest Package-Registrierung, Aktivierung und Ladezustand; installed entspricht registered und unbekannte Zustände bleiben null.
- package_install und package_uninstall wählen ein geöffnetes Package-Projekt oder eine vollständige BPL-Datei und verwenden die öffentliche ToolsAPI. Kein automatischer Build oder Projektwechsel; Deinstallation löscht die BPL nicht und unterstützt verwaiste Registrierungen.
- Installation prüft Package-Typ und IDE-Architektur. Mutationen verlangen Lese-, IDE-Bearbeitungs- und Ausführungsrechte; laufendes DAI, feste IDE-Packages und geladene Abhängigkeiten erhalten gezielte Schutzprüfungen.
- README und generierter IDE-Skill erklären die kompakte Projektübersicht und Package-Verwaltung; native OTA-Fixtures prüfen die Packageoperationen ohne echte Installation in der Benutzer-IDE.

## 1.2.16

- source_search unterstützt optional RegEx für query sowie einen zusätzlichen filename_regex-Filter auf den Dateinamen; bestehende Glob-/Interfaces-/Editorpufferregeln bleiben erhalten.
- directory_files_list, project_directory_files_list und reference_files_list ergänzen Dateinamen-RegEx und wörtliche oder RegEx-Inhaltsfilter für vollständige aktuelle Editor-/Designer- bzw. codierungstreue Dateiinhalte.
- RegEx werden je Suche wiederverwendet; Syntaxfehler und überschrittene Ausführungsgrenzen werden ausdrücklich gemeldet. Unlesbare, binäre und übergroße Inhalte werden bei Dateilisten nicht als fehlende Treffer ausgegeben.
- Fehlende file_patterns und optionale Zahlen verwenden zuverlässig ihre Standards; leere/kurze Textdateien und abgeschnittene UTF-8-Sequenzen bleiben auch bei vollständiger boolescher Auswertung sicher.
- Native Regressionen prüfen RegEx, Inhaltsfilter sowie die tatsächlichen MCP-Schemata, Argumentweitergabe und Leseberechtigungen für alle vier Suchwerkzeuge.
- README und generierter IDE-Skill erklären Parameter, kombinierte Filter und RegEx-Beispiele einschließlich JSON-Escaping.

## 1.2.15

- Nach tatsächlichem Verbreitern der Fehlersuche-Toolbar wird der gemeinsame Parent mit Realign vollständig ausgerichtet; benachbarte Toolbars erhalten das neue Layout.
- Normale Statusaktualisierungen und bereits ausreichend breite Toolbars lösen keine zusätzliche Ausrichtung aus. Parentzugriff bleibt auf lebende, fertig geladene Controls mit vorhandenem HWND beschränkt.
- Native VCL-Tests prüfen zwei benachbarte Toolbars, vollständige Bandausrichtung sowie erhaltene Nachbarbreite und unveränderte Position bei Statusupdates.

## 1.2.14

- Fünf MCP-Werkzeuge für Projektaktivierung, Konfigurationsübersicht sowie Lesen, Setzen und echtes Entfernen von Projektoptionen.
- Schreibziele verlangen eine ausdrückliche Konfiguration und Plattform; Basiskonfiguration und alle Plattformen bleiben gezielt erreichbar.
- Gelesene Optionen nennen lokale/effektive Werte, Herkunft, Eltern-/Plattformkandidaten und Listenmerge. Mehrdeutige Quellen bleiben ausdrücklich unbekannt. Remove stellt Vererbung wieder her.
- Eigene Leerwerte unterstützen neun native Delphi-Listen mit ausdrücklichem replace; andere leere Setter werden vor Änderungen abgewiesen. Der angewandte Merge-Modus wird geprüft.
- Zugriff nur auf das aktive Projekt; Änderungen bleiben bis project_save im IDE-Zustand. Referenz- und Reparse-Schreibschutz bleibt wirksam.

## 1.2.13

- Delphi-11-kompatibler parameterloser UTF-8-Decoder; optionale Code-Insight-Erweiterung wird mit Declared ausgeklammert und pro Provider abgefragt, mit Fallback auf den älteren Callback.
- Package verwendet LIBSUFFIX AUTO: BPL-Namen enthalten die Compiler-Package-Version; der Build prüft ausschließlich die tatsächlich neu geschriebene versionierte BPL.
- Nach Buttonaufbau, Wiederverwendung und Altlastenbereinigung erhält die Fehlersuche-Toolbar den fehlenden horizontalen Platz bis zum tatsächlichen nativen DAI-Buttonrechteck.
- Die Anpassung prüft die native Buttonidentität und respektiert DPI und Größenbeschränkungen. Position, Höhe und bereits größere Breiten bleiben erhalten; normale Refreshes verändern die Breite nicht.
- ReadOnly-Fensterinspektion nennt bei unsensiblen ToolButtons VCL-/Native-Rechtecke, Clientbereich, native Sichtbarkeit und Bildbestand. Vorhandene HWNDs werden gelesen; die Diagnose erzeugt keine neuen Handles.

## 1.2.12

- Ein öffentlicher ToolsAPI-Toolbar-Lesenotifier erfasst den ursprünglich benannten DAI-Button vor Delphis Namensnormalisierung; Aktion und Menü werden nach dem Lesen erneut zugeordnet.
- Beim Desktoprestore wird genau der erfasste eigene Button wiederverwendet. Ein weiterer anonymer DAI-Button entsteht dadurch nicht; Objektidentität, Besitzer und offizielle Debug-Toolbar werden geprüft.
- Ein einzelner bestätigter Altrest wird nur unmittelbar nach erfolgreicher Wiederverwendung des ursprünglich benannten DAI-Eintrags bereinigt. Die allgemeine Altlastenmigration bleibt auf drei bis fünf begrenzt.
- Schwache VCL-Freigabebenachrichtigungen und vor der Abmeldung getrennte Notifier verhindern Rückrufe auf bereits freigegebene Controller; mehrdeutige oder fremd verknüpfte Controls bleiben erhalten.

## 1.2.11

- Altbutton-Migration verwendet die eindeutige Rückkehr-Aktion aus der offiziellen IDE-ActionList; die IDE stellt Standardbuttons ohne Komponentennamen wieder her.
- Drei bis fünf verifizierte vollständig inerte Altbuttons direkt vor dem eigenen DAI-Button werden entfernt; Objektidentität, Nachbarschaft und alle Schutzbedingungen bleiben erforderlich.
- Dieselbe begrenzte Prüfung erfolgt auch nach späterem Desktoprestore bei erhaltenen Controls. Im Abbau befindliche Toolbars, Actionlisten, Buttons und Aktionen werden ausgespart.

## 1.2.10

- Listener- und angenommene HTTP-Sockets werden über geprüftes SetHandleInformation nicht vererbbar gesetzt. IDE-Kindprozesse behalten nach Stop keine geerbten DAI-Sockets.
- Echter Kindprozess-Regressionsfall reproduziert den alten Listener trotz geschlossenem Parent-Handle; nach Fix ist derselbe Port bei lebendem Kind sofort frei.
- Toolbar-Aktion gehört dem stabilen Besitzer der IDE-ActionList; VCL-Streaming kann sie ohne unauflösbaren .Owner-Pfad wiederfinden.
- Beim Entfernen werden alle Toolbar-Clients derselben DAI-Action-Objektidentität beseitigt. Eng begrenzte Migration der bestätigten drei/vier inerten Altbuttons hinter RunUntilReturn.
- ReadOnly-Fensterinspektion nennt Eltern/Besitzer und bei nicht sensiblen ToolButtons Action, Bild und Dropdown-Verknüpfung; sensible Controls bleiben ausgespart.

## 1.2.9

- Toolbar erhält transparente Serversymbole für inaktiv, aktiv und Fehler; native 16×16-Glyphen und größere Auflösungen über INTAServices280.AddImage.
- ActionList wird vor dem ImageIndex zugeordnet, damit die IDE-Bildliste den initialen Bildnamen korrekt setzt; isolierter BPL-Unload-/Reload-Vertrag geprüft.
- Listener wird auf dem IDE-Hauptthread geschlossen, danach werden wartende HTTP-Arbeiter mit Synchronize-Verarbeitung vollständig beendet.
- Reentrante Start-/Übernahmeaufrufe während Stop werden auch vor idempotenten Kurzschlüssen abgewiesen; Socketbindungen erst nach vollständigem Drain freigeben.
- Stop prüft die eigenen ehemaligen Socket-Handles; Fehler nennen Listenerzustand und die zugrunde liegende Winsock-Exception. Fremde Handles werden nicht geschlossen.
- Native Server-Lifecycle-Regressionen mit echtem HTTP-Verkehr, sofortigem Wiederbinden und Instanzwechsel, statisch sowie mit Hersteller-/IDE-Indy-Packages.
- PNG-Glyphen verwenden Delphis vorhandenes Standardpackage vclimg; weiterhin keine GetIt-Abhängigkeit.

## 1.2.8

- Fensterschließbefehle werden vor der Berechtigungsprüfung normalisiert; auch Großschreibung und umgebende Leerzeichen verlangen die zusätzliche Ausführungsfreigabe.
- Threadlisten und Stacktrace wählen OS-Prozess-/Thread-IDs aus den von Delphi gedebuggten Prozessen; mehrere Prozesse und gedebuggte Subprozesse werden berücksichtigt.
- Stacktrace eines angehaltenen aktuellen oder ausgewählten Debuggerthreads mit Frame-/Zeichenlimit über die öffentliche ToolsAPI auslesen.
- Compiler- und Debuggerlog getrennt lesen: letzte 50 Einträge als Standard, Anzahl begrenzen oder einzelnen Index auswählen; Zeichenlimit und Kürzungsstatus.
- DAI-Schaltfläche in Delphis bestehender Fehlersuche-Toolbar zeigt Serverzustand und Port; Klick startet/stoppt, Dropdown öffnet Optionen oder setzt Sitzungsfreigaben zurück.
- IDE-Fenster minimieren, wiederherstellen, Vorder-/Hintergrund anfordern und normal schließen; der HTTP-Schließauftrag wird vor WM_CLOSE bestätigt.
- Optionsseite zeigt Skill und dynamischen MCP-Werkzeugkatalog; Clientdetails sind ohne zusätzliche Leerzeilen um vier Leerzeichen eingerückt.

## 1.2.7

- Package-Abschluss sperrt neue LSP-Anfragen; eigene Callbackbroker und gehaltenes Callbackmodul schützen noch ausstehende Rückrufe. Package-Austausch nach Code Insight erfordert IDE-Neustart.
- Eigene Logcallbacks werden beim Abschluss gezielt entfernt; reentranter Runtime-Stop und fehlgeschlagener Server-Drain geben den Server nicht voreilig frei.
- Unicode in DFM-/FMX-Stringliteralen wird vor dem Designer-Rückwechsel nativ normalisiert; der PAS-Schutz vergleicht echte Inhalte statt des gemeinsamen Modified-Flags.

- Code Insight verwendet eigene Callback-Empfänger pro Anfrage; wiederverwendete IDs, Providerwechsel und verspätete Antworten verfälschen keine spätere Anfrage.
- Höchstens 256 noch nicht abgeschlossene Callback-Empfänger; weitere Anfragen werden vor dem Provideraufruf mit einer Erklärung abgewiesen.
- Ein reiner Help-Insight-Marker „HTML“ gilt als nicht verfügbar; tatsächlicher HTML-Inhalt bleibt erhalten.
- DFM-/FMX-Textmodus verwendet den nativen OTA-Wechsel und bestätigt Erfolg erst bei vorhandenem Quelltexteditor; auch ungespeicherte Formularnamen werden aufgelöst.
- Formulartext-Schreiben verwendet denselben nativen Pfad; save=false erhält den Editorpuffer ohne Datenträger-Fallback.
- Native Formularwechsel werden außerhalb des IDE-Hauptthreads begrenzt abgewartet; parallele Anfragen teilen eine Umschaltung.
- Noch nicht gespeicherte oder geänderte PAS-Units blockieren den ersetzenden Textmoduswechsel vorab; Rückwechsel zum Designer unterstützt.
- Aktive modale VCL-Dialoge auslesen, Buttons gezielt klicken oder Form.ModalResult setzen; kurzlebige Einmal-Tokens prüfen Identität, Titel und Dialogtext.
- DAI-Freigaben, native WinAPI-Dialoge und Eingabefeldtexte bleiben ausgeschlossen; Aktionen verlangen IDE-Bearbeitungs- und Ausführungsrechte.
- IDE-Builds verwenden den dokumentierten Wait=False-Parameter und warten bei Erfolg nicht auf OK; tatsächliches Ergebnis bleibt synchron.
- Nicht lesbare String-Eigenschaften im Designer melden value_available=false, anstatt einen leeren Wert vorzutäuschen.
- Native Code-Insight-Regressionen für Win32/Win64 sowie Live-IDE-Tests für Quellen, Editor, Projektverwaltung, Haltepunkte, Exception und Debuggersteuerung ergänzt.

## 1.2.6

- „Server starten“ verwendet unmittelbar die Port-/Token-Eingaben der geöffneten Optionsseite; dauerhaftes Speichern bleibt separat.
- Laufender Server hält eine unveränderliche Port-/Token-Konfiguration; spätere Drafts oder Settings-Zuweisungen ändern keine aktive Authentifizierung.
- Optionsstatus und ide_status melden den tatsächlich gebundenen Port; configured_port zeigt den übernommenen Wert.
- Übernehmen vergleicht Port und Token und startet bei Änderungen unter derselben Instanzsperre neu; Stop/Bindefehler räumen die Laufzeitwerte auf.
- Gemeinsame Validierung für Start und Speichern; ungültige Eingaben schließen den Optionsdialog beim Speichern nicht.
- Wechsel des Berechtigungsbereichs lädt ausschließlich Berechtigungen und erhält ungespeicherte Servereingaben.
- Hauptthread-Stopp arbeitet wartende OTA-Synchronize-Aufrufe über Thread.WaitFor ab; Reentrancyguard schützt während des Indy-Shutdowns.
- Native Regressionen prüfen den tatsächlichen VCL-Optionsframe und HTTP-Server mit isolierten Abhängigkeiten unter Win32/Win64.

## 1.2.5

- 18 längere Text-/JSON-Vorlagen als native Delphi-Multiline-Strings mit explizitem TEXTBLOCK CRLF; dynamische Werte über Format.
- Skill, Quellvorlagen, Dialogtexte und serialisierte MCP-Werkzeugdefinitionen bleiben unverändert; Prüfer versteht Textblöcke.
- Statische Versionsprüfung prüft optionale Datei-/Produktversionsressourcen nur bei aktivierter VerInfo_IncludeVerInfo-Einstellung.
- DAI-Skill heißt künftig dai-delphi-ide; Verzeichnis und YAML-Name tragen die Herkunft, vorgeschriebene Einstiegsdatei bleibt SKILL.md.
- Native Skillmigration für beide alten delphi-ide-Pfade unter USERPROFILE/APPDATA, mit Besitzmarkern, Sicherungen und Konfliktprüfung.
- MigrateSkillFiles aktualisiert ausschließlich Skills; vorhandene Clientkonfigurationen und Settings bleiben unverändert.
- Status und Deregistrierung erkennen alte und neue eigene Skills. Fremde Inhalte bleiben erhalten.
- Eigene Verwaltungs-/Sicherungs-/Hilfsdateien tragen weiterhin dai/DAI; vorgeschriebene gemeinsame Clientdateinamen bleiben kompatibel.
- Native Registrierungstests um Migration, Idempotenz, Fremdkollisionen, schreibgeschützte Altdaten und unveränderte Konfigurationen erweitert.

## 1.2.4

- interfaces_only mit Standard true in source_search, file_read und reference_file_read; Pascal-Units enden in der Antwort vor implementation.
- Gemeinsamer lexikalischer Filter berücksichtigt Kommentare, Direktiven, escaped identifiers, Unicode und Delphi-Multiline-Strings; kein Präprozessor.
- Vollständiger Inhaltshash bleibt erhalten; Interfaceansicht, Zeichenlimit und vollständiger Inhalt werden ausdrücklich unterschieden.
- Vor Ganzdatei-Schreibzugriffen auf .pas Strukturprüfung für Unit-Kopf, interface, implementation und end., vor Editor-/Datenträgermutationen.
- IDE-Diagnosen nennen IOTAModuleErrors.GetErrors und unbekannte Aktualität; keine unbelegte Validierung vorgeschlagenen Texts über LSP.
- IDE-Skill erklärt Interface-/Volltextwahl, vollständigen Schreibinhalt und Diagnosegrenzen; nativ erzeugt, validiert und mit Backup aktualisiert.
- Native Filter-/Struktur-/Editorregressionen und vollständige Win32-/Win64-Builds ohne neue GetIt-Abhängigkeit.

## 1.2.3

- Native ReadOnly-Quelltextsuche in Projekt, Projektgruppe, Delphi-/ToolsAPI-/Samples-/GetIt-Referenzen mit Zeile, Spalte, Editorpuffervorrang und Grenzen.
- Referenzpfade mit explizitem ToolsAPI-Eintrag und aufgelösten BDS-/GetIt-/Samples-Aliasen; Schreibschutz gilt auch für im Editor geöffnete Referenzdateien.
- Schreibschutz-Vorprüfungen für Projekt-/Gruppenspeichern, Entfernen und IDE-Builds einschließlich Begleitdateien, Abhängigkeiten und Reparse-Schreibpfaden.
- Dateimuster der Quellsuche verwenden einen begrenzten eigenen Globmatcher für `*` und `?`, ohne System.Masks-Backtracking.
- Generierter IDE-Skill erklärt Quellsuche, tatsächliche Deklarationen, ReadOnly-Grenzen und Projektanlage über die OTA.
- project_create unterstützt save=false; VCL-Projekte erhalten ihr Hauptformular über den Projektcallback der IDE.
- Lesende IDE-/Debuggee-Fensterinspektion über WinAPI und VCL-Metadaten, ohne Anlegen von Handles oder Debuggee-Fortsetzung.
- Editor-Readback akzeptiert genau ein von der IDE ergänztes CRLF; Rückgabehash und Zeilenenden stammen aus dem tatsächlichen Puffer.
- Native Regressionstests für Quellsuche, Pfadaliasauflösung, Editor-Readback und Fensterinspektion; Package-Builds für Win32 und Win64.

## 1.2.2

- Win32 und Win64 im Package-Projekt aktiviert; vollständiger Release-Build für beide Delphi-IDE-Architekturen. Build prüft PE-Architektur und DLL-/EXE-Typ.
- Eigene Delphi-Sperre für genau einen aktiven MCP-Server je Windowsbenutzer, unabhängig von IDE-Architektur, Delphi-Version und Port. Die erste erfolgreiche Serverinstanz übernimmt.
- Stoppen und Prozessende geben die Sperre frei; fehlgeschlagener Start erst nach abgeschlossener Bereinigung. Keine automatische Übernahme durch wartende IDEs.
- Manuelle Start-/Stop-Schaltflächen in den DAI-Optionen, ohne gespeicherte Einstellungen zu ändern. ide_status meldet IDE-Architektur, Prozess, EXE, BPL und passenden Package-Schlüssel.
- Autostart gilt nur beim IDE-Start; Übernehmen der Optionen bewahrt manuelles Starten/Stoppen. Portänderungen am laufenden Server behalten die Instanzsperre während des Neustarts.
- Native Instanztests einschließlich getrennten Win32-/Win64-Prozessen und Prozessabbruch; HTTP-Tests prüfen Übernahme und Freigabe nach Bindfehlern.

## 1.2.1

- Eigene Delphi-Sitzungsverwaltung mit 30 Minuten Inaktivitätsfrist, monotoner Zeitmessung und gezieltem Aufräumen. Laufende Anfragen bleiben geschützt.
- Das Limit von 1.024 Sitzungen weist neue Initialisierungen mit HTTP 503 ab, statt alle bestehenden Sitzungen zu löschen.
- Klassische MCP-Sitzungen können mit authentifiziertem HTTP DELETE beendet werden; die native stdio-Brücke beendet ihre Sitzung beim Schließen der Eingabe.
- Native Sessiontests und HTTP-Lebenszyklustests ergänzt; statische Prüfung schützt die dokumentierten Standardpakete vor zusätzlichen GetIt-Abhängigkeiten.

## 1.2.0

- KI-Client-Registrierung in Delphi für Codex, Claude Code, Claude Desktop, Gemini CLI / Code Assist, Hermes, LM Studio und OpenClaw ergänzt; Eigent und Gemini Desktop mit geprüften manuellen Hinweisen.
- Native Delphi-stdio-Brücke für Claude Desktop; HTTP mit Bearer-Token und verwalteter Session.
- Sicherungen, private Windows-Rechte, gezielte JSON-/JSON5-/YAML-Änderungen und Besitzprüfung vor Aktualisierung oder Deregistrierung.
- Codex berücksichtigt CODEX_HOME; Skill enthält YAML-Metadaten und aktuelle Arbeitsanweisungen. Fremde Skills bleiben erhalten.
- Formdesigner-Inspektion/Anzeige, aktuelle ungespeicherte DFM-/FMX-Inhalte, Quellhaltepunkte und Debugger-Steuerung über OpenToolsAPI.
- Aktives Projekt und Projektgruppen-Dateizugriff korrigiert; sicherer Umgang mit Projektmodulen, Editor-Hashkonflikten und save=false.
- HTTP-Origin-, Session-, JSON-RPC- und Projektberechtigungsprüfung korrigiert; moderner und klassischer MCP-Verbindungsablauf geprüft.
- Reproduzierbare native Registrierungs- und Protokolltests sowie Test der kompilierten Delphi-Brücke.

## 1.1.16

- Hinweis am unteren Ende des DAI-Options-Frames ergänzt, dass die Codex-App nach Änderungen an Port oder Bearer-Token sowie nach dem Registrieren oder Deregistrieren neu gestartet werden muss
- Hinweis in die dynamische Frame-Höhe einbezogen, damit die IDE-eigene ScrollBox ihn vollständig anzeigt

## 1.1.15

- dynamisch geladene WinAPI-Funktionen werden direkt den typisierten Codepointer-Variablen zugewiesen
- unzulässige Schreibzugriffe über `Pointer(LQueryFullProcessImageNameW)` und `Pointer(LGetExtendedTcpTable)` entfernt
- statische Prüfung ergänzt, die linkseitige Pointer-Casts bei `GetProcAddress` für diese Funktionsvariablen zurückweist

## 1.1.14

- Indy akzeptiert das Autorisierungsschema `Bearer` nun über `OnParseAuthentication`, bevor unbekannte Schemata verworfen werden
- Bearer-Schema wird case-insensitiv, der eigentliche Token weiterhin als case-sensitiver undurchsichtiger Wert geprüft
- Codex-Konfiguration und persönlicher Skill werden aus `%USERPROFILE%` statt aus `TPath.GetHomePath` abgeleitet
- beim Registrieren und Deregistrieren werden ausschließlich von DAI markierte Altdateien unter `%APPDATA%` sicher bereinigt

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
