# DAI 1.1.5 – Prüfbericht

## Grundlage

Der Stand basiert auf DAI 1.1.4. Die drei zuletzt vom Benutzer in Delphi 13 erfolgreich kompilierten Dateien wurden erneut unverändert als Grundlage übernommen:

- `h5u.DAI.MCP.Server.pas`: UTF-8 mit BOM und CRLF, bytegenau übernommen
- `h5u.DAI.Options.Frame.pas`: UTF-8 mit BOM und CRLF, bytegenau übernommen
- `h5u.DAI.OTA.Projects.pas`: UTF-8 mit BOM und CRLF übernommen; ausschließlich die bereits bekannte unbenutzte Initialisierung `Result := False` wurde entfernt

Es wurde keine pauschale Umstellung der Zeilenenden vorgenommen.

## PAS-Codierung

Alle 25 ausgelieferten `.pas`-Dateien sind jetzt UTF-8 mit BOM. Beim Hinzufügen des BOM wurden die vorhandenen Zeilenenden nicht verändert:

- die beiden bytegenau übernommenen Benutzerdateien behalten CRLF
- `h5u.DAI.OTA.Projects.pas` behält CRLF
- die übrigen, aus dem bisherigen Projektstand stammenden Dateien behalten LF
- die neue Unit `h5u.DAI.Text.Encoding.pas` verwendet UTF-8 mit BOM und LF

Die Prüfung verlangt UTF-8 mit BOM ausschließlich für die ausgelieferten `.pas`-Dateien. Für DFM-Dateien wird keine entsprechende Regel angewendet.

## Laufzeitverhalten von `file_read` und `file_write`

Die neue Unit `h5u.DAI.Text.Encoding.pas` kapselt die Codierungs- und Zeilenendenbehandlung geschlossener Dateien.

### Vorhandene geschlossene Dateien

- BOM-basierte Codierungen werden erkannt und beibehalten.
- Delphi-Dateien ohne BOM werden entsprechend dem IDE-Verhalten als System-ANSI interpretiert.
- Vorhandene Zeilenenden werden erkannt und bei vollständiger Ersetzung des Inhalts beibehalten.
- Kann neuer Inhalt nicht verlustfrei in der bestehenden ANSI-Codierung gespeichert werden, wird eine Pascal-Quelldatei auf UTF-8 mit BOM angehoben.

### Neue Dateien

- Neue `.pas`-Dateien werden standardmäßig als UTF-8 mit BOM geschrieben.
- Für andere neue Textdateien wird nicht automatisch die PAS-Regel verwendet.
- Die im übergebenen Inhalt vorhandenen Zeilenenden bleiben unverändert.

### DFM-Dateien

DFM-Dateien werden niemals direkt durch `TFile.WriteAllText` oder `TFile.WriteAllBytes` ersetzt. `file_write` behandelt `.dfm` immer als IDE-Bearbeitung, öffnet beziehungsweise verwendet den IDE-Textpuffer und speichert bei angefordertem `save` über die IDE. Dadurch entscheidet Delphi selbst beim Speichern, ob die DFM als ANSI oder UTF-8 ausgegeben wird.

Ist kein DFM-Textpuffer verfügbar, wird der Schreibvorgang abgelehnt. Ein verdecktes Überschreiben der DFM auf dem Datenträger findet nicht statt.

## Erweiterte Rückgabedaten

`file_read` liefert zusätzlich:

- `encoding`
- `line_ending`

`file_write` liefert zusätzlich:

- `encoding`
- `original_encoding`
- `line_ending`
- `original_line_ending`

Für einen aktiven Editorpuffer wird die Codierung als `ide-buffer` gemeldet, weil die endgültige Dateicodierung erst beim Speichern durch die IDE festgelegt wird.

## Statische Prüfungen

- 25 Pascal-Units vorhanden
- 34 MCP-Werkzeuge deklariert
- alle `.pas`-Dateien UTF-8 mit BOM
- keine Prüfung oder erzwungene Standardcodierung für DFM-Dateien
- maximale erlaubte Zeilenlänge in Pascal-Dateien und `DAI.dpk`: 180 Zeichen
- tatsächlich längste Pascal-Zeile: 179 Zeichen
- Methodensignaturen und Property-Deklarationen bleiben einzeilig, solange sie vollständig in höchstens 180 Zeichen passen
- jeder `finalization`-Abschnitt besitzt einen vorherigen `initialization`-Abschnitt
- DPK- und DPROJ-Referenzen einschließlich `h5u.DAI.Text.Encoding.pas` vollständig
- DPROJ-XML syntaktisch gültig
- bekannte ungültige beziehungsweise ungeeignete Dateiausnahmen nicht vorhanden
- Klammern, Zeichenketten und Kommentare statisch geprüft
- `Scripts/verify.py` mit `py_compile` geprüft

## Abgrenzung

DAI 1.1.4 wurde nach Rückmeldung des Benutzers in Delphi 13 kompiliert. Die neue Encoding-Unit und die Änderungen an `file_read`/`file_write` konnten in dieser Umgebung nicht mit `dcc32.exe` kompiliert werden, weil keine Delphi-13-Toolchain installiert ist. Sie wurden statisch gegen die vorhandenen Projektschnittstellen und die Delphi-Signaturregeln geprüft.
