# DAI 1.2.1 – Prüfbericht vom 1. Oktober 2026

## Änderungen seit 1.2.0

- Eigenständige Sessionverwaltung: 30 Minuten Inaktivität, monotone Zeitmessung, gezieltes Cleanup und Schutz laufender Anfragen.
- Das Limit von 1.024 Sitzungen weist neue Initialisierungen mit HTTP 503 ab; bestehende Verbindungen bleiben erhalten.
- Authentifiziertes DELETE beendet klassische MCP-Sitzungen mit HTTP 204. Die native Bridge versucht beim Schließen ihrer Eingabe ein Session-DELETE.
- Package- und Unit-Prüfung gegen zusätzliche GetIt-Abhängigkeiten. Kein Fremdcode und keine SDK-Binärressource übernommen.
- Registrierungen, Skill-Metadaten, OTA-Editor-/Projektzugriffe, Designerinspektion und Debuggerwerkzeuge aus 1.2.0 bleiben enthalten.

## Verifikation

- Win32 Release: DAI.bpl und DAI.McpBridge.exe erfolgreich mit Delphi 37.0 gebaut.
- Je 69 native Sessionprüfungen unter Win32/Win64, darunter acht Threads mit 8.000 parallelen Anfragezyklen.
- Je 46 native HTTP-/Protokollprüfungen unter Win32/Win64, inklusive DELETE, Auth/Origin/Version, Kapazität und Ablauf.
- Kompilierte Bridge erfolgreich gegen einen isolierten HTTP-Server geprüft, einschließlich EOF-DELETE und UTF-8.
- Statische Prüfung: 33 Pascal-Units, 49 MCP-Werkzeuge, Schemas, BOM/CRLF, Zeilenlayout und Standardpaketgrenze.
- PE-Importprüfung von Package/Bridge ohne zusätzliche GetIt-BPLs; nur mit Delphi gelieferte Pakete bzw. Windows-DLLs.
- Zwei unabhängige Codeprüfungen ohne blockierende Befunde; git diff --check sauber und Manifest aktualisiert.

Die unveränderte Registrierungslogik hatte im vorherigen Stand 98 erfolgreiche native Checks pro Plattform. Diese Tests wurden in diesem Schritt nicht erneut ausgeführt.

## Praktische Grenzen

Der vollständige Package-Build wurde weiterhin für Win32 ausgeführt. Die Win64-Protokolltests arbeiten mit IDE-Stubs und ersetzen keinen 64-Bit-IDE-Test.
Das neue BPL wurde nicht in die laufende IDE geladen. Echte Clientkonfigurationen, GetIt-Installationen und Designer-/Debuggerzustände wurden nicht verändert.
Die bekannten Compilerhinweise W1002 zum Windows-Flag und H2077 zum initialen YAML-Ergebniswert bleiben; keine Buildfehler.

Ressourcen- und Prompt-Endpunkte sowie eine gemeinsame Toolregistry sind dokumentierte Ideen und noch nicht implementiert.
