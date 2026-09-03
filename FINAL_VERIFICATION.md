# DAI 1.1.13 – Prüfbericht

## Änderung

DAI 1.1.13 qualifiziert sämtliche Zugriffe auf die RTL-Sperrklasse explizit mit dem Unit-Namespace `System`:

```pascal
System.TMonitor.Enter(ALock);
try
  // geschützter Bereich
finally
  System.TMonitor.Exit(ALock);
end;
```

Die unqualifizierte Schreibweise `TMonitor.Enter` beziehungsweise `TMonitor.Exit` wird nicht mehr verwendet. Dadurch kann `Vcl.Forms.TMonitor`, das einen
Bildschirm beschreibt, die Synchronisationsklasse aus `System` nicht mehr überdecken.

Geänderte Units:

- `h5u.DAI.OTA.Build.pas`
- `h5u.DAI.OTA.CodeInsight.pas`
- `h5u.DAI.Permissions.Manager.pas`

Insgesamt wurden 24 Synchronisationsaufrufe umgestellt.

## Statische Regressionserkennung

`Scripts/verify.py` durchsucht Pascal-Code außerhalb von Zeichenketten und Kommentaren nach unqualifizierten Verwendungen des Symbols:

```pascal
TMonitor
```

Ein solcher Aufruf führt nun zu einem Fehler wie:

```text
Source/h5u.DAI.OTA.Build.pas:129: Synchronisationszugriffe müssen System.TMonitor verwenden
```

Der Negativtest wurde mit einem absichtlich zurückgesetzten `TMonitor.Enter` ausgeführt und erwartungsgemäß abgelehnt.

## Prüfung

- 27 Pascal-Units erkannt
- 39 MCP-Werkzeuge erkannt
- 24 von 24 Monitor-Sperraufrufen als `System.TMonitor` qualifiziert
- keine unqualifizierten `TMonitor`-Aufrufe in Pascal-Sourcen oder `DAI.dpk`
- alle PAS-Dateien besitzen UTF-8 mit BOM
- keine Tabulatorzeichen in Pascal-Sourcen
- keine gemischten Zeilenenden innerhalb einer Pascal-Datei
- maximale Pascal-Zeilenlänge: 179 von erlaubten 180 Zeichen
- DPK- und DPROJ-Referenzen vollständig
- DPROJ-XML gültig
- internes SHA-256-Manifest vollständig erzeugt

## Einschränkung

In dieser Umgebung ist keine Delphi-13-Toolchain vorhanden. Der vorherige Projektstand wurde vom Benutzer in Delphi 13 fehler-, warnungs- und hinweisfrei
kompiliert. Die Änderung in 1.1.13 beschränkt sich auf die eindeutige Qualifikation vorhandener RTL-Aufrufe sowie die statische Regressionserkennung.
