# DAI 1.2.13 – automatische Package-Versionssuffixe, 2. Oktober 2026

Die vom Nutzer gesetzten DllSuffix=$(Auto) im DPROJ und LIBSUFFIX AUTO im DPK bleiben erhalten. Delphi 13 / BDS 37.0 erzeugt
jetzt DAI370.bpl. Ausgabeverzeichnisse und Bridge-Dateiname bleiben unverändert; die Bridge wird weiterhin neben dem tatsächlich
geladenen Package gesucht. Die entsprechende Statusmeldung und die aktuellen Installationshinweise sind suffixunabhängig formuliert.

Build.ps1 akzeptiert ausschließlich genau eine beim aktuellen Build neu geschriebene versionierte DAI-BPL. Vorhandene unsuffigierte
DAI.bpl und unveränderte BPLs früherer Builds werden nicht als aktuelles Ergebnis geprüft. Release und Debug für Win32/Win64 sowie
ein wiederholter Win32-Release-Build sind erfolgreich; die jeweiligen BPL-/Bridge-Ausgaben bestehen die PE-Architektur-/Typprüfung.
Die zusätzlichen statischen Prüfungen für DPROJ/DPK-AUTO, XML, BOM, Zeilenenden und GetIt-Unabhängigkeit bestehen.

Bei geschlossener IDE wurden beide vorhandenen BDS-37.0-Registrierungen von Build/Win32 bzw. Win64/Debug/Bpl/DAI.bpl auf die
jeweilige DAI370.bpl umgestellt und nachgelesen. Beschreibung und Architekturzuordnung bleiben erhalten; die alten Einträge wurden
entfernt. Vorherige Werte liegen im Codex-Workspace in package-registration-before-auto-suffix.json. Die neue Registrierung ist
noch nicht durch einen weiteren tatsächlichen IDE-Start geprüft. Delphi 11 ist hier nicht installiert und wurde nicht binär geprüft.

Die vollständige statische Gesamtprüfung meldet weiterhin sieben bereits in HEAD d4b8071 vorhandene Befunde: eine 182-Zeichen-Zeile
im Delphi-11-Fallback (Projects.pas:349), vier Schema-Argumentzählungen und eine Klammerprüfung, deren Scanner beide alternativen
CompilerVersion-Zweige zugleich verarbeitet, sowie eine Versionsprüfung der deaktivierten WinARM64EC-Konfiguration.
Keiner dieser Befunde wurde durch die Suffixänderung eingeführt. Der Manifeststand wurde auf die aktuellen Dateien aktualisiert.

# DAI 1.2.13 – tatsächliche Toolbar-Darstellung nach Packagebuild, 2. Oktober 2026

## Ergebnis in der laufenden Win64-IDE

Der Nutzer bestätigte nach dem manuellen IDE-Packagebuild ausdrücklich: „Kompiliert, Button sichtbar“. Health bestätigt HTTP 200,
DAI 1.2.13 und active=true. Die Toolbar enthält genau einen DAIServerToolButton mit aktivem Serversymbol, DAIServerToggleAction
und Dropdownmenü; keine inerten namenlosen Zusatzbuttons. Der Listener verschwand während des normalen Package-Austauschs und
kehrte unter derselben Win64-IDE PID 28240 zurück. Die Überwachung dokumentiert 1.2.12 vor und 1.2.13 nach dem Austausch.

Die erweiterte ReadOnly-Inspektion belegt die tatsächliche Ursache: Vor dem Fix lag der Button bei x=218..263 vollständig außerhalb
des Clientbereichs mit Breite 218. VCL-Visible, native Registrierung, native Identität und Bildliste waren bereits korrekt. Die tatsächliche
TDockToolBar hat AutoSize=False und Wrapable=False. Nach dem Fix ist die Clientbreite 263; das eigene native Rechteck liegt horizontal
vollständig darin. Left=346, Top=30, Höhe 24, AutoSize und Wrapable bleiben erhalten; ImageIndex 347 liegt in der nativen Bildliste mit 350 Bildern.
Alle Standardbuttons hatten bereits vorher native Höhe 28 bei Clienthöhe 24. Diese bestehende vertikale Geometrie wurde beibehalten;
das allgemeine Diagnosefeld clipped kann deshalb weiterhin true sein. Die horizontale Korrektur und tatsächliche Sichtbarkeit sind bestätigt.

Artefakte im Codex-Workspace: inspect-toolbar-geometry-win64-1212.txt, inspect-after-packagebuild-win64-1213.txt,
listener-1213-reload.jsonl und health-win64-1213.json. Der globale Fenstersnapshot ist begrenzt; die relevante DebugToolBar ist enthalten.

## Umsetzung und Verifikation

DAI vergrößert die bestehende Toolbar ausschließlich nach eigener Buttonerzeugung oder positiv bestätigter Restore-Adoption und nach
Altlastenbereinigung. Grundlage ist das native Rechteck des exakt eigenen Buttons. Vorhandenes HWND, Index, native Objektidentität,
Sichtbarkeit, Größenbeschränkungen und stabile DPI werden geprüft. Bereits größere Breiten bleiben erhalten, gewöhnliche Refreshes
verändern die Breite nicht. Die Altbutton-Migration bleibt unverändert begrenzt; der ursprünglich benannte Streambutton wird wiederverwendet.

Win32 und Win64 bestanden mit dem endgültigen Toolbar-BOMhash b01faac4e2a4181a5405420b71528dfc4cebf7d4393f269c9ac0ec2261c0ea80
jeweils 4.553 Checks der vollständigen Toolbar-Suite. Darin enthalten sind je 366 gezielte Layoutchecks; deren separater Lauf bestand ebenfalls.
Sie prüfen feste Breite, tatsächlichen Dropdown, Streamreuse, Reload und Altbereinigung, erhaltene Höhe/Position/AutoSize/Wrapable,
bereits breite Toolbars, Constraints und fehlendes periodisches Übersteuern einer Benutzerverkleinerung. SDK-, Test-BPL- und Hostbuilds
kompilieren B+/Q+/R+ gegen die installierte designide.dcp ohne Warnungen oder Hinweise.

Die erweiterte Fensterdiagnose bestand zusätzlich je 223 native Windowschecks: Native-Count/Identität/Sichtbarkeit/Rechtecke,
Clipping trotz Visible=True, Bildbestand, ungültige Indizes, fehlendes HWND ohne Neuerzeugung und Sensitive-Ausschluss. Danach wurde
lediglich der direkte Vcl.ImgList-Import ergänzt, um den Inline-Hinweis H2443 zu beseitigen; die Diagnosefunktion bleibt identisch.

Release-Package und Bridge für Win32/Win64 sowie Debug-Win32 wurden gegen den Endstand gebaut. Das Debug-Win64-Package wurde in
der tatsächlichen IDE gebaut und live als 1.2.13 bestätigt; seine unveränderte Bridge liegt ebenfalls vor. Alle acht BPL-/EXE-Artefakte
sind nach PE-Architektur und DLL-/EXE-Typ geprüft. Reguläre Projektbuilds behalten die vorherigen W1002-/H2077-Meldungen; keine neue Toolbarwarnung.
Statische Prüfung: 43 Pascal-Units, 59 MCP-Werkzeuge und keine GetIt-Abhängigkeit. BOM/CRLF, Versionskonsistenz, Manifest und Diffprüfung sind sauber.

Der konkrete AutoSize-Wert einer gleichzeitig laufenden Win32-IDE wurde nicht erneut gemessen. Die isolierten nativen Layoutfälle sind
für beide Architekturen reproduziert; dieser Befund beweist keinen ausschließlich Win64-spezifischen IDE-Fehler. Der zusätzliche tatsächliche
IDE-Neustart mit 1.2.13 wurde nicht verlangt: Der Native-Restorepfad ist getestet, und der tatsächliche Package-Neuladefall ist nun bestätigt.

Die folgenden früheren Prüfstände bleiben als Historie erhalten.

# DAI 1.2.12 – Wiederverwendung des gestreamten Toolbarbuttons, 2. Oktober 2026

## Befund und Korrektur

Die tatsächliche Win64-IDE (PID 14404, bin64/bds.exe) bestätigte DAI 1.2.11, Build/Win64/Debug/Bpl/DAI.bpl und einen aktiven Server auf 7333.
Der Nutzer meldete einen zunächst guten visuellen Eindruck. Die ReadOnly-Toolbarinspektion zeigte jedoch einen vollständig inerten
namenlosen Dropdownrest unmittelbar vor dem aktiven DAI-Button. Der gespeicherte Registry-Stream enthält einen ursprünglich benannten
DAIServerToolButton mit korrekten Action-/Menünamen. Native TReader-Proben bestätigen: Wenn die Zielobjekte beim Lesen fehlen, bleiben
diese Referenzen leer; späteres Anlegen der Action/des Menüs repariert den bereits abgeschlossenen ReadComponents-Aufruf nicht.

1.2.12 registriert unmittelbar beim Toolbar-Install einen öffentlichen INTAReadToolbarNotifier. Er erfasst ausschließlich den eigenen
originalen Namen vor Delphis Button-Namensnormalisierung. Reader.Root/Owner sind der IDE-Besitzer AppBuilder, Reader.Parent die DebugToolBar;
während des Lesens kann INTAServices.ToolBar[sDebugToolBar] nil sein. Nach Ende des Lesens prüft Refresh zusätzlich die konkrete SDK-Toolbar,
Besitzer, Objektidentität und fremde Verknüpfungen, bevor es genau dieses Objekt wieder mit eigener Action und eigenem Menü verbindet.

Nur während einer positiv bestätigten Wiederverwendung darf der einzelne vollständig inerte historische Rest zwischen der tatsächlichen
RunUntilReturnCommand-Action und dem eigenen Button entfernt werden. Ohne diesen Nachweis bleibt die allgemeine Migration auf drei bis fünf
begrenzt. Die schwache Capture verfolgt Freigaben und Mehrdeutigkeit. Vor Unregister wird der Controller getrennt; beide Abmeldepfade sichern
auch reentrantes Shutdown und fehlschlagendes Unregister ab. Ein normales Unregister pinnt das Package nicht.

## Native Verifikation

Die endgültige Produktionsunit mit BOM-Dateihash afe732379577d99dd2c9d75edce06466b64ac0042f8b06028495e9569ce9f930 bestand
unter Win32 und Win64 jeweils 4.187 Checks der vollständigen Toolbar-Suite. Darin enthalten sind je 560 echte TWriter/TReader-Restorechecks;
deren zusätzlicher gezielter Lauf bestand ebenfalls. Die Prüfsuite enthält den Start vor Action-/Menüerzeugung, dreifaches Restore,
Refresh bei vorübergehend nil SDK-Toolbar, einmaligen Einzelrest, fremde Action/Eventhandler/Tag/Dragging, doppelte Originalnamen,
Freigabe vor Adoption, Hostzerstörung, Notifier-Abkopplung und reentrantes Register-Shutdown bei fehlschlagendem Unregister.

Die isolierten SDK-Proben kompilieren gegen die tatsächlich installierte designide.dcp. SDK-, Test-BPL- und Hostkompilierung verwenden
B+/Q+/R+ und melden keine Warnungen oder Hinweise. Die vollständige Suite enthält auch den nativen gepinnten BPL-Finalize/Initialize-Vertrag.
Logs: work/skill-validation/toolbar-all-1212-final.log und toolbar-stream-1212-final.log im Codex-Workspace.

Release-Package und Bridge beider Architekturen sowie Debug-Win32 wurden gegen diesen Endstand erfolgreich gebaut. Die regulären
Projektbuilds behalten ihre bekannten plattformspezifischen W1002-Warnungen und den H2077-Hinweis in ConfigText; keine neue Toolbarwarnung.
Die statische Prüfung bestätigt weiterhin 43 Pascal-Units, 59 MCP-Werkzeuge und keine GetIt-Abhängigkeit. BOM, CRLF und Diffprüfung sind sauber.

## Live-Prüfung in Win64

Nach dem bestätigten IDE-Abschluss wurde die installierte Debug-Win64-BPL mit dem endgültigen Quellstand gebaut und bin64/bds.exe erneut
gestartet. Health bestätigt HTTP 200, DAI 1.2.12 und active=true. ide_status bestätigt PID 28240, Win64, Known Packages x64,
Build/Win64/Debug/Bpl/DAI.bpl, das aktive DAI-Projekt und Port 7333. Die ReadOnly-VCL-Inspektion zeigt keinen inerten Altbutton und genau einen
DAIServerToolButton mit DAIServerToggleAction, aktivem Serversymbol und Dropdownmenü unmittelbar nach RunUntilReturnCommand.
Der globale Fenstersnapshot ist auf 500 Controls gekürzt; die relevante DebugToolBar-Unterliste ist darin enthalten.

Alle acht Release-/Debug-Package-/Bridgeartefakte sind vorhanden und nach PE-Architektur sowie DLL-/EXE-Typ geprüft. Das geladene Win64-Package
ist zusätzlich live über Health und den tatsächlich gemeldeten Packagepfad bestätigt. Die Quellunit ist unverändert gegenüber dem nativen Endtest.

Der Nutzer löste anschließend den manuellen IDE-Packagebuild aus. Die Überwachung bestätigt das Entfernen und Wiederkehren des Listeners
zwischen 07:35:25 und 07:35:27 UTC; Health meldet wieder 1.2.12, active=true. Die anschließende VCL-Inspektion findet genau einen
DAIServerToolButton mit visible=true, aktivem Bild, Action und Menü und weiterhin keinen inerten Zusatzbutton. Der Nutzer meldet jedoch
auch nach weiterer Wartezeit, dass der Button tatsächlich nicht sichtbar ist. Damit ist der Darstellungs-/Layoutpfad noch nicht abgeschlossen.
Die reine Leseinspektion wird um native Rechtecke, Clipping und Bildbestand erweitert, um die Ursache vor der Korrektur konkret zu messen.
Die bisherige VCL-visible-Angabe alleine bestätigt keine tatsächlich sichtbare native Toolbarfläche. Gesicherte Befunde:
listener-1212-reload.jsonl, inspect-failed-packagebuild-win64-1212.txt und build-logs-afterbuild-win64-1212.json im Codex-Workspace.

Die folgenden früheren Prüfstände bleiben als Historie erhalten.

# DAI 1.2.11 – Toolbarbereinigung und IDE-Packagebuild, 2. Oktober 2026

## Ergebnis in der tatsächlichen Win32-IDE

Die neue ReadOnly-Inspektion zeigte, dass Delphi sämtliche Standardbuttons der DebugToolBar ohne Komponentennamen wiederherstellt.
Der bisherige Name-Anchor RunUntilReturn konnte daher die Altbutton-Migration nicht auslösen. Fünf vollständig inerte Dropdowns standen live
zwischen der tatsächlichen Action RunUntilReturnCommand und dem aktuellen DAI-Button. Vier stammten aus der vorherigen Sitzung; der alte
benannte DAI-Eintrag wurde beim Neustart ebenfalls namenlos.

DAI 1.2.11 wurde direkt durch den manuellen IDE-Build geladen, ohne weiteren IDE-Neustart. Health bestätigte Version 1.2.11; Listener und MCP
kamen nach der normalen kurzen Package-Unload-Unterbrechung wieder. Die VCL-Inspektion bestätigte null inerte Altbuttons und exakt einen
DAIServerToolButton mit DAIServerToggleAction, aktivem Serversymbol und Dropdownmenü unmittelbar nach der Rückkehr-Aktion.
Die Wiederholung eines weiteren IDE-Builds nach der Bereinigung ist noch ausstehend. Die entsprechende Nutzerrückfrage ist offen;
das erneute Entstehen eines einzelnen Altbuttons nach dieser Wiederholung wurde noch nicht live geprüft.

Der Socketfix aus 1.2.10 ist ebenfalls live geprüft: Stop entfernte den Listener auf 127.0.0.1:7333 bei weiterlaufender IDE und drei
DelphiLSP-Kindprozessen; der anschließende Start bestätigte wieder HTTP-200-health und active=true. Die genaue früher geerbte Referenz
in einem bestimmten IDE-Kindprozess wurde nicht direkt ausgelesen; die native Vererbungsregression und die tatsächliche Portfreigabe sind bestätigt.

## Begrenzung und native Verifikation

Der Migrationsanker ist die genau einmal in der offiziellen IDE-ActionList vorhandene Action RunUntilReturnCommand. Nur deren konkrete
Objektidentität an genau einem Button derselben Toolbar zählt. Die unmittelbar folgende Gruppe muss exakt drei, vier oder fünf vollständig
inerte Stock-TToolButtons enthalten und direkt vor dem eigenen aktuellen, unverändert verknüpften DAI-Button enden. Alle Kandidaten werden
vor dem ersten Löschen geprüft. Mehrdeutigkeit, Fremdaktionen, Abweichungen, Dragging oder Objekte im Abbau verhindern die Migration.
Die Prüfung ist idempotent und berücksichtigt auch einen späteren Desktoprestore bei erhaltenen Toolbar-/Buttonobjekten.

Unter Win32 und Win64 bestanden jeweils 3.415 Checks der vollständigen Anker-/Lebensdauer-/LateRestore-Suite. Nach der letzten kleinen
Drag-Absicherung wurde die endgültige Produktion erneut kompiliert und in 72 gezielten zusätzlichen Checks je Architektur geprüft:
Die bekannte Fünfergruppe wird entfernt; dmAutomatic und dkDock bleiben erhalten. Insgesamt bestanden in dieser Runde 6.974 Toolbarchecks.
Der reguläre All-Runner enthält sämtliche 3.487 Checks je Architektur, der gezielte LegacyDrag-Runner die 72 abschließenden Checks.
SDK-, Test-BPL- und Hostkompilierung meldeten keine Warnungen oder Hinweise. BOM, CRLF, Tabfreiheit, maximale Pascal-Zeilenlänge und Diffprüfung sind sauber.

## Builds und Grenzen

Release-Package und Bridge sowie Debug-Win64 wurden mit dem eingefrorenen Endstand gebaut. Das Debug-Win32-Package wurde in der
tatsächlichen IDE gebaut und live als 1.2.11 bestätigt; die Debug-Win32-Bridge wurde separat neu gebaut. Alle acht Package-/Bridgeartefakte
sind nach PE-Architektur und DLL-/EXE-Typ geprüft. Die statische Prüfung bestätigt weiterhin 43 Pascal-Units, 59 MCP-Werkzeuge und keine GetIt-Abhängigkeit.

Der Nutzer wechselte anschließend in die tatsächliche Win64-IDE und bestätigte eine gute erste Sichtprüfung. ReadOnly-Status und Health
bestätigen PID 14404, bin64/bds.exe, Known Packages x64, Build/Win64/Debug/Bpl/DAI.bpl, DAI 1.2.11 und den aktiven Server auf7333.
Die VCL-Inspektion bestätigt einen aktiven DAI-Button mit Aktion und Dropdown, zeigt daneben aber einen einzelnen neuen namenlosen
inerten Dropdownrest. Der nach Win32-Abschluss gespeicherte Toolbarstream enthält ausschließlich Standardbuttons und genau einen
DAIServerToolButton mit korrekt gespeicherten Referenzen DAIServerToggleAction/DAIServerPopupMenu; deren früherer .Owner-Fehler ist behoben.
Beim frühen Lesen dieses Streams sind DAI-Action/Menu offenbar noch nicht angelegt, weil der Controller erst per500ms-Timer installiert.
Diese Entstehungshypothese wird gezielt geprüft; die begrenzte Drei-bis-fünf-Migration entfernt den einzelnen Rest bisher nicht.
Ein nach Code-Insight-Callbacks gepinntes Package benötigt für den Austausch seines BPL-Images weiterhin einen IDE-Neustart.
Frühere vollständige Skill-/Werkzeugprüfungen bleiben unten dokumentiert.

# DAI 1.2.10 – Socketvererbung und Toolbar-Altlasten, 2. Oktober 2026

Der Stand umfasst weiterhin 43 Pascal-Units und 59 MCP-Werkzeuge. Die 1.2.9-Livediagnose zeigte den eigenen Listenerdescriptor vor Stop als gültig und danach mit Winsock=10038 als geschlossen, obwohl der TCP-Listener unter der ursprünglichen IDE-PID bestehen blieb. Diese Kombination wurde nun durch einen echten vererbenden Kindprozess unter Win32 und Win64 reproduziert: Parent-Stop meldet Erfolg und Port0; bis zum normalen Kindende bleiben LISTEN und Bindfehler10048 erhalten. Danach verschwinden der Listener und der Fremd-Bindfehler.

DAI sperrt und prüft jetzt HANDLE_FLAG_INHERIT für den Listener in DoBeforeBind sowie für akzeptierte HTTP-Sockets in DoConnect. Die installierte Indy-Schnittstelle ruft DoBeforeBind nach AllocateSocket und vor Bind auf. Die Änderung betrifft nur eigene aktuelle Socketbindungen; GStack, fremde Sockets und Prozessstarts werden nicht verändert. [Microsoft dokumentiert Socketvererbung als Standard](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsasocketw); [SetHandleInformation](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-sethandleinformation) kann das Vererbungsflag löschen. Die tatsächliche geerbte Referenz in DelphiLSP.exe ist bislang nicht direkt ausgelesen; dessen Start kurz nach dem IDE-Listener und der isolierte Repro stützen diese Ursache.

## Native Verifikation 1.2.10

| Testreihe | Checks je Win32/Win64 |
| --- | ---: |
| Toolbar, Streaming, Clone-Cleanup, begrenzte Altlastenmigration, gepinnte BPL-Lebensdauer | 1.905 |
| Windows, Parent/Owner-/ToolButtonmetadaten und Sensitivitätsschutz | 152 |
| Protocol, HTTP-/Synchronize-/Reentrancy-/Bindfehlerverträge | 115 |
| Runtime, Start-/Drain-Vertrag und temporäre Einstellungen | 60 |
| ServerLifecycle, statisch mit echtem vererbenden Kindprozess | 538 |
| ServerLifecycle, Hersteller-BPLs mit Kindprozess | 538 |
| ServerLifecycle, zusätzlich initialisierte IndyIP-Host-Packages mit Kindprozess | 541 |
| **Summe je Architektur** | **3.849** |

Insgesamt bestanden **7.698 Checks**. Die sechs Lifecycle-Varianten enthalten 120 vollständige Start/Ping/Stop/Restart-Zyklen und sechs neue Kindprozessfälle. Mit Fix sind Parent-Status0, fehlende LISTEN-Zeile und unmittelbar erfolgreicher unabhängiger Bind bei weiterhin lebendem Kind bestätigt. Alle Testkinder werden über GUID-Events regulär beendet; ChildExit0 und abschließende Portfreigabe sind geprüft. Die vorherige fehlerhafte Variante wurde unter Win32/Win64 als erwarteter Gegenbeweis ausgeführt und regulär bereinigt.

## Toolbar und Livediagnose

Die gespeicherte DebugToolBar enthielt drei namenlose Dropdowns ohne Aktion/Menü plus einen benannten DAI-Button mit dem nicht stabil auflösbaren Actionpfad DAIServerToggleAction.Owner. Der Nutzer bestätigt vier leere Altbuttons unmittelbar hinter dem zuvor letzten Rückkehr-Button. Die Aktion gehört nun dem Besitzer der IDE-ActionList. Native VCL-Streamingtests bestätigen den stabilen Actionpfad. Beim Entfernen werden zusätzliche ToolButtons über die exakte eigene Action-Objektidentität beseitigt, bevor die Action freigegeben wird.

Die einmalige Bereinigung verlangt einen eindeutigen RunUntilReturn-Anchor, eine lückenlose Folge von genau drei oder vier vollständig inerten Stock-TToolButtons und den eigenen aktuellen DAI-Button. Klassenabweichungen, andere Owner, Actions, Menüs, Bilder, Texte, Eventhandler, Tags oder andere Positionen/Anzahlen verhindern die Migration. 28 Fremd-/Abweichungsfälle sind für beide Folgenlängen geprüft, einschließlich eines Nachkommen mit eigenem virtuellem Click-Verhalten. Es werden keine Registrywerte zurückgesetzt oder fremde Toolbaraktionen entfernt.

Die ReadOnly-Fensterinspektion liefert zusätzlich Parent-/Owner-Namen und -Klassen sowie für nicht sensitive ToolButtons Styleenum, Bildindex/-name, vorhandenes Dropdown und tatsächliche Action-Namen/-Klassen. Sensitive Namen/Eltern und DAI-Freigabefenster bleiben geschützt; Inspektion verändert keine Action-/Popup-Verknüpfung.

## Builds und ausstehende Liveprüfung

Release- und Debug-Packages samt nativer Bridge 1.2.10 wurden für Win32 und Win64 erfolgreich gebaut und nach Architektur sowie DLL-/EXE-Typ geprüft. Nach dem vom Nutzer bestätigten IDE-Abschluss waren weder bds.exe/DelphiLSP.exe noch Listener auf Port 7333 vorhanden. Die installierte Debug-BPL wurde ersetzt. Die abschließenden Protokolltests bestanden danach erneut mit 115 Checks je Architektur. Die frische Win32-IDE PID 31876 bestätigte 1.2.10. Beim ausdrücklich gestoppt belassenen Server verschwand die LISTEN-Zeile auf 127.0.0.1:7333, während die IDE und drei DelphiLSP-Prozesse weiterliefen. Nach dem Start waren Listener und HTTP-200-health wieder vorhanden; ide_status bestätigte active=true. Dieser Livezyklus bestätigt die behobene Portfreigabe in der tatsächlichen IDE. Die neue ToolButtoninspektion zeigte jedoch fünf inerte Dropdowns: Die zuvor benannte alte DAI-Schaltfläche wurde nach dem Neustart ebenfalls namenlos. Auch der RunUntilReturn-Button trägt live keinen Komponentennamen, sondern die Action RunUntilReturnCommand. Der bisherige Name-Anchor verhindert damit die Migration; dieser Befund wird in 1.2.11 korrigiert. Der tatsächliche IDE-Packagebuild wird noch geprüft. Die folgenden historischen Prüfstände bleiben erhalten.

# DAI 1.2.9 – Toolbar- und Server-Lifecycle-Prüfung vom 2. Oktober 2026

Der Stand umfasst weiterhin 43 Pascal-Units und 59 MCP-Werkzeuge. Die neue Toolbar verwendet transparente PNG-Serversymbole mit Pause, Startdreieck und Warnung, primär 16×16 sowie weitere IDE-Auflösungen. `ActionList` wird vor `ImageIndex` zugeordnet; dadurch ist der initiale Bildname auch bei Delphis tatsächlicher virtueller Bildliste gesetzt. Die Bildregistrierung nutzt `INTAServices280.AddImage` und einen neuen eigenen Identifikator. Das dafür benötigte `vclimg` gehört zur Delphi-Standardinstallation; es gibt keine GetIt-Abhängigkeit.

## Native Verifikation 1.2.9

| Testreihe | Checks je Win32/Win64 |
| --- | ---: |
| Toolbar, reale Bildlisten und isolierter gepinnter BPL-Unload-/Reload-Vertrag | 376 |
| Protocol, HTTP-/Synchronize-/Reentrancy- und Bindfehlerverträge | 115 |
| Runtime, Startdelegation, temporäre Einstellungen und Drainfehler | 60 |
| ServerLifecycle, statisch | 513 |
| ServerLifecycle, Hersteller-BPLs | 513 |
| ServerLifecycle, Hersteller-BPLs plus initialisierte IndyIP-Host-Packages | 516 |
| **Summe je Architektur** | **2.093** |

Insgesamt bestanden **4.186 Checks** dieser Runde. Die Lifecycle-Tests prüfen pro Variante 20 vollständige Stop/Start-Zyklen mit echtem HTTP-Verkehr, Keepalive, Windows-TCP-Tabelle, unmittelbarem fremdem Wiederbinden und Instanzsperrenwechsel. Die Hersteller-BPL-Varianten bestätigen ihre tatsächlichen Ladepfade und Klassenmodule. Die Hostvariante initialisiert zusätzlich `IndyIPClient`, `IndyIPCommon` und `IndyIPServer` über den echten Delphi-Packageloader. Sie reproduziert den Serververtrag mit diesen Packages, nicht die gesamte Delphi-IDE.

Der echte belegte-Port-Test bestätigt die innere Indy-Exception mit `Winsock=10048`. Bei wartendem HTTP-Synchronize-Aufruf werden parameterloses Start, identisches explizites Start und identisches ApplySettings während Stop abgewiesen. Runtime delegiert auch bei noch `Active=True` an den Server, erhält dessen aktuelle temporäre Port-/Token-Werte und meldet den tatsächlichen Startfehler.

Listenerstop erfolgt auf dem IDE-Hauptthread; anschließend beendet der Hilfsthread die HTTP-Arbeiter, während `WaitFor` Synchronize-Anfragen verarbeitet. Bindings und Instanzsperre werden erst nach dem abgeschlossenen Drain freigegeben. Die Diagnose liest nur die früheren eigenen Socket-Handles und unterscheidet einen lesbaren Listener von einem Winsock-Lesefehler. Ein wiederverwendeter numerischer Handle für denselben Endpunkt kann nicht eindeutig dem alten Listener zugeordnet werden; DAI verweigert den Abschluss in diesem seltenen Fall konservativ und schließt keinen rohen Handle. Die noch vorhandenen Binding-Objekte werden vor ihrer Freigabe auf `HandleAllocated` geprüft.

## Livebefund und ausstehende Wiederholung

In der vorherigen frischen Win32-Sitzung mit DAI 1.2.8 blieb der Listener auf 127.0.0.1:7333 unter PID 27948 nach dem vom Nutzer ausgelösten Stop/Start erhalten. `/health` und MCP-Leseaufrufe antworteten anschließend nicht mehr, während bds.exe weiterhin reagierte. Die Windows-TCP-Tabelle zeigte LISTEN; TIME_WAIT erklärt diesen Befund nicht. Der gleiche Fehler tritt in den isolierten nativen Varianten nicht auf. Die Ursache im tatsächlichen IDE-Host ist deshalb bislang nicht bewiesen.

Die korrigierten 1.2.9-Release- und Debug-Packages samt Bridges wurden für Win32/Win64 gebaut und nach Architektur sowie DLL-/EXE-Typ geprüft. Nach dem vom Nutzer bestätigten IDE-Abschluss waren keine bds-Prozesse und keine Listener auf Port 7333 mehr vorhanden. Die installierte Debug-BPL wurde ersetzt und die frische Win32-IDE unter PID 24604 bestätigte Version 1.2.9 sowie die neuen Symbole. Der Nutzer bestätigte zunächst Stop/Start, die laufende Portüberwachung erfasste dabei jedoch keine Listenerunterbrechung. Beim ausdrücklich gestoppt belassenen Server zeigte der Button inaktiv, während Windows weiterhin einen Listener der IDE meldete; HTTP antwortete nicht mehr. Der nachfolgende tatsächliche Startversuch scheiterte mit Winsock=10048. Die Stopdiagnose bestätigt den eigenen Socket 0xD74 vor Stop als LISTEN auf 7333 und danach als nicht lesbar mit Winsock=10038. Der eigene Descriptor wurde somit geschlossen; das darunterliegende Socketobjekt blieb über eine andere Referenz erhalten. DelphiLSP.exe wurde als Kindprozess derselben IDE rund 350 ms nach dem Listenerstart erzeugt. Socketvererbung wird als gezielte Hypothese geprüft; die genaue Referenz im IDE-Kindprozess ist bisher nicht direkt ausgelesen. In der gespeicherten DebugToolBar stehen außerdem drei namenlose Dropdowns ohne Action/Menu und der aktuelle DAI-Eintrag mit Actionpfad DAIServerToggleAction.Owner; die Symbolbestätigung belegt daher keine vollständige Toolbarbereinigung. Das erneute Erscheinen nach einem tatsächlichen IDE-Packagebuild ist bislang nur im isolierten BPL-Vertrag geprüft. Die folgenden historischen Prüfstände bleiben unverändert.

# DAI 1.2.8 – Erweiterungs- und Liveprüfung vom 2. Oktober 2026

Der aktuelle Stand umfasst 43 Pascal-Units und 59 MCP-Werkzeuge. Der live gelesene Katalog der Win32-IDE entspricht exakt dem nativ exportierten Katalog. Debug- und Release-Packages sowie die native Bridge wurden für Win32 und Win64 gebaut; nach dem Liveabschluss wurden die korrigierten Endfassungen erneut für beide Architekturen gebaut.

## Native Verifikation 1.2.8

Der installierte `dai-delphi-ide`-Skill entspricht bytegleich dem nativen Delphi-Generator. YAML, 48 genannte Werkzeugnamen, 15 Argumentverträge und zwei Beispiele sind mit dem Katalog der 59 Werkzeuge abgeglichen. Die Skillmigration erhielt die Fingerabdrücke aller 14 geprüften Clientkonfigurations-/Ownership-Pfade unverändert. Die abschließende statische Prüfung bestätigt Quellformat, Version, Packageverweise und fehlende GetIt-Abhängigkeiten; Diffprüfung und aktualisiertes SHA-256-Manifest sind sauber.

Die folgenden Prüfungen dieser Runde liefen jeweils unter Win32 und Win64 mit isolierten Fixtures. Sie verändern keine tatsächlichen Clientkonfigurationen, IDE-Packages oder Registrierungen.

| Native Testreihe | Checks je Win32/Win64 |
| --- | ---: |
| Test.Options: tatsächlicher Optionsframe und aktuelle UI-/Katalogverträge | 199 |
| Test.Toolbar: Einbindung, Serveraktionen und Lebensdauer der IDE-Toolbar | 122 |
| Test.IDEControl: Fensteraktionen und verzögerter normaler Schließauftrag | 81 |
| Test.Protocol: HTTP-/MCP- und Antwortverträge | 107 |
| Test.Messages: Produktionsleser, native BPL-ABI, Indizes, Spalten und Ausgabegrenzen | 235 |
| Test.Stack: OTA-Stackauswahl, Frames und Ausgabegrenzen | 214 |
| Test.Threads: OTA-Prozess-/Threadauswahl und globale Begrenzung | 276 |
| Test.ToolDispatch: tatsächlicher Fensterzweig und Berechtigungsprüfungen | 688 |
| **Neue beziehungsweise erweiterte Testreihen** | **1.922** |
| Test.CodeInsight: reguläre Callback-/Positions-/Shutdown-Prüfungen | 794 |
| Test.CodeInsight: isolierte BPL-Abschluss-/Latecallback-Prüfungen | 25 |
| **Summe dieser Runde je Architektur** | **2.741** |

Insgesamt bestanden **5.482 Checks**. Die Code-Insight-Reihe umfasst dabei weiterhin den tatsächlichen isolierten BPL-Pfad für Package-Abschluss und verspätete Rückrufe. Die Meldungstests kompilieren den vollständigen Produktionsleser gegen ein eigenes, isoliertes Producer-BPL mit den verifizierten Methodensignaturen; sie ersetzen keine Liveprüfung der Hersteller-BPL.

Der abschließende Review fand eine unterschiedliche Normalisierung des Fensterschließbefehls zwischen Berechtigungsprüfung und Ausführung. Der Dispatch normalisiert jetzt einmalig vor beiden Prüfungen und übergibt denselben Wert an die Fenstersteuerung. `Test.ToolDispatch` kompiliert den unverändert extrahierten Produktionszweig sowie die echten `ArgumentString`-/`RequirePermission`-Routinen gegen die tatsächliche Types-Unit und isolierte Berechtigungs-/Fenster-Doubles. Unter beiden Architekturen verlangen auch `CLOSE`, umgebende Leerzeichen und Steuerzeichen weiterhin `pcExecute`; eine Ablehnung verhindert jeden Fenster- und Schließaufruf. Dieser Test prüft den begrenzten Dispatchvertrag, nicht die gesamte OTA-/HTTP-Integration. Die Liveprüfungen wurden vor dieser abschließenden Dispatchkorrektur ausgeführt; die neu gebauten Endfassungen sind dafür nativ geprüft.

## Live in der Win32-IDE

Die laufende IDE bestätigt Version 1.2.8 und 59 Werkzeuge. Ein erfolgreicher Compilerbuild lieferte 34 tatsächlich vorhandene Buildlogzeilen. Das Debugger-Ereignislog lieferte zunächst 49 Zeilen. Für beide Quellen bestanden die Auswahl eines einzelnen Originalindex und ein Zeichenlimit von drei Zeichen.

Am Haltepunkt wurden vier Threads gelesen. Die ausdrückliche Auswahl über die Windows-Prozess-ID funktioniert; `maximum_threads: 2` begrenzt die insgesamt zurückgegebenen Threads. Die Enumeration mehrerer realer Debuggerprozesse und der Betrieb in der Win64-IDE sind bislang ausschließlich durch native Fixtures abgedeckt.

Der Stack enthielt zehn Frames; drei davon wurden mit `Checkpoint`, `Tick` und `Vcl.Timer` gelesen. Auch `maximum_characters: 3` funktioniert. Bei der echten Timerexception wurde der IDE-Dialog über `BreakButton` angehalten. Der Stack lieferte fünf von zehn Frames einschließlich `RaiseException` und der eigenen PAS-Datei in Zeile 47; die Zustände meldeten Exception beziehungsweise angehaltenen Thread. Die Ereigniszeile mit „DAI Testexception – Grüße“ erschien asynchron verzögert unter Originalindex 50. Die Logabfrage behauptet daher keine synchrone Vollständigkeit unmittelbar nach einem Debuggerereignis.

Fortsetzen und `project_stop` waren erfolgreich; anschließend waren keine Debuggerprozesse oder Testhaltepunkte mehr vorhanden. Minimieren, Wiederherstellen und Hintergrundplatzierung des IDE-Fensters funktionieren. Windows lehnte die Vordergrundanforderung ab; die Antwort meldete dies korrekt mit `accepted: false`.

## Verwendete Schnittstellen und Grenzen

Die installierten öffentlichen ToolsAPI-Interfaces stellen Gruppenmetadaten und Benachrichtigungen bereit, aber keine allgemeine Enumeration vorhandener Build- oder Ereignislogzeilen. DAI verwendet hierfür den konkreten VCL-Adapter für Delphi 13 / BDS 37: bekannte Logforms und Baumkontrollen, verifizierte Exporte der bereits geladenen `vclide370.bpl` und veröffentlichte Header-/Spalteneigenschaften über klassisches RTTI. Klassenherkunft und Exporte werden geprüft; Nodes bleiben opaque Handles. Private Objekt- oder Node-Layouts werden nicht nachgebildet. Das Lesen verändert weder Tabwahl, Filter, Auswahl noch Loginhalt und benötigt keine GetIt-Abhängigkeit.

Die Logantworten erhalten Originalindizes und Gesamtzahl. Standardmäßig werden höchstens die letzten 50 Zeilen gelesen; Anzahl, Textbudget, Spaltenvollständigkeit und kooperatives Zeitlimit sind begrenzt und werden ausgewiesen. Ein einzelner fremder Getter kann nicht während seines Aufrufs unterbrochen werden. Nicht erstellte oder nicht unterstützte Logkontrollen liefern einen erklärten unavailable-Befund mit begrenzten Adapterdetails.

Die öffentliche OTA-Stackschnittstelle liefert für die verwendeten Framegetter weder Modulname noch Instruktionsadresse. `module` und `address` bleiben deshalb ausdrücklich `null`; es werden keine Werte aus privaten Debuggerstrukturen abgeleitet.

Der gezielte Compilerfehler-Logtest lieferte 36 Buildlogzeilen einschließlich E2003 in der eigenen PAS-Datei, Zeile 38, und F2063. DAI bestätigte den tatsächlichen `TProgressForm`-Dialog über den Button mit Name `CancelButton` und Caption `OK`; die Buildantwort blieb korrekt `succeeded: false`. Nach Wiederherstellung und Speichern der Original-PAS-Datei war der erneute Build erfolgreich.

Nach einer echten LSP-Definitionsabfrage wurde die Testsitzung über `ide_window_control(action: close)` geschlossen. Die vollständige HTTP-Antwort mit `accepted: true` und `close_pending: true` traf vor der Beendigung ein; PID 6920 endete innerhalb des Beobachtungsfensters. Es blieben weder IDE noch Testanwendung aktiv, und im Windows-Anwendungsprotokoll waren keine zugehörigen bds-Absturzereignisse vorhanden. Die DAI-Schaltfläche wurde zuvor als sichtbarer `DAIServerToolButton` direkt unter dem bestehenden `DebugToolBar` gelesen. Die oben beschriebenen Liveprüfungen gelten für Win32; Win64 und echte Mehrprozess-Debuggersitzungen sind bisher nativ geprüft.

Die ausführbaren Prüfungen liegen unter `Scripts/Test.Options.ps1`, `Test.Toolbar.ps1`, `Test.IDEControl.ps1`, `Test.Protocol.ps1`, `Test.Messages.ps1`, `Test.Stack.ps1`, `Test.Threads.ps1`, `Test.ToolDispatch.ps1` und `Test.CodeInsight.ps1`. Isolierte Ausgaben liegen in den zugehörigen Verzeichnissen unter `Build/Tests`. Die folgenden historischen Prüfstände bleiben unverändert.

# DAI 1.2.7 – Skill- und IDE-Prüfung vom 1./2. Oktober 2026

Der installierte Skill entspricht dem nativen Delphi-Generator und den 55 Werkzeugschemas. YAML, 44 genannte Werkzeuge, 11 Argumentverträge und zwei Beispiele geprüft. Alte Kai-Skills wie beauftragt entfernt. Letzte native Skillmigration mit Sicherung: 14 Konfigurations-/Ownership-Pfade unverändert, davon neun vorhandene Dateien. Keine Zugangsdaten ausgegeben.

## Ergebnis und Korrekturen

Live in Win32 geprüft: Referenzsuche/Interfaceansicht, offene Editorpuffer, hashgeschützte Änderungen, OTA-VCL-Projektanlage, Projekt-/Unit-/Dateiverwaltung, Designer, Builds und Debugger mit bedingtem Haltepunkt, Einzelschritten und Timer-Exception. Eigene Testanwendung beendet, Haltepunkte entfernt, Quellen wiederhergestellt und gespeichert.

Der finale Unicode-DFM-Rundlauf funktioniert: `save=false`, Designerwert „DAI Designer - Grüße“, erneuter Textwechsel bei geänderter DFM, PAS-Datenträgerbytes unverändert. Native Formularwechsel werden asynchron begrenzt abgewartet; echte ungespeicherte PAS-Änderungen werden vorab geschützt. Der Guard vergleicht vollständigen Quelltext mit der dekodierten Datei, statt das gemeinsame Modified-Flag auszuwerten. Unicode-Formularstrings werden als `#nnn` normalisiert; Antwortsha256 beschreibt den tatsächlichen Puffer.

Code Insight findet `TForm` tatsächlich in `Vcl.Forms.pas` (Zeile 1252). Der HTML-Marker liefert einen ehrlichen unavailable-Befund. Jede Anfrage besitzt einen eigenen Empfänger und Callbackbroker; dauerhaftes Shutdown sperrt neue Anfragen. Verspätete Rückrufe benötigen keine finalisierten globalen Sperren. Callbackcode bleibt gemappt: nach Code Insight erfordert Package-Austausch einen IDE-Neustart, MCP-Stop/Start bleibt möglich. Hover löst Editor/View/QueryContext sofort auf dem Hauptthread. Eigene Logcallbacks werden gezielt entfernt; reentranter oder fehlgeschlagener Runtime-Drain gibt den Server nicht voreilig frei.

Die drei neuen VCL-Dialogwerkzeuge wurden praktisch geprüft: echter fehlgeschlagener Build per OK bestätigt und `succeeded=false` erhalten; nach Wiederherstellung Build erfolgreich. Debugger-Exception per BreakButton/Anhalten unterbrochen, fortgesetzt und beendet. InputQuery über Form.ModalResult=2 geschlossen; 0 wird abgewiesen. Tokens prüfen unveränderte Identität/Titel/Text/Buttonzustand und verfallen nach 30 Sekunden. DAI-Freigaben/WinAPI-Dialoge und Inputtexte sind ausgeschlossen.

## Verifikation

- Win32/Win64 jeweils 2.838 native Prüfungen, insgesamt 5.676 bestanden. CodeInsight umfasst je 794 reguläre und 25 echte isolierte BPL-Prüfungen für `UnloadPackage → Latecallback → InitializePackage`; unabhängige Lebensdauerprüfung ohne konkreten Befund.
- Release und Debug: Packages/Brücken für Win32/Win64 gebaut und PE-/DLL-/EXE-Typ geprüft. Release-Brücken HTTP-Mocktests; finale Debug-Win32-Brücke tatsächlich mit der IDE verbunden und 55 Werkzeuge gelesen.
- Statische Prüfung: 38 Pascal-Units, 55 Werkzeuge, Version 1.2.7, Quellformat und Diff sauber. Manifest aktualisiert. Bekannte W1002/H2077 enthalten keine Buildfehler; keine GetIt-Abhängigkeit.

## IDE-Abschluss und Grenzen

Der gemeldete Stack zeigt `TLSPPascalManager.GetAllOtherSearchPaths` während Projektabbau über `ModuleRemoved`/`BeforeDestruction`/`WindowCloseQuery`; DAI-Frames fehlen. Für die anschließende Null-AV liegt kein weiterer Stack vor. Ein zuvor verlorener unsaved PAS-Puffer verursachte F1026 und kann interne Projekt-/LSP-Assoziationen beschädigt haben; die konkrete Absturzursache ist nicht bewiesen.

Zwei anschließend frisch gestartete IDE-Sitzungen schlossen laut Nutzer ohne Exception, zuletzt mit allen Abschlusskorrekturen. Das ist ein erfolgreicher Wiederholungstest, kein allgemeiner Beweis zur ursprünglichen LSP-Ursache. Delphi ist nach der abschließenden Prüfung geschlossen. Eine frühe Shutdown-Zulassung für alle OTA-Modulreferenzen bleibt ein gesonderter Auditbefund; kein gleichzeitiger eigener Request ist für den ursprünglichen Abschluss belegt.

Win64-IDE und alle realen Clientregistrierungen wurden nicht live verändert; native Fixtures und Package-Proben bestehen. WinAPI-MessageBox-Aktionen wurden nicht automatisiert. ReadOnlyPolicy liest HKCU ohne Änderungen. Persönliche unversionierte Dateien und Referenzquellen bleiben erhalten.

Der ausführliche Nachweis liegt im Codex-Arbeitsverzeichnis als `DAI-Skilltest-2026-10-01.txt`; Stack/Analyse, Live-JSON und finale Buildlogs liegen unter `work/skill-validation`. Ältere Prüfberichte folgen unverändert.

# DAI 1.2.6 – Prüfbericht vom 1. Oktober 2026

## Starten mit den aktuellen Optionsfeldern

Der bisherige Startknopf nutzte ausschließlich TDAISettings.Instance und ignorierte noch nicht übernommene Port-/Token-Eingaben.
Er liest jetzt beide Eingabefelder direkt und übergibt sie als temporäre Startkonfiguration an Runtime und MCP.Server.
Starten/Stoppen wirkt sofort, ohne den Optionsdialog zu schließen. Nach einem belegten Port lässt sich im selben Dialog der nächste versuchen.
Speichern oder Registrieren übernimmt die Werte dauerhaft; Abbrechen macht einen bereits ausgeführten manuellen Start/Stopp nicht rückgängig.
Starten schreibt weder Registry noch Berechtigungen oder Clientregistrierungen. Die Statusanzeige meldet den tatsächlich gebundenen Port.
ide_status.port zeigt den aktiven Port; configured_port nennt zusätzlich den übernommenen Port.

Der Server hält eigene Port-/Token-Werte, die während laufender HTTP-Worker unverändert bleiben.
Settings-Zuweisungen ändern keine aktive Authentifizierung; ApplySettings vergleicht beide Werte und startet bei Änderungen unter derselben Instanzsperre neu.
Bei sauberem Stop oder aufgeräumtem Bindefehler werden die Laufzeitwerte zurückgesetzt. Eine unvollständige Indy-Bereinigung gibt die Instanzsperre nicht voreilig frei.
Gemeinsame Validierung prüft Port 1024–65535 und nichtleeren Token ohne Steuerzeichen. Der Optionsdialog validiert vor dem Schließen bei Speichern.
Ein Wechsel zwischen globalen und Projektberechtigungen erhält ungespeicherte Serverfelder.

## Stoppen während einer IDE-Anfrage

Indy-Shutdown auf dem Hauptthread konnte auf einen HTTP-Worker warten, der seinerseits in TThread.Synchronize auf die IDE wartete.
Deactivate führt den Shutdown nun in einem eigenen Thread aus. Der Hauptthread wartet über TThread.WaitFor und verarbeitet dabei Synchronize-Anfragen.
Es wird keine allgemeine Application.ProcessMessages-Schleife verwendet. Fehlerdaten werden vor dem Freigeben des Threads kopiert.
Während der Bereinigung werden reentrante Start-/Stop-Versuche blockiert; Token und Instanzsperre bleiben bis zum vollständigen Shutdown erhalten.

## Verifikation 1.2.6

| Native Testreihe | Checks je Win32/Win64 |
| --- | ---: |
| Test.Protocol: echte HTTP-/MCP-, Instanz-, Auth-, temporäre Settings- und Shutdown-Regressionen | 99 |
| Test.Options: tatsächlicher VCL-Optionsframe mit DFM, echten Edit-/Button-/Scope-/Statusaktionen | 73 |
| **Summe** | **172** |

Alle 344 Prüfungen bestanden. Die Protokolltests nutzen echte lokale Listener und eine eigene GUID-Instanzsperre sowie synthetische Settings/Tools.
Die UI-Tests kompilieren den tatsächlichen Produktionsframe; seine externen Dienste sind isolierte In-Memory-Stubs und das Hostfenster bleibt verborgen.
Sie bestätigen aktuelle Eingaben, Trim, Scopewechsel, Start/Stop, tatsächlichen Statusport und ausbleibende Save-/Apply-/Rechte-/Registrierungswrites beim Start.
Der Shutdowntest erzwingt eine wartende Synchronize-Anfrage und prüft Callback auf dem Hauptthread, vollständigen Stop und anschließende Leaseübernahme.
Ein reentranter Start aus dem Callback wird abgewiesen; der begrenzende Test-Watchdog musste nicht eingreifen.

Release-Package und Bridge für Win32/Win64 erfolgreich gebaut; PE-Architektur sowie DLL-/EXE-Typ aller vier Ausgaben geprüft.
Statische Prüfung: 38 Pascal-Units, 52 MCP-Werkzeuge, Version 1.2.6 und Quellformat. git diff --check sauber; Manifest aktualisiert.
Keine neue GetIt-Abhängigkeit; die bekannten W1002-/H2077-Meldungen enthalten keine Buildfehler.
Unveränderte Registrierung-/Source-/Debugger-Tests wurden nicht wiederholt; vorherige Ergebnisse stehen im historischen Bericht.

Die laufende Win32-IDE (PID 19448) lädt noch Build\Win32\Debug\Bpl\DAI.bpl; die neuen Release-Packages liegen unter Build\Win32/Win64\Release\Bpl.
Kein Neustart oder Hot-Unload vorgenommen. Die tatsächliche IDE verwendet die Korrektur erst nach Neubuild/Neuladen ihres Packages.
Benutzeränderungen an DAI.dai.permissions.json und persönliche, unversionierte Dateien wurden nicht bearbeitet.

## DAI 1.2.5 – Prüfbericht vom 1. Oktober 2026

### Ergänzung: Delphi-Multiline-Strings

18 Vorlagen mit mindestens drei Text- oder bisherigen Literalzeilen verwenden native Delphi-Textblöcke:
Skill und Codex-TOML, Hermes-YAML, fünf Unit-/Form-/Projektvorlagen, drei Projektbestätigungen und sieben längere MCP-Eingabeschemas.
TEXTBLOCK CRLF steht einmal im Header jeder betroffenen Unit; MCP.Tools verwendet zusätzlich die JSON-Dekoration.
Format setzt dynamische Werte ein. Die bisherigen Inhalte, Einrückungen und finalen Zeilenumbrüche bleiben erhalten.
Kurze/optionale Textsegmente sowie Testorakel für Mischzeilenenden, Quotes und unvollständige Sourcen bleiben explizit.

- Native Vorher/Nachher-Vergleiche: je Win32/Win64 32 OTA- und 24 TOML-/YAML-Vergleiche, inklusive Unicode, Apostrophen und Prozentzeichen.
- Generierter Skill mit 7.267 UTF-8-Bytes entspricht bytegenau vorherigem Generator und installierter Datei; keine erneute Registrierung nötig.
- Alle 52 nativ exportierten Werkzeugobjekte inklusive Schemas/Annotations bleiben in Win32/Win64 bytegenau identisch zum bisherigen Export.
- Alle 38 aktuellen PAS-Units bestehen unter Win32/Win64 den nativen Ganzdatei-Schreibguard und Interfacefilter, einschließlich Textblock-Vorlagen.
- Je 144 bestehende Registrierungsprüfungen unter Win32/Win64 erfolgreich; Release-Package und Bridge für beide Architekturen gebaut/geprüft.
- Der statische Prüfer maskiert 3/5/7-Quote-Textblöcke, ignoriert darin vermeintlichen Pascalcode und dekodiert JSON-Schema-Blöcke; 32 lokale Checks erfolgreich.

Compilerprobe dcc32/dcc64 37.0: NATIVE ist der Standard und liefert unter Windows CRLF, auch bei LF in der Probe-Quelldatei.
TEXTBLOCK DEFAULT ist ungültig (E1030). Die Schlussquotes müssen auf einer eigenen Zeile stehen (inline: E2658).
Der unmittelbar vorhergehende Zeilenumbruch gehört nicht zum Wert; ein finaler CRLF erfordert eine zusätzliche leere Textblockzeile.

Die aktuelle DAI.dproj hatte bereits vor dieser Änderung keine Versionsressource aktiviert; diese Projekteinstellung bleibt erhalten.
Die Versionsprüfung prüft Datei-/Produktversionen weiterhin bei aktivierter VerInfo_IncludeVerInfo-Einstellung.
Die MCP-/Produktversion bleibt 1.2.5; der Refactor ändert keine Werkzeugschnittstellen oder Clientdateien.

### DAI-Dateinamen und aktuelle Migration

Der verwaltete Skill heißt dai-delphi-ide und liegt unter %USERPROFILE%\.agents\skills\dai-delphi-ide\SKILL.md.
SKILL.md bleibt als vorgeschriebener Einstiegsdateiname bestehen; Verzeichnis und YAML-Name kennzeichnen DAI.
Eigene Verwaltungsdateien (.dai-registration.json), Sicherungen/Temporärdateien (.dai-GUID.bak/.tmp) und DAI.McpBridge.exe tragen bereits DAI im Namen.
Gemeinsame Clientdateien wie config.toml, .claude.json, settings.json, mcp.json und config.yaml behalten ihre vorgeschriebenen Namen.

Die öffentliche native Routine TDAICodexRegistration.MigrateSkillFiles aktualisiert ausschließlich den Skill.
Sie wurde als frisch kompilierter Delphi-Code jetzt gegen die vorhandene Benutzerregistrierung ausgeführt:
neuer Skill geschrieben, interne Metadaten angepasst, alter verwalteter Einstieg entfernt, ursprüngliche Datei mit .dai-Sicherung erhalten.
Die vorhandenen fünf Clientkonfigurationen und zugehörigen Verwaltungsdateien wurden vor/nach der Migration bytegenau verglichen und blieben unverändert.
Die installierte Datei entspricht bytegenau dem aktuellen nativen Delphi-Generator. Es gab keine bestehenden Skill-Pfadverweise in den Clientkonfigurationen.

Registrieren, Status und Deregistrieren erkennen beide alten delphi-ide-Skillpfade unter USERPROFILE und APPDATA.
Nur Dateien mit DAI-Verwaltungsmarker werden migriert oder entfernt; fremde Ziel-Skills blockieren vor Änderung der Clientkonfiguration,
fremde alte Dateien und Unterordner bleiben erhalten. MigrateSkillFiles schreibt weder aktuelle/alte Clientkonfiguration noch DAI-Settings.

### Verifikation 1.2.5

- Je 144 native Registrierungs-/Parser-/SafeFile-Prüfungen unter Win32/Win64 erfolgreich (98 bestehende und 46 neue Migrationsprüfungen).
- Je 67 native HTTP-/MCP-Protokoll- und Versionsprüfungen unter Win32/Win64 erfolgreich; insgesamt 422 Checks in diesen Testreihen.
- Release-Package und native Bridge für Win32/Win64 erfolgreich gebaut; Architektur sowie DLL-/EXE-Typ aller vier PE-Dateien geprüft.
- Generierter Skill: YAML und Name dai-delphi-ide gültig; 41 Werkzeugnennungen, zwei JSON-Beispiele und elf Argumentverträge gegen 52 Schemas geprüft.
- Aktuelle Live-Skillmigration mit der echten Produktionsroutine erfolgreich; Sicherung und unveränderte Clientdateien als Receipt dokumentiert.
- Statische Prüfung: 38 Pascal-Units, 52 MCP-Werkzeuge, Versionen, Packageverweise, Quellformat; git diff --check sauber und Manifest aktualisiert.

Unveränderte SourceView-/SourceSearch-/Editor-/ReadOnly-/Fenster-/Instanz-/Sessiontests wurden nicht wiederholt; ihre vorherigen Ergebnisse stehen unten.
Die bekannte W1002-/H2077-Hinweisliste bleibt ohne Buildfehler. Es gibt keine neue GetIt-Abhängigkeit.

Die laufende IDE verwendet noch das ältere Package. Die zukünftige Namensvergabe bei Registrieren in der IDE greift nach Laden des neu gebauten Packages;
die jetzige Benutzer-Skillmigration wurde bereits unabhängig davon als nativer Delphi-Code ausgeführt. Kein Neustart/Hot-Unload der IDE vorgenommen.

### Historischer Prüfstand 1.2.4

Die folgenden Beobachtungen und damaligen Skillnamen beschreiben den vorherigen Stand.

#### Änderungen und Verhalten

source_search, file_read und reference_file_read nehmen interfaces_only entgegen, mit Standard true in Schema und Ausführung.
Bei erkannten .pas-Units endet die Textansicht vor dem echten implementation-Schlüsselwort. Das gemeinsame Delphi-Lexing ignoriert
Kommentare, Direktiven, Strings, Multiline-Strings, escaped identifiers und längere Unicode-Bezeichner. Zeilen und Spalten bleiben erhalten.
Andere Dateitypen und Inhalte ohne erkannten Unit-/Interface-Kopf werden beim Lesen nicht verändert. Mit false bleibt vollständiger Quelltext verfügbar.

Suchtreffer und Auszüge entstehen nach der Filterung, für Disk und Editor-/Designer-Snapshots gleichermaßen.
Der Suchadapter liest Snapshots intern ausdrücklich vollständig, damit false nicht versehentlich nur Interfaces durchsucht.
ReadFile berechnet sha256/original_characters weiterhin über den vollständigen aktuellen Inhalt. implementation_omitted, view_characters,
content_complete und sha256_scope unterscheiden die Ansicht vom vollständigen Schreibinhalt; truncated bleibt das Zeichenlimit.

WriteFile prüft .pas-Inhalte vor Editor-/Datenträgermutationen auf echten Unit-Kopf, interface, implementation und abschließendes end.
Der Test einer versehentlich zurückgeschriebenen Interfaceansicht mit gültigem Fullhash bestätigt Ablehnung vor Writer/Save und unveränderten Puffer.
Die Strukturprüfung erlaubt leere Interfaces und ist kein vollständiger Delphi-Parser oder Präprozessor.

LSP-/Code-Insight-Zugriff wurde am installierten ToolsAPI-Quellbestand nachgeprüft. Der vorhandene Dienst file_diagnostics liest IOTAModuleErrors.GetErrors;
die Antwort nennt jetzt Diagnosequelle und unbekannte Aktualität. Die öffentliche API bietet keine gefundenen hypothetischen Textdiagnosen und keine
Versionsbindung der gemeldeten Fehler. Eine leere Liste ist keine Bestätigung einer abgeschlossenen Prüfung des neuesten Texts.

#### Verifikation 1.2.4

Release-Package und native Bridge für Win32/Win64 erfolgreich gebaut. PE-Architektur und DLL-/EXE-Typ aller vier Ausgaben geprüft.
Keine neue GetIt-Laufzeitabhängigkeit; bekannte W1002/H2077-Hinweise ohne Buildfehler.

| Native Testreihe | Checks je Win32/Win64 |
| --- | ---: |
| Test.SourceView: lexikalischer Interfacefilter und Vollständigkeitsguard | 365 |
| Test.SourceSearch: Disk-/Pufferfilter, Auszüge, Koordinaten und bestehende Suchregressionen | 140 |
| Test.EditorWrite: echter Datei-/Editor-Dienst, View-/Hash-Verträge und Guard vor Mutationen | 86 |
| Test.SearchService: echte OTA-Suchintegration mit isolierten Diensten und vollständigen Snapshots | 123 |
| Test.ReadOnlyPolicy: Schreibschutz und Priorität vor Strukturprüfung | 51 |
| Test-ClientRegistration: Skill-/Registrierungs-/Parser-/Sicherungsregressionen | 98 |
| Test.Protocol: HTTP-/MCP- und Versionsregressionen | 67 |
| **Summe** | **930** |

Alle 1.860 Checks erfolgreich. Die unveränderten Fenster-/SourcePaths-/Instanz-/Sessiontests wurden diesmal nicht wiederholt;
ihre früheren Ergebnisse bleiben unten dokumentiert. Isolierte OTA-Doubles ersetzen keinen Live-IDE-Test.

Skill aus dem aktuellen Delphi-Generator nativ exportiert, gegen die aktuelle Toolregistry validiert und mit Backup installiert.
YAML gültig, 41 Werkzeugnennungen, zwei JSON-Beispiele und elf dokumentierte Argumentverträge geprüft; alle drei Interface-Defaults und explizites false geprüft.
Die installierte Datei entspricht bytegenau dem nativen Export. Statische Prüfung: 38 Pascal-Units, 52 Werkzeuge, Referenzen, Versionen und Quellformat;
git diff --check sauber, Manifest aktualisiert.

#### Praktischer Stand

Die laufende Win32-IDE verwendet noch das ältere Debug-Package. Die neue Release-Version wurde nicht geladen; Interfacefilter, PAS-Schreibguard
und neue Diagnosemetadaten sind deshalb noch nicht in dieser IDE live geprüft. Das ungespeicherte Testprojekt bleibt erhalten.
Compilerprüfungen, isolierte Tests und aktuelle ToolsAPI-Quellanalyse sind erfolgreich; für die neuen Funktionen ist das Laden des neuen Packages erforderlich.

#### Historischer Prüfstand 1.2.3

Die folgenden Ergebnisse beschreiben den vorherigen Stand. Die früheren Einschränkungen zum Datei-Symlinktest betreffen eine unveränderte Prüfung;
in 1.2.4 wurde keine blockierte Aktion erneut versucht.

##### Aktueller Stand

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

##### Aktuelle Verifikation

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

##### Grenzen und Live-Stand

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

##### Historischer Prüfstand 1.2.2 und Win32-Live-Test

Die folgenden Zahlen und Beobachtungen beziehen sich auf den früheren Stand 1.2.2.

###### Änderungen seit 1.2.1

- Win32 und Win64 im DPROJ aktiviert, getrennte Build-Ausgaben und PE-Prüfung für Package/Bridge in beiden Architekturen.
- Eigene Delphi-Instanzsperre: ein aktiver DAI-Server je Windowsbenutzer, unabhängig von Port, IDE-Architektur und Delphi-Version.
- Die erste erfolgreiche Serverinstanz übernimmt. Nach sauberem Stop oder Prozessende kann eine andere IDE manuell übernehmen.
- Start-/Stop-Schaltflächen in den DAI-Optionen; Autostart gilt nur beim Laden des Packages. Übernehmen der Optionen bewahrt den manuellen Laufzustand.
- Portänderungen halten die Sperre durch den internen Neustart. Fehlgeschlagene Starts geben sie nach erfolgreicher Bereinigung frei;
  unvollständige Listenerbereinigung hält die Sperre und verlangt einen IDE-Neustart.
- ide_status nennt aktive IDE, Architektur, PID, EXE, BPL und den zur Architektur passenden Package-Registrierungsschlüssel.
- Sessions, Clientregistrierungen, Skill-Metadaten, Editor-/Projektzugriffe, Designerinspektion und Debuggerwerkzeuge bleiben enthalten.

###### Verifikation

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

###### Installation und praktische Grenzen

32-Bit-IDE: bin\bds.exe, Win32-BPL, HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages.
64-Bit-IDE: bin64\bds.exe, Win64-BPL, HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Known Packages x64.
Die Bridge muss jeweils neben dem BPL liegen. Beide IDE-Architekturen teilen im selben BDS-Benutzerprofil die DAI-Einstellungen.
Andere Delphi-Versionen brauchen ein mit ihrer Toolchain gebautes Package; die Instanzsperre bleibt dabei gleich, API-Kompatibilität ist hier nicht geprüft.

Die Release-BPLs wurden beim Build nicht in eine laufende IDE geladen. Der nachfolgende Live-Test verwendete das bereits geladene Win32-Debug-Package
(siehe unten). Die sichtbare DAI-Optionsseite, DFM-Bearbeitung und die Win64-IDE brauchen weiterhin einen IDE-Praxistest.
Echte Clientkonfigurationen, Package-Registrierungsschlüssel und GetIt-Installationen wurden durch diese Prüfungen nicht verändert.
Die bekannten Compilerhinweise W1002 zum Windows-Flag und H2077 zum initialen YAML-Ergebniswert bleiben; keine Buildfehler.

Ressourcen- und Prompt-Endpunkte sowie eine gemeinsame Toolregistry sind dokumentierte Ideen und noch nicht implementiert.

###### Nachfolgender Live-Test in der 32-Bit-IDE

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
