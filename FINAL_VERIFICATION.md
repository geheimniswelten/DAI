# DAI 1.1.7 – Prüfbericht

## Fehlerbild

DAI 1.1.6 wurde nach Rückmeldung des Benutzers mit Delphi 13 ohne Fehler, Warnungen oder Hinweise kompiliert und erfolgreich in der IDE installiert. Der Settings-Tab war im IDE-Optionsbaum sichtbar. Beim Öffnen des Tabs brach die Instanziierung jedoch mit folgender Ausnahme ab:

```text
Ressource TDAIOptionsFrame nicht gefunden.
```

Der Stacktrace führte von `Vcl.Forms.TCustomFrame.Create` unmittelbar in `TDAIOptionsFrame.Create`. Der Fehler entstand damit im Aufruf von `inherited Create(AOwner)`, noch bevor `BuildControls` ausgeführt wurde.

## Ursache

`TDAIOptionsFrame` ist ein `TFrame`-Nachkomme. Der normale Frame-Konstruktor erwartet für die konkrete Klasse eine eingebundene DFM-Klassenressource. In DAI 1.1.6 fehlten sowohl die Resource-Direktive als auch die dazugehörige DFM-Datei.

Die Tatsache, dass sämtliche sichtbaren Controls programmatisch in `BuildControls` erzeugt werden, beseitigt diese Anforderung des Frame-Konstruktors nicht.

## Korrektur

### Frame-Unit

In `Source/h5u.DAI.Options.Frame.pas` steht unmittelbar nach `implementation` jetzt:

```pascal
{$R *.dfm}
```

Der bestehende Konstruktor bleibt unverändert:

```pascal
constructor TDAIOptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alClient;
  AutoScroll := False;
  BuildControls;
end;
```

### Minimale DFM-Ressource

Neu hinzugekommen ist `Source/h5u.DAI.Options.Frame.dfm`:

```text
object DAIOptionsFrame: TDAIOptionsFrame
  Left = 0
  Top = 0
  Width = 800
  Height = 600
  TabOrder = 0
end
```

Die DFM enthält bewusst ausschließlich die Root-Komponente. Alle sichtbaren Controls werden weiterhin in `TDAIOptionsFrame.BuildControls` erzeugt.

### DPROJ-Metadaten

Der Eintrag der Frame-Unit lautet jetzt:

```xml
<DCCReference Include="Source\h5u.DAI.Options.Frame.pas">
    <Form>DAIOptionsFrame</Form>
    <FormType>dfm</FormType>
    <DesignClass>TFrame</DesignClass>
</DCCReference>
```

## Dateiformate

- Alle 25 PAS-Dateien bleiben UTF-8 mit BOM.
- Die vorhandenen Zeilenenden der PAS-Dateien bleiben unverändert.
- Keine PAS-Datei enthält gemischte Zeilenenden oder Tabulatorzeichen.
- Die neue DFM ist reines ASCII/ANSI ohne BOM und verwendet einheitliches CRLF.
- Die UTF-8+BOM-Vorgabe gilt weiterhin nur für `.pas`, nicht für `.dfm`.

## Erweiterte statische Prüfung

`Scripts/verify.py` prüft jetzt für jeden direkten `TFrame`-Nachkommen:

- eine gleichnamige DFM-Datei,
- `{$R *.dfm}` in der Unit,
- eine zur Frame-Klasse passende Root-Komponente,
- einheitliche Zeilenenden in der DFM,
- einen nicht selbstschließenden DPROJ-Eintrag,
- `Form`-Metadaten,
- `FormType=dfm`,
- und `DesignClass=TFrame`.

Vier Negativtests wurden ausgeführt:

```text
fehlendes {$R *.dfm}:       erkannt
fehlende DFM-Datei:         erkannt
falsche DFM-Root-Klasse:    erkannt
falsches Form-Metadatum:    erkannt
```

## Gesamtergebnis

```text
Pascal-Units:                          25
MCP-Werkzeuge:                         34
Neue DFM-Ressourcen:                    1
Maximal erlaubte Pascal-Zeilenlänge:  180
Tatsächlich längste Pascal-Zeile:     179
PAS-Dateien mit UTF-8-BOM:             25 von 25
PAS-Dateien mit CRLF:                   3
PAS-Dateien mit LF:                    22
Gemischte Pascal-Zeilenenden:           0
Tabulatoren in Pascal-Sourcen:          0
DFM-Zeilenenden:                       einheitliches CRLF
DPK-/DPROJ-Referenzen:                 vollständig
DPROJ-XML:                             gültig
Statische Prüfung:                     bestanden
Negative Frame-Ressourcentests:        bestanden
```

## Abgrenzung

DAI 1.1.6 wurde laut Benutzer in Delphi 13 erfolgreich kompiliert und installiert. DAI 1.1.7 konnte in dieser Umgebung mangels Delphi-13-Toolchain nicht erneut mit `dcc32.exe` gebaut werden. Die Codeänderung beschränkt sich auf die fehlende Frame-Ressource, ihre Projektmetadaten, Versionsangaben und die zugehörige statische Prüfung.
