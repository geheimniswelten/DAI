# Delphi 13 OpenToolsAPI – Code Insight / LSP

## Nachprüfung der installierten ToolsAPI, 1. Oktober 2026

Zusätzlich wurden die lokalen Sourcen unter `C:\Program Files (x86)\Embarcadero\Studio\37.0\source\ToolsAPI` geprüft.
`IOTAModuleErrors.GetErrors` in `ToolsAPI.pas` (Zeile 3260 ff.) liefert IDE-Moduldiagnosen. DAI verwendet diese Schnittstelle bereits in `file_diagnostics`.
Sie bietet keine Diagnoseversion, keinen Refresh-/Completed-Parameter und keinen Dienst `Validate(file, proposed_content)`.
DAI 1.2.4 weist deshalb `diagnostics_api` und `diagnostics_freshness: unknown` aus, beziehungsweise `unavailable`, wenn das Modul den Dienst nicht anbietet.

Die asynchronen Code-Insight-Schnittstellen (Zeile 10733 ff.) bieten Completion, Parameter-/Help-Insight, Definition und Abbruch;
ein öffentlicher Raw-LSP-Kanal oder eine Diagnoseprüfung übergebenen Inhalts wurde im installierten ToolsAPI-Quellbestand nicht gefunden.
`PreValidateCodeInsight` prüft einen Token als Code-Insight-Abfragepunkt, nicht den Delphi-Code. `IOTACodeFormatter.FormatFile` nimmt Inhalt an,
liefert aber Formatiererfolg und formatierten Text statt Syntax-/Semantikdiagnosen.

`cmOTACheck` (Zeile 1104) ist ein Compiler-Prüfmodus für den aktuellen Projektstand. Laut API entstehen dabei keine Compiler-Ausgabedateien;
IDE-Notifiers und mögliche Autosave-Abläufe machen daraus trotzdem keine rein lesende Vorabprüfung beliebigen Texts.
DAI ersetzt für Codeprüfungen keinen Editorpuffer vorübergehend. Die `.pas`-Schreibprüfung ist lexikalisch; eine vollständige Syntax-/Semantikprüfung
erfordert den Compiler. Eine leere Error-Insight-Liste bestätigt keine Prüfung des neuesten oder vorgeschlagenen Inhalts.

## Kompatibilität mit Delphi 11/12, 2. Oktober 2026

DAI wird gegen die ToolsAPI der jeweiligen Delphi-Installation kompiliert. Optionale neuere Deklarationen wie
`IOTAAsyncCodeInsightManager290` werden bereits mit `{$IF Declared(...)}` ausgeklammert, wenn die verwendete SDK-Version sie nicht kennt.
Innerhalb dieses Guards prüft `Supports` das konkrete Provider-Objekt. Eine vorhandene Interface-Deklaration bedeutet nicht, dass jeder registrierte
Code-Insight-Provider sie implementiert. DAI verwendet bei fehlender Erweiterung den älteren Callback, dessen Ergebnis keinen Zeichenindex liefert.
`definition_character_supported` beschreibt entsprechend die tatsächlich angebotene Provider-Schnittstelle.

Der Nutzer bestätigte Build und Installation unter Delphi 11. Die lokalen Regressionen laufen gegen die installierte Delphi-13-ToolsAPI;
sie ersetzen keinen vollständigen Funktionstest in der Delphi-11/12-IDE. CompilerVersion 35.0 bezeichnet Delphi 11 und 36.0 Delphi 12
([Compiler-Versionen](https://docwiki.embarcadero.com/RADStudio/Athens/en/Compiler_Versions)).
Textblöcke und TEXTBLOCK sind deshalb ab `CompilerVersion >= 36.0` geschützt
([String-Typen](https://docwiki.embarcadero.com/RADStudio/Athens/en/String_Types_%28Delphi%29)).

## Untersuchte Quelle

Grundlage ist das vom Benutzer bereitgestellte Archiv `4eca849b-bdf8-4cba-9dc9-9e73f93171aa.zip` mit den Delphi-13-OpenToolsAPI-Sourcen. Das Archiv enthält
unter anderem `ToolsAPI.pas`, `ToolsAPI.Editor.pas` und `ToolsAPI.AI.pas`. SHA-256 des unveränderten Archivs:

```text
d04c17f7a772fead151db1dee7a2b1eb906b68760972abeba59c10fd778d6f2b
```

## Relevante öffentliche Schnittstellen

### `IOTACodeInsightServices`

Die Schnittstelle wird über `BorlandIDEServices` abgefragt. Sie stellt den aktuellen Code-Insight-Manager, alle registrierten Manager, die zugehörige
Editoransicht und `HandlesFile` bereit. `IOTACodeInsightServices270.SetQueryContext` erlaubt, eine konkrete `IOTAEditView` und einen Manager für eine
programmatische Abfrage zu setzen. Laut API muss der Kontext anschließend mit `SetQueryContext(nil, nil)` zurückgesetzt werden.

### `IOTAAsyncCodeInsightManager`

Die asynchrone Schnittstelle bietet öffentlich:

- Code Completion,
- Parameter Insight,
- Help Insight,
- Go to Definition,
- Bereitschafts- und Capability-Abfragen,
- Abbruch einer laufenden Operation.

`IOTAAsyncCodeInsightManager290` erweitert Go to Definition um den Zeichenindex im Ziel.

### Positionskonventionen

Die API verwendet zwei unterschiedliche Positionstypen:

| Kontext | Zeile | Zeichen/Spalte |
|---|---:|---:|
| `TOTACharPos`, Definition und Error Insight | 1-basiert | `CharIndex` 0-basiert, vor Tabulator-Expansion |
| `TOTAEditPos` und Help Insight | 1-basiert | `Col` 1-basiert, nach Tabulator-Expansion |

DAI übernimmt diese Konventionen unverändert in den jeweiligen Werkzeugparametern und Ergebnissen, damit keine stillen Off-by-one-Umrechnungen entstehen.

### `IOTAModuleErrors`

Ein geladenes `IOTAModule` kann nach `IOTAModuleErrors` abgefragt werden. `GetErrors` liefert Meldung, Schweregrad sowie Start-/Endpositionen. Die Daten
entsprechen Error Insight; eine leere Liste beweist daher nicht in jeder IDE-Situation, dass der Compiler die Datei fehlerfrei übersetzen würde.

### Projektkontext

`IOTAProject`, `IOTAProjectOptionsConfigurations` und `IOTABuildConfiguration` liefern die aktive Konfiguration, Plattform, Framework-/Anwendungstypen,
Projektdateien und ausgewertete Build-Eigenschaften. Für Delphi werden in DAI insbesondere folgende öffentliche Property-Namen abgefragt:

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

### Abgrenzung zu `ToolsAPI.AI` und `ToolsAPI.Editor`

`ToolsAPI.AI.pas` beschreibt die Registrierung und Verwendung von KI-Providern innerhalb der IDE, etwa Chat-, Instruction- und Modellfunktionen. Diese API
stellt keinen semantischen Zugriff auf den Delphi-LSP bereit. `ToolsAPI.Editor.pas` ergänzt Editor- und Darstellungsfunktionen, enthält aber ebenfalls keine
generische Schnittstelle für LSP-Methoden wie References oder Rename. Für semantische Quelltextabfragen ist daher die Code-Insight-API in `ToolsAPI.pas`
der öffentliche Einstiegspunkt.

## Gewählte Architektur

Die von der IDE gestartete `DelphiLSP.exe` kommuniziert über die von Delphi gehaltenen Standard-I/O-Pipes. Ein zweiter Client kann sich an diesen Transport
nicht zuverlässig anhängen. DAI verwendet deshalb für die öffentlich erreichbaren Funktionen die OpenToolsAPI-Abstraktion der IDE. Das hat drei Vorteile:

1. keine zweite Indizierung und kein zusätzlicher LSP-Prozess,
2. identische aktive Projekt-/Plattformkonfiguration,
3. Nutzung des von Delphi synchronisierten, auch ungespeicherten Editorstands.

Alle OTA-Aufrufe werden auf dem IDE-Hauptthread gestartet. Der MCP-Arbeitsthread wartet auf das Callback, ohne den Hauptthread zu blockieren. Anfragen werden
serialisiert, weil der Code-Insight-Query-Kontext IDE-global ist. Timeouts werden an den Provider weitergereicht.

## In DAI 1.1.9 bereitgestellte MCP-Werkzeuge

| Werkzeug | Grundlage | Einschränkung |
|---|---|---|
| `code_insight_status` | Provider-Auflistung und Capability-Abfragen | keine Roh-LSP-Verbindung |
| `code_definition` | `AsyncGotoDefinitionEx` / `AsyncGotoDefinition` | Zielzeichenindex nur mit Interface 290 |
| `code_hover` | `AsyncGetHintText` und `SetQueryContext` | Datei benötigt eine sichtbare Editoransicht |
| `file_diagnostics` | `IOTAModuleErrors.GetErrors` | entspricht Error Insight, nicht einem vollständigen Build |
| `project_context` | `IOTAProject` und Build-Konfiguration | ausgewählte DCC-Eigenschaften, nicht sämtliche MSBuild-Properties |

## Nicht öffentlich abgedeckte LSP-Funktionen

Die untersuchte OpenToolsAPI bietet keine generische öffentliche Methode für References, Workspace-/Document-Symbole, Rename, Call Hierarchy, Type Hierarchy
oder Semantic Tokens. Eine spätere zweite Stufe kann diese Funktionen über eine separate, von DAI gestartete LSP-Instanz pro Projekt ergänzen. Diese Instanz
müsste mit denselben Plattform-/Konfigurationswerten initialisiert und mit Editoränderungen synchronisiert werden; sie darf nicht die privaten Pipes der
IDE-Instanz übernehmen.
