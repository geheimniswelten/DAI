# DAI 1.1.9 – Prüfbericht

Prüfdatum: 2. September 2026

## Gegenstand

DAI 1.1.9 erweitert den bisherigen Delphi-13-IDE-/MCP-Server um lesenden semantischen Zugriff auf den bereits von der IDE verwalteten
Code-Insight-Provider. Grundlage der API-Prüfung war das unveränderte Benutzerarchiv
`4eca849b-bdf8-4cba-9dc9-9e73f93171aa.zip` mit den Delphi-13-OpenToolsAPI-Sourcen.

SHA-256 des untersuchten API-Archivs:

```text
d04c17f7a772fead151db1dee7a2b1eb906b68760972abeba59c10fd778d6f2b
```

Die OpenToolsAPI-Sourcen werden nicht mit DAI ausgeliefert.

## Architekturentscheidung

DAI verbindet sich nicht als zweiter JSON-RPC-Client mit den privaten Standard-I/O-Pipes der von Delphi gestarteten `DelphiLSP.exe`. Stattdessen wird
der aktive Provider über die öffentliche OpenToolsAPI angesprochen:

```text
MCP-Client
  -> DAI Streamable-HTTP-Server
    -> h5u.DAI.OTA.CodeInsight
      -> IOTACodeInsightServices
        -> aktiver IOTAAsyncCodeInsightManager
          -> von Delphi verwalteter Code-Insight-/LSP-Provider
```

Dadurch verwendet die KI dieselbe aktive Projekt-, Plattform- und Build-Konfiguration wie die IDE. Auch der von Delphi an den Provider synchronisierte
Editorstand bleibt maßgeblich; ein zweiter Index und ein zweiter LSP-Prozess sind für die öffentliche Basisfunktionalität nicht erforderlich.

## Neue MCP-Werkzeuge

| Werkzeug | Ergebnis | OpenToolsAPI-Grundlage |
|---|---|---|
| `code_insight_status` | Provider, Bereitschaft und unterstützte Operationen | `IOTACodeInsightServices`, `IOTAAsyncCodeInsightManager` |
| `code_definition` | Definitionsdatei, Zielzeile und nach Möglichkeit Zielzeichenindex | `AsyncGotoDefinitionEx`, Fallback `AsyncGotoDefinition` |
| `code_hover` | Help-Insight-Inhalt für eine Editorposition | `AsyncGetHintText`, `SetQueryContext` |
| `file_diagnostics` | Error-Insight-Fehler, Warnungen und Hinweise | `IOTAModuleErrors.GetErrors` |
| `project_context` | aktive Konfiguration, Plattform, Ziel, Dateien und DCC-Eigenschaften | `IOTAProject`, `IOTAProjectOptionsConfigurations`, `IOTABuildConfiguration` |

Alle fünf Werkzeuge sind als read-only registriert und verwenden die bestehende Berechtigungskategorie `pcReadAccess`.

## API-Abgleich

Folgende 18 Signaturen beziehungsweise Datendefinitionen wurden automatisiert gegen das hochgeladene `ToolsAPI.pas` geprüft:

```text
IOTACodeInsightServices.GetCurrentCodeInsightManager
IOTACodeInsightServices.SetQueryContext
IOTACodeInsightServices.HandlesFile
IOTAAsyncCodeInsightManager.AsyncEnabled
IOTAAsyncCodeInsightManager.AsyncCanInvoke
IOTAAsyncCodeInsightManager.AsyncGetHintText
IOTAAsyncCodeInsightManager.AsyncGotoDefinition
IOTAAsyncCodeInsightManager290.AsyncGotoDefinitionEx
IOTAAsyncCodeInsightManager.AsyncOperationCanceled
IOTAModuleErrors.GetErrors
IOTAProject.GetCompleteFileList
IOTABuildConfiguration.Value
IOTAProjectOptionsConfigurations.ActiveConfiguration
TOTAEditPos
TOTACharPos
TOTAGotoDefinitionCallBack
TOTAGotoDefinitionCallBackEx
TOTAHintTextCallBack
```

Ergebnis: **18 von 18 Signaturprüfungen bestanden.**

### Positionskonventionen

- Definition und Error Insight: Zeile 1-basiert, `CharIndex` 0-basiert und vor Tabulator-Expansion.
- Help Insight: Zeile und Spalte 1-basiert; die Spalte entspricht der Editorposition nach Tabulator-Expansion.

DAI übernimmt diese Konventionen unverändert in den MCP-Parametern und -Ergebnissen.

## Nebenläufigkeit und IDE-Lebenszyklus

- Alle OpenToolsAPI-Aufrufe werden über `TDAIOTA.RunOnMainThread` auf dem IDE-Hauptthread ausgeführt.
- Asynchrone Code-Insight-Anfragen werden durch einen globalen Monitor serialisiert, da der Query-Kontext IDE-global ist.
- Der MCP-Arbeitsthread wartet auf ein manuelles Event; der IDE-Hauptthread bleibt für Provider-Callbacks verfügbar.
- Bei Aufruf vom Hauptthread wird die Nachrichtenwarteschlange verarbeitet, statt den Thread blockierend warten zu lassen.
- Timeouts sind auf 100 bis 60.000 Millisekunden begrenzt; Standard sind 10.000 Millisekunden.
- Eine Zeitüberschreitung wird nur markiert, solange nicht bereits ein erfolgreiches Callback eingetroffen ist.
- Gültige Request-IDs werden geprüft; laufende Anfragen werden bei Timeout über `AsyncOperationCanceled` abgebrochen.
- Verspätete Callbacks abgebrochener Anfragen werden ignoriert.
- Der für Help Insight gesetzte Query-Kontext wird in einem `finally`-Block stets mit `SetQueryContext(nil, nil)` zurückgesetzt.

## Projektkontext

`project_context` kann neben den Projektmetadaten eine begrenzte vollständige Projektdateiliste und folgende ausgewertete Delphi-Eigenschaften liefern:

```text
DCC_Define
DCC_UnitSearchPath
DCC_Namespace
DCC_IncludePath
DCC_LibraryPath
DCC_UnitAlias
DCC_UsePackage
DCC_ExeOutput
DCC_DcuOutput
DCC_BplOutput
DCC_DcpOutput
```

Die Anzahl zurückgegebener Dateien ist auf maximal 50.000 begrenzt und standardmäßig auf 5.000 eingestellt.

## Statische Prüfung

Ausgeführt wurde:

```text
python Scripts/verify.py
```

Ergebnis:

```text
DAI-Prüfung erfolgreich: 26 Pascal-Units, 39 MCP-Werkzeuge.
```

Zusätzliche Prüfergebnisse:

```text
OpenToolsAPI-Signaturen:              18 von 18 bestanden
MCP-JSON-Schemas:                     39 von 39 gültig
Eindeutige MCP-Werkzeugnamen:         39 von 39
Pascal-Units:                         26
PAS-Dateien mit UTF-8-BOM:            26 von 26
Gemischte Pascal-Zeilenenden:          0
Tabulatoren in Pascal-Sourcen:         0
Maximal erlaubte Pascal-Zeilenlänge: 180
Tatsächlich längste Pascal-Zeile:    179
DPK-/DPROJ-Referenzen:               vollständig
DPROJ-XML:                           gültig
Versionsangaben:                     konsistent 1.1.9 / 1.1.9.0
Statische Prüfung:                   bestanden
```

Der bestehende Regressionstest für die nichtfatale Behandlung eines belegten MCP-Ports aus DAI 1.1.8 bleibt Bestandteil des Prüfers.

## Negativtests

Der Prüfer wurde gegen gezielt beschädigte temporäre Kopien ausgeführt. Folgende sechs Fehler wurden erwartungsgemäß erkannt:

```text
Rückbau von SetQueryContext(nil, nil) entfernt: erkannt
Registrierung von code_definition entfernt: erkannt
DPROJ-Referenz der neuen Unit entfernt: erkannt
UTF-8-BOM der neuen PAS-Datei entfernt: erkannt
Prüfung ungültiger Code-Insight-Request-IDs entfernt: erkannt
CDAIVersion auf 1.1.8 zurückgesetzt: erkannt
```

Ergebnis: **6 von 6 Negativtests bestanden.**

## Funktionale Grenzen

Die öffentliche Delphi-13-OpenToolsAPI stellt keinen generischen Rückgabekanal für sämtliche LSP-Methoden bereit. Nicht enthalten sind in dieser Version
insbesondere:

- Find all references,
- Workspace-/Document-Symbole,
- Rename,
- Call Hierarchy,
- Type Hierarchy,
- Semantic Tokens.

Diese Funktionen würden eine separate, von DAI gestartete und mit dem Projekt synchronisierte LSP-Instanz erfordern. Ein Anhängen an die privaten Pipes
der IDE-Instanz ist dafür nicht vorgesehen.

`file_diagnostics` spiegelt Error Insight. Eine leere Ergebnisliste ersetzt keinen vollständigen Compilerlauf und beweist nicht in jeder IDE-Situation,
dass die Datei fehlerfrei kompiliert.

## Noch erforderlicher Delphi-Test

In der Prüfungsumgebung ist keine Delphi-13-Toolchain beziehungsweise `dcc32.exe` vorhanden. Deshalb wurde das Package nicht binär kompiliert oder in einer
laufenden Delphi-13-IDE installiert. Der Quellstand ist statisch, strukturell und gegen die bereitgestellten OpenToolsAPI-Signaturen geprüft; abschließend
ist einmal `Build.ps1` beziehungsweise ein Build von `DAI.dproj` in Delphi 13 auszuführen und die fünf Werkzeuge gegen den dort aktiven Provider aufzurufen.
