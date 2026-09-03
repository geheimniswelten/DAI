# DAI 1.1.10 – Prüfbericht

Prüfdatum: 3. September 2026

## Gegenstand

DAI 1.1.10 korrigiert das Layout des in die Delphi-13-IDE-Optionen eingebetteten `TDAIOptionsFrame`. Der Frame stellt keine eigene ScrollBox mehr bereit. Das Scrollen übernimmt vollständig der von der IDE erzeugte Options-Host.

Die in DAI 1.1.9 ergänzte Code-Insight-/LSP-Integration über die öffentliche OpenToolsAPI bleibt unverändert enthalten.

## Options-Frame

Aus `h5u.DAI.Options.Frame.pas` wurden entfernt:

```text
FScrollBox
TScrollBox
Vcl.ExtCtrls
VertScrollBar.Range
Align := alClient
```

Alle dynamisch erzeugten Controls verwenden nun direkt `TDAIOptionsFrame` als Owner und Parent. `BuildControls` endet mit:

```pascal
  Align := alTop;
  Height := LTop;
```

Damit kann die vorhandene ScrollBox des Delphi-Einstellungsdialogs die tatsächliche Höhe des Frames ermitteln. Es entsteht keine zweite vertikale Scrollbar, und das Mausrad wird durch das Standardverhalten der IDE verarbeitet.

## Statische Prüfung

Ausgeführt wurde:

```text
python Scripts/verify.py
```

Ergebnis:

```text
DAI-Prüfung erfolgreich: 26 Pascal-Units, 39 MCP-Werkzeuge.
```

Geprüft werden unter anderem:

```text
keine eigene TScrollBox im Options-Frame
kein FScrollBox-Feld
kein alClient-Layout im Options-Frame
BuildControls endet mit Align := alTop und Height := LTop
keine nur für die entfernte ScrollBox verbliebene Vcl.ExtCtrls-Referenz
maximal 180 Zeichen je Pascal-Zeile
keine Tabulatoren in Pascal-Sourcen
einheitliche Zeilenenden innerhalb jeder Pascal-Datei
UTF-8 mit BOM für alle ausgelieferten PAS-Dateien
vollständige DPK-/DPROJ-Referenzen
gültiges DPROJ-XML
konsistente Version 1.1.10 / 1.1.10.0
39 erwartete MCP-Werkzeuge
nichtfatale Behandlung eines belegten MCP-Ports
öffentliche OpenToolsAPI-Code-Insight-Integration
```

## Negativtests des neuen Layouts

Der Prüfer wurde gegen gezielt beschädigte temporäre Kopien ausgeführt:

```text
FScrollBox wieder eingefügt: erkannt
Align := alTop durch Align := alClient ersetzt: erkannt
Height := LTop entfernt: erkannt
Vcl.ExtCtrls wieder in die Uses-Liste aufgenommen: erkannt
```

Ergebnis: **4 von 4 Negativtests bestanden.**

## Quellformat

```text
Pascal-Units:                         26
MCP-Werkzeuge:                        39
PAS-Dateien mit UTF-8-BOM:            26 von 26
PAS-Dateien mit CRLF:                  3
PAS-Dateien mit LF:                   23
Gemischte Pascal-Zeilenenden:          0
Tabulatoren in Pascal-Sourcen:         0
Maximal erlaubte Pascal-Zeilenlänge: 180
Tatsächlich längste Pascal-Zeile:    179
```

Vorhandenes CRLF beziehungsweise LF wird je Datei beibehalten. Innerhalb einer Datei sind gemischte Zeilenenden nicht zulässig. DFM-Dateien unterliegen weiterhin nicht der PAS-Vorgabe für UTF-8 mit BOM.

## Noch erforderlicher IDE-Test

In der Prüfungsumgebung ist keine Delphi-13-Toolchain vorhanden. Daher konnte DAI 1.1.10 hier nicht binär kompiliert oder in einer laufenden IDE geladen werden.

Nach dem lokalen Build sind insbesondere diese Punkte zu prüfen:

```text
Optionsseite lässt sich öffnen
nur eine vertikale Scrollbar ist sichtbar
Mausrad scrollt den IDE-Einstellungsdialog
Frame-Höhe umfasst alle dynamisch erzeugten Controls
Speichern und erneutes Öffnen der Einstellungen funktionieren
```
