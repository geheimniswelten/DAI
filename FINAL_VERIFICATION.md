# DAI 1.1.6 – Prüfbericht

## Änderung

Die Behandlung von Zeilenenden und Einrückungen wurde an den Windows-/Delphi- und Git-Arbeitsablauf angepasst:

- ein bereits einheitliches CRLF bleibt CRLF
- ein bereits einheitliches LF bleibt LF
- es findet keine projektweite Konvertierung zwischen CRLF und LF statt
- gemischte Zeilenenden werden beim Schreiben vereinheitlicht
- alleinstehendes CR wird nicht als Zielformat weitergeführt
- Tabulatorzeichen werden in Pascal-Sourcen durch zwei Leerzeichen ersetzt

Die Tab-Regel gilt für `.pas`, `.dpr`, `.dpk` und `.inc`, nicht für DFM-Dateien.

## Laufzeitverhalten von `file_write`

`TDAITextEncoding.PrepareText` wird sowohl für geöffnete IDE-Puffer als auch für direkt geschriebene, geschlossene Dateien verwendet.

### Vorhandene Dateien

- Bei eindeutigem CRLF oder LF wird dieses Format für den vollständig ersetzten Inhalt beibehalten.
- Bei gemischten Zeilenenden oder alleinstehendem CR wird der neue Inhalt auf CRLF normalisiert.
- Pascal-Sourcen werden anschließend von echten Tabulatorzeichen auf jeweils zwei Leerzeichen normalisiert.
- Die bestehende Codierung bleibt erhalten; eine vorhandene ANSI-PAS-Datei wird nur dann auf UTF-8 mit BOM angehoben, wenn der neue Inhalt nicht verlustfrei in ANSI darstellbar ist.

### Neue Dateien

- Einheitliches CRLF beziehungsweise LF aus dem übergebenen Inhalt bleibt erhalten.
- Gemischte Zeilenenden oder alleinstehendes CR werden auf CRLF normalisiert.
- Neue `.pas`-Dateien verwenden weiterhin UTF-8 mit BOM.
- Andere neue Textdateien erhalten nicht automatisch die PAS-Codierungsregel.

### DFM-Dateien

DFM-Dateien werden weiterhin ausschließlich über den IDE-Textpuffer bearbeitet. Delphi entscheidet beim Speichern selbst über ANSI oder UTF-8. Die Tabulatorregel für Pascal-Sourcen wird nicht auf DFM angewendet.

## Auslieferungsformat

Die vorhandenen Zeilenenden der Projektdateien wurden nicht pauschal verändert:

- 3 PAS-Dateien verwenden CRLF
- 22 PAS-Dateien verwenden LF
- keine PAS-Datei enthält gemischte Zeilenenden
- `DAI.dpk` verwendet weiterhin LF
- alle 25 PAS-Dateien verwenden UTF-8 mit BOM
- keine ausgelieferte Pascal-Source enthält ein Tabulatorzeichen

Die drei CRLF-Dateien bleiben:

```text
h5u.DAI.MCP.Server.pas
h5u.DAI.OTA.Projects.pas
h5u.DAI.Options.Frame.pas
```

## Statische Prüfungen

`Scripts/verify.py` prüft jetzt zusätzlich:

- keine Tabulatorzeichen in `.pas` und `DAI.dpk`
- keine Mischung von CRLF und LF innerhalb derselben Pascal-Source
- keine alleinstehenden CR-Zeilenenden
- die Laufzeit-Schreiblogik verwendet `PrepareText` auch für IDE-Puffer
- gemischte beziehungsweise CR-Zeilenenden besitzen einen CRLF-Fallback
- Pascal-Tabulatoren werden beim Schreiben durch zwei Leerzeichen ersetzt

Die neuen Prüfungen wurden mit absichtlich fehlerhaften Testkopien kontrolliert:

- ein eingefügter Tabulator wurde mit Dateiname und Zeilennummer erkannt
- eine absichtlich erzeugte CRLF-/LF-Mischung wurde erkannt

## Gesamtergebnis

```text
Pascal-Units:                          25
MCP-Werkzeuge:                         34
Maximal erlaubte Pascal-Zeilenlänge:  180
Tatsächlich längste Pascal-Zeile:     179
PAS-Dateien mit UTF-8-BOM:             25 von 25
PAS-Dateien mit CRLF:                   3
PAS-Dateien mit LF:                    22
Gemischte Pascal-Zeilenenden:           0
Tabulatoren in Pascal-Sourcen:          0
DPK-/DPROJ-Referenzen:                 vollständig
DPROJ-XML:                             gültig
Statische Prüfung:                     bestanden
Negative Tabulatorprüfung:             bestanden
Negative Mischzeilenendenprüfung:      bestanden
```

## Abgrenzung

DAI 1.1.4 wurde nach Rückmeldung des Benutzers in Delphi 13 erfolgreich kompiliert. Die seitdem hinzugekommene Codierungs- und Zeilenendenlogik konnte in dieser Umgebung nicht mit `dcc32.exe` kompiliert werden, weil keine Delphi-13-Toolchain installiert ist. Die vorliegenden Änderungen wurden statisch geprüft; ihre Pascal-Schnittstellen sind konsistent in Deklaration und Implementierung vorhanden.
