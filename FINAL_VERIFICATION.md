# DAI 1.2.0 – Prüfbericht vom 1. Oktober 2026

Das Projekt wurde direkt erweitert. Vorhandene Änderungen dienten als Ausgangspunkt; persönliche Chats, Archive und Projekt-Berechtigungen wurden nicht verändert.

## Ergebnis

- Registrierungen in Delphi für Codex, Claude Code, Claude Desktop (native Delphi-stdio-Brücke), Gemini CLI / Code Assist, Hermes, LM Studio und OpenClaw.
- Eigent mit manuellem UI/API-Hinweis; Gemini Desktop mit Hinweis auf fehlenden verifizierten lokalen Anschluss.
- Backups, private Windows-Rechte, atomare Dateien, JSON-/JSON5-/YAML-Erhalt und SHA-256-Besitzprüfung.
- Skill-Metadaten, CODEX_HOME, Projektzuordnung und aktuelle Arbeitsanweisungen korrigiert.
- Designerinspektion/-anzeige, ungespeicherte DFM/FMX-Ressourcen, Quellhaltepunkte und Debuggersteuerung ergänzt.
- Projekt-/Editor-, Berechtigungs- und MCP-HTTP/JSON-RPC-Fehler behoben; jedes Projekt vor Gruppen-Build autorisieren.
- MCPConnect ist ein zusätzlicher GetIt-Download zur Servererstellung. Kein MCP-Server-Service in den installierten ToolsAPI-Quellen gefunden; keine Migration in dieser Änderung.

## Verifikation

- Win32 Release: DAI.bpl und DAI.McpBridge.exe mit Delphi 37.0 erfolgreich gebaut.
- 32 Pascal-Units und 49 MCP-Werkzeuge statisch geprüft, einschließlich Eingabeschemas, BOM/CRLF, Zeilenlängen und Package-Referenzen.
- 98 native Registrierungs-/Parser-/Datei-Checks unter Win32 und 98 unter Win64 erfolgreich.
- 25 native HTTP-/Protokoll-Checks unter Win32 und 25 unter Win64 erfolgreich.
- Kompilierte stdio-Brücke gegen isolierten HTTP-Server erfolgreich geprüft; YAML-Fixture zusätzlich extern geparst.
- git diff --check ohne Fehler; MANIFEST.sha256 auf ausgelieferte Dateien begrenzt.

Reproduzierbare Testbefehle stehen in README.md. Die älteren Prüfnotizen sind unter work/FINAL_VERIFICATION-vor-1.2.0.md erhalten.

## Noch in der laufenden IDE prüfen

Optionslayout, echte Clientverbindung nach Neuladen, Designer-/Editorzustände, Undo/Speichern, Projektgruppe und Debuggerschritte wurden nicht live ausgelöst.
Das vollständige Package wurde hier nur für Win32 gebaut. Die Win64-Tests verwenden IDE-Stubs und ersetzen keinen 64-Bit-IDE-Test.
Es wurden keine realen Clientkonfigurationen verändert und kein neues BPL in die laufende IDE geladen.

Der Compiler meldet W1002 zum Windows-spezifischen Reparse-Point-Flag und H2077 zum initialen YAML-Ergebniswert; keine Buildfehler.
