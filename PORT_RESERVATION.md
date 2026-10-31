# Gemeinsame Portverwaltung

DAI kann Ports optional mit anderen Programmen auf demselben Windows-Rechner
abstimmen. Die Verwaltung ist eine dauerhafte, kooperative Vormerkung; sie
benötigt keinen Windows-Dienst und ersetzt nicht das Binden des Sockets.
Andere Programme müssen dieses Format und dieselbe Sperre selbst unterstützen.

## Verzeichnis und Dateien

Das Verzeichnis ist FOLDERID_ProgramData\h5uPortReservation\. Der ProgramData-Pfad
wird über Windows ermittelt; C:\ProgramData\ ist nur ein Beispiel. Alle
folgenden Dateien liegen unmittelbar in diesem Verzeichnis:

    .DAI
    .FirefoxMCP
    S-1-5-21-111-222-333-1001_Besitzer
    S-1-5-21-111-222-333-1002_Anna

Dateien mit führendem Punkt sind Anwendungsbeschreibungen oder temporäre
Dateien. Eine Benutzerdatei beginnt mit der Windows-Benutzer-SID, gefolgt von
einem Unterstrich und einem lesbaren Benutzernamen. Die SID stammt aus dem
aktuellen Windows-Prozesstoken. Bei der Suche nach der eigenen Datei wird nur
die vollständige SID einschließlich des folgenden Unterstrichs verglichen;
der Namensteil darf nach einer Konto-Umbenennung veraltet sein. Mehrere Dateien
für dieselbe SID sind ein Fehler. Der Dateiname ist keine Sicherheitsprüfung:
Vor einer Änderung prüft DAI zusätzlich den tatsächlichen Dateibesitzer.

Texte sind UTF-8, lesbar mit oder ohne BOM. Leere Zeilen und Zeilen, deren
erstes Nichtleerzeichen # ist, sind Kommentare. Eine Portzeile besteht
aus einer dezimalen Zahl, genau einem Tabulator und einer Anwendungskennung:

    # Benutzer: Besitzer
    7331<TAB>DAI:dai
    17331<TAB>DAI:dai_bds37_0
    38477<TAB>FirefoxMCP:http

<TAB> steht im Beispiel für einen echten Tabulator. Kennungen enthalten
ASCII-Buchstaben, Ziffern, Unterstrich, Minus, Punkt oder Doppelpunkt. Der
Port muss zwischen 1 und 65535 liegen; DAI wählt nur Ports ab 1024. Eine
Portnummer darf in der gesamten Verwaltung nur einmal vorkommen, unabhängig
von Anwendung, Benutzer, Transport oder Adresse. Das ist bewusst konservativ.
Dieselbe Anwendungskennung darf vorübergehend mehrere verschiedene Ports
besitzen, damit ein alter Port bei einer Umstellung nicht vorzeitig für
andere freigegeben wird. Alte Einträge werden nur ausdrücklich freigegeben.

Alle teilnehmenden Anwendungen müssen alle Benutzerdateien berücksichtigen,
fremde Zeilen und Kommentare erhalten und unbekannte Kennungen tolerieren.
Eine unlesbare oder fehlerhafte Benutzerdatei und doppelte Portnummern
verhindern eine neue Vergabe; sie gelten nicht als freie Ports. DAI liest
höchstens 4 MiB je Datei und 65.536 Zeilen je Benutzerdatei.

## Anwendungsbeschreibung

Die erste Zeile ist ein lesbarer Name; danach folgen Name=Wert-Zeilen.
DAI legt .DAI bei Bedarf an und überschreibt eine vorhandene Datei nicht:

    Delphi AI
    Schema=1
    StartPort=17331
    MaxAnzahl=100
    Protokoll=TCP
    BindAdresse=127.0.0.1

StartPort und MaxAnzahl beschreiben den bevorzugten Suchbereich für neue
Ausweichports, einschließlich des Startports. Ein bereits konfigurierter
gültiger Port wie DAI-Standardport 7331 kann auch außerhalb dieses Bereichs
übernommen werden. Protokoll und BindAdresse sind beschreibende Angaben; sie
öffnen keinen Netzwerkzugriff. DAI nutzt weiterhin nur 127.0.0.1. Andere
Anwendungen legen eigene Beschreibungen und Suchbereiche an; alle reservierten
Portnummern werden dennoch gemeinsam geprüft.

## Sperre und Schreibvorgang

Alle Teilnehmer verwenden für **den gesamten Lese-, Prüf- und Schreibvorgang**
den benannten Windows-Mutex Global\h5uPortReservation.v1. Ohne das Global-Präfix
wäre die Sperre nur innerhalb einer RDP-Sitzung sichtbar. Ein WAIT_ABANDONED
bedeutet, dass erneut alle Dateien eingelesen und geprüft werden müssen. Nach
zehn Sekunden Wartezeit meldet DAI einen Fehler. Ein Lockfile ist kein
gleichwertiger Ersatz: Es muss bei Absturz ebenfalls zuverlässig bereinigt werden.

Der Mutex wird mit einem expliziten Sicherheitsdeskriptor erzeugt. DAI benutzt
CreateMutexExW mit SYNCHRONIZE | MUTEX_MODIFY_STATE und
D:P(A;;0x00100001;;;AU)(A;;GA;;;SY)(A;;GA;;;BA)S:(ML;;NW;;;ME).
Damit können authentifizierte Benutzer den Mutex sitzungsübergreifend öffnen
und benutzen. Der explizite Unicode-Export ist wichtig: Die Delphi-RTL kann
CreateMutexEx fälschlich an den nicht vorhandenen Export ohne W/A-Suffix
binden. Der Vertrag ist unabhängig von der Implementierungssprache: Eine
spätere Delphi-/Free-Pascal-Einzel-EXE kann dieselbe Windows-API verwenden.
Bei der aktuellen Node.js-Variante muss ein geeigneter Windows-API-Zugriff
oder ein Helfer den gesamten kritischen Abschnitt unter diesem Mutex ausführen.

DAI erstellt eine eigene temporäre Datei mit CREATE_NEW, schreibt und
flusht sie und ersetzt anschließend ausschließlich die eigene Benutzerdatei
per MoveFileExW. Eine neue Zieldatei darf dabei nicht überschrieben werden.
Beim Ersetzen bleibt deren bestehende DACL erhalten. Ist die Datei kurzzeitig
von einem anderen Prozess zum Löschen gesperrt, versucht DAI das Ersetzen
begrenzt erneut und prüft vorher jeweils die unveränderte Datei. Temporäre
Dateien heißen .tmp-{GUID} und zählen nicht als Benutzerdateien. Der Mutex
wird auch bei Fehlern freigegeben. Schema=1 ist unabhängig von der jeweiligen Produktversion.

Bei der erstmaligen Anlage erhält das Verzeichnis eine geschützte DACL:
System und Administratoren Vollzugriff; authentifizierte Benutzer lesen und
listen sowie direkt Dateien erstellen; Ersteller besitzen die eigenen Dateien.
Es wird kein allgemeines DELETE_CHILD vergeben. Die von DAI angelegten
Dateien sind für authentifizierte Benutzer lesbar und nur für ihren
Windows-Besitzer, Administratoren und System änderbar. Für Verzeichnis und
neue Dateien wird eine mittlere Integritätsstufe gesetzt, damit eine erhöht
laufende Einrichtung spätere normale Benutzer nicht aussperrt. Vorhandene
Verzeichnisse und Anwendungsbeschreibungen werden nicht ungefragt mit neuen
Rechten überschrieben; deren ACL muss gegebenenfalls administrativ geprüft
werden. Reparsepunkte und mehrere Hardlinks werden beim Dateizugriff abgewiesen.

## DAI-Bedienung und Grenzen

Unter Tools → Options → Third Party → DAI zeigen die Bedienelemente den
Zustand und einen vorhandenen DAI-Portbereich an. Ein eingetragener Port
außerhalb dieses Bereichs bleibt ausdrücklich zulässig und wird nicht
umgestellt. „Portverwaltung einrichten“ legt Verzeichnis und .DAI bei Bedarf an.

Auf Desktop-PCs bleibt die Einrichtung freiwillig und es erscheint keine
ungefragte Empfehlung beim Speichern. Wenn ein TCP-Port beim Serverstart
nicht gebunden werden kann, nennt DAI die gemeinsame Portverwaltung als
Möglichkeit für mehrere Benutzer; die bisherigen Prozessdetails bleiben.
Auf Windows Server fragt DAI beim Speichern oder Registrieren, solange der
gewählte Verbindungsbereich noch keine eigene Reservierung hat. Bei „Nein“
wird innerhalb desselben Optionsdialogs nicht erneut gefragt. „Abbrechen“
unterbricht Speichern oder Registrierung. Bei „Ja“ wird der angezeigte Port
sofort ohne Ausweichport reserviert; diese Reservierung
bleibt auch bei einem späteren Abbruch bestehen. Bei Konflikten bleibt der
Dialog zur Korrektur offen. Remotezugriff allein macht einen Desktop nicht zu
einem Windows Server. Port und Clientregistrierungen werden durch die
Einrichtung nicht automatisch umgestellt.

„Freien Port suchen“ zeigt nur einen Vorschlag im Portfeld: Es wird weder eine
Reservierung geschrieben noch die Konfiguration oder Clientregistrierung
geändert. Bei vorhandener .DAI-Datei durchsucht DAI deren gesamten Bereich
vom Startport an. Ohne diese Datei beginnt die Suche beim eingetragenen Port
und endet bei 65535; ein vorhandenes gemeinsames Verzeichnis wird trotzdem
auf Reservierungen geprüft. Die Suche berücksichtigt einen kurzen exklusiven
TCP-Bindetest auf 127.0.0.1 und überspringt auch gebundene Sockets ohne
Listener. Der Vorschlag ist eine Momentaufnahme und kann später belegt sein.

„Port reservieren“ versucht ausschließlich den angezeigten Port und wählt bei
einem Konflikt keinen anderen. Die Reservierung wird sofort dauerhaft
beschrieben, auch wenn der Optionsdialog anschließend abgebrochen wird. Der
Port selbst bleibt zunächst im Dialog; Speichern oder Registrieren übernimmt
ihn in DAI. Betroffene KI-Clients anschließend neu registrieren und
gegebenenfalls ihre Verbindung neu laden.

Hat der gewählte Verbindungsbereich bereits eine DAI-Reservierung, reserviert
DAI einen manuell geänderten Port beim Speichern ebenfalls. Ist er belegt,
wird das Speichern abgelehnt statt still ein anderer Port verwendet. Ein
anderer freier Port kann vorläufig aus den Optionen gestartet werden; der
Start schreibt keine Reservierung. Wenn die gemeinsame Verwaltung vorhanden
ist, werden vorher fremde Reservierungen geprüft. Die bisherige Reservierung bleibt
bestehen. „Port freigeben“ entfernt nach Bestätigung nur den im Portfeld
angezeigten Eintrag des aktuellen Bereichs. Auch bei einem Fehler nach der
Reservierung kann ein zusätzlicher Eintrag zurückbleiben und bewusst
freigegeben werden.

Ein vorgemerkter oder probeweise geprüfter Port ist nicht durch Windows für
den nächsten Start reserviert: nicht teilnehmende Programme können ihn später
belegen. Ein aktiver Listener des eigenen DAI-Servers darf bei der ersten
Reservierung übernommen werden. Vorhandene eigene Reservierungen bleiben
auch bei einem fremden Listener bestehen; der tatsächliche Serverstart meldet
den Bindefehler.

Beim Einführen können alte, bisher nicht teilnehmende Installationen denselben
Port konfiguriert haben. Eine nicht laufende Installation ist erst erkennbar,
wenn sie ihre vorhandene Einstellung übernimmt. Es werden keine Tokens oder
anderen Geheimnisse in der gemeinsamen Verwaltung gespeichert. Loopback
isoliert Windows-Benutzer nicht voneinander; die bisherige Authentifizierung
bleibt erforderlich.

## Integration in weitere Anwendungen

Die Portverwaltung ist ein gemeinsames Dateiformat und ein Windows-Protokoll.
Sie kann in Delphi, Free Pascal, Node.js oder einer anderen Sprache umgesetzt
werden; eine Anwendung muss weder DAI installieren noch dessen BPL laden.

Für eine weitere Anwendung empfiehlt sich folgendes Vorgehen:

1. Vorhandene Listener, ihre Protokolle und Konfigurationen ermitteln. Ein
   reiner STDIO-Prozess benötigt keine Portreservierung. Jede unabhängig
   nutzbare Listener-Funktion erhält eine stabile Anwendungskennung, zum
   Beispiel `MeineApp:http`. Eine eigene `.MeineApp`-Datei beschreibt den
   bevorzugten Bereich und die Adresse.
2. Die benutzerspezifische Konfiguration und gegebenenfalls vorhandene
   Clientregistrierungen erhalten. Beim Einstieg den bestehenden Port
   übernehmen, sofern er noch nicht für einen anderen Eintrag reserviert ist;
   Konflikte sichtbar melden und eine bewusste Auswahl ermöglichen.
3. Die Windows-Benutzer-SID aus dem Prozesstoken ermitteln und die zugehörige
   Datei anhand der vollständigen SID und des Unterstrichs finden. Eine
   Namensänderung darf nicht zu einer zweiten Datei für dieselbe SID führen.
4. Den oben angegebenen globalen Mutex während des gesamten Einlesens,
   Prüfens und Schreibens verwenden. Unter dieser Sperre die Portdateien aller
   Benutzer und Anwendungen berücksichtigen und die eigene Datei atomar
   ersetzen. Bereits vorhandene fremde Zeilen und Kommentare beibehalten.
5. Zugangsdaten ausschließlich in der geschützten benutzereigenen
   Konfiguration ablegen. Die gemeinsame Portdatei enthält keine Tokens.
   Anzeigen, ob die Verwaltung nutzbar ist, und bestehende Berechtigungen
   fremder Dateien respektieren.
6. Den gewählten Port dauerhaft reserviert lassen, auch wenn der Prozess
   beendet ist. Eine Freigabe oder Umstellung erfolgt bewusst; alte
   Clientregistrierungen dürfen nicht unbemerkt auf einen neuen Port zeigen.
   Beim tatsächlichen Start muss die Anwendung den Socket weiterhin selbst
   binden und eventuelle Fehler melden.
7. Mit synthetischen Testverzeichnissen prüfen: bestehende DAI-Einträge,
   fremde Anwendungseinträge, Namensänderung, unlesbare oder ungültige
   Dateien, doppelte Ports, belegte Listener, konkurrierende Prozesse und
   einen Abbruch während der Vergabe. Für RDP zusätzlich die Rechte und die
   Vergabe mit getrennten Windows-Benutzerkonten prüfen.

Bei Übernahme der DAI-Implementierung die jeweilige Compiler-/RTL-Version und
Lizenzhinweise des aufnehmenden Projekts berücksichtigen. Die Umsetzung kann
auch eigenständig erfolgen, solange das gemeinsame Format und die
Synchronisation eingehalten werden.
