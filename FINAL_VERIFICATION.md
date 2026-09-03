# DAI 1.1.15 – Prüfbericht

## Anlass

In `h5u.DAI.WinAPI.TCP.pas` wurden die Ergebnisse von `GetProcAddress` bisher über einen linkseitigen Cast der Prozedurvariablen zugewiesen:

```pascal
Pointer(LQueryFullProcessImageNameW) := GetProcAddress(...);
Pointer(LGetExtendedTcpTable) := GetProcAddress(...);
```

Bei Codepointer- beziehungsweise Prozedurvariablen soll die Variable selbst nicht nach `Pointer` gecastet und anschließend beschrieben werden. Stattdessen wird das Ergebnis von `GetProcAddress` auf den konkreten Prozedurtyp gecastet und der typisierten Variablen direkt zugewiesen.

## Korrektur

Die beiden Zuweisungen lauten jetzt:

```pascal
LQueryFullProcessImageNameW := TQueryFullProcessImageNameW(GetProcAddress(LKernelModule, 'QueryFullProcessImageNameW'));
LGetExtendedTcpTable := TGetExtendedTcpTable(GetProcAddress(LModule, 'GetExtendedTcpTable'));
```

Damit bleibt die linke Seite eine echte Prozedurvariable. Der Cast befindet sich ausschließlich auf der rechten Seite und beschreibt den von `GetProcAddress` gelieferten Codepointer mit seiner tatsächlichen Aufrufsignatur.

Im gesamten DAI-Quellverzeichnis gibt es keine weitere Zuweisung der Form `Pointer(<Prozedurvariable>) := GetProcAddress(...)`.

## Statische Prüfung

`Scripts/verify.py` prüft nun zusätzlich:

- `LGetExtendedTcpTable` darf auf der linken Seite nicht nach `Pointer` gecastet werden.
- `LQueryFullProcessImageNameW` darf auf der linken Seite nicht nach `Pointer` gecastet werden.
- beide Variablen müssen direkt aus einem auf ihren konkreten Prozedurtyp gecasteten `GetProcAddress`-Ergebnis zugewiesen werden.

## Allgemeine Prüfung

- 27 Pascal-Units erkannt
- 39 MCP-Werkzeuge erkannt
- alle PAS-Dateien besitzen UTF-8 mit BOM
- keine Pascal-Datei enthält Tabulatorzeichen
- keine Pascal-Datei enthält vermischte Zeilenenden
- maximale Pascal-Zeilenlänge: 179 von erlaubten 180 Zeichen
- DPK- und DPROJ-Referenzen vollständig
- DPROJ-XML gültig
- internes SHA-256-Manifest vollständig erzeugt

## Negativtests

Die statische Prüfung wurde gegen zwei absichtlich fehlerhafte Varianten ausgeführt:

1. `Pointer(LQueryFullProcessImageNameW) := GetProcAddress(...)`
2. `Pointer(LGetExtendedTcpTable) := GetProcAddress(...)`

Beide Varianten wurden erwartungsgemäß zurückgewiesen.

## Einschränkung

In dieser Umgebung ist keine Delphi-13-Toolchain vorhanden. Die Änderung muss daher einmal lokal mit Delphi 13 kompiliert werden. Sie betrifft ausschließlich die zwei dynamischen WinAPI-Codepointer-Zuweisungen sowie die zugehörige statische Regressionserkennung.
