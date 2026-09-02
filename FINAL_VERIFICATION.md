# DAI 1.1.3 – Prüfbericht

## Änderungen

- Sämtliche Pascal-Units wurden mit einer maximalen Zeilenlänge von 180 Zeichen geprüft.
- Methodensignaturen und Property-Deklarationen bleiben in einer Zeile, solange die vollständige Zeile einschließlich Einrückung höchstens 180 Zeichen enthält.
- Längere Funktionssignaturen werden möglichst spät umgebrochen. Wenn möglich, bleibt die vollständige Parameterliste in der ersten Zeile und der Rückgabetyp folgt in der nächsten Zeile.
- In `h5u.DAI.UI.pas` wurde vor dem `finalization`-Abschnitt ein `initialization`-Abschnitt ergänzt.
- Dieselbe fehlerhafte Abschnittsfolge wurde zusätzlich in `h5u.DAI.Options.Page.pas` und `h5u.DAI.Runtime.pas` korrigiert.
- `Scripts/verify.py` erkennt nun `finalization` ohne vorheriges `initialization` sowie unnötig früh umgebrochene Methoden- und Property-Deklarationen.

## Statische Prüfungen

- 24 Pascal-Units vorhanden
- 34 MCP-Werkzeuge deklariert
- maximale Zeilenlänge in Pascal-Dateien und `DAI.dpk`: 180 Zeichen
- tatsächlich längste Pascal-Zeile: 179 Zeichen
- keine Methodensignatur wird umgebrochen, wenn sie vollständig in höchstens 180 Zeichen passt
- keine mehrzeilige Property-Deklaration, die in höchstens 180 Zeichen passen würde
- jeder `finalization`-Abschnitt besitzt einen vorherigen `initialization`-Abschnitt
- DPK- und DPROJ-Referenzen vollständig
- DPROJ-XML syntaktisch gültig
- bekannte ungültige beziehungsweise ungeeignete Dateiausnahmen nicht vorhanden
- Klammern, Zeichenketten und Kommentare statisch geprüft
- `Scripts/verify.py` mit `py_compile` geprüft

## Abgrenzung

Ein echter Delphi-13-Build konnte in dieser Umgebung nicht ausgeführt werden, weil keine Delphi-13-Toolchain mit `dcc32.exe`, `designide.dcp` und der installierten `ToolsAPI.pas` verfügbar ist. Die statischen Prüfungen ersetzen deshalb nicht den abschließenden lokalen Build in RAD Studio 13.
