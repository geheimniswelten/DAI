# DAI 1.1.14 – Prüfbericht

## Anlass

Codex erkannte den konfigurierten DAI-Server und sendete den statischen HTTP-Header `Authorization: Bearer …`. Indy verwarf das ihm unbekannte Autorisierungsschema jedoch bereits während des Parsens der HTTP-Anfrage mit `EIdHTTPUnsupportedAuthorisationScheme`. Der MCP-Handler von DAI wurde deshalb gar nicht erreicht.

Daneben befanden sich die von DAI erzeugten Codex- und Skill-Dateien wegen `TPath.GetHomePath` unter `%APPDATA%`. Für die von Codex verwendeten persönlichen Pfade muss dagegen `%USERPROFILE%` verwendet werden.

## Bearer-Authentifizierung

`TDAIMCPServer` registriert nun vor dem Aktivieren des Indy-Servers:

```pascal
FHTTPServer.OnParseAuthentication := HandleParseAuthentication;
```

Der Handler erkennt das Schema case-insensitiv, übernimmt den unveränderten Tokenwert und markiert Bearer gegenüber Indy als verarbeitet:

```pascal
procedure TDAIMCPServer.HandleParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: string; var VUsername, VPassword: string; var VHandled: Boolean);
begin
  if not SameText(AAuthType, 'Bearer') then
    Exit;

  VUsername := '';
  VPassword := Trim(AAuthData);
  VHandled := True;
end;
```

Erst im normalen DAI-MCP-Handler erfolgt die eigentliche Authentifizierung. Dabei wird das Schema case-insensitiv und der Token als case-sensitiver, undurchsichtiger Wert geprüft:

```pascal
Result := ARequestInfo.AuthExists and SameText(ARequestInfo.AuthType, 'Bearer') and SameStr(ARequestInfo.AuthPassword, AExpectedToken);
```

Ein fehlender oder falscher Token führt kontrolliert zu HTTP 401 mit:

```text
WWW-Authenticate: Bearer realm="DAI"
```

## Registrierungsverzeichnisse

DAI verwendet jetzt ausdrücklich das Windows-Benutzerprofil:

```text
%USERPROFILE%\.codex\config.toml
%USERPROFILE%\.agents\skills\delphi-ide\SKILL.md
```

Ein Verzeichnis `.skills` wird von DAI nicht verwendet. Der Skill enthält nur Arbeitsanweisungen und keine Zugangsdaten. Port und Bearer-Token werden ausschließlich im verwalteten DAI-Block der Codex-Konfiguration gespeichert.

Beim Registrieren und Deregistrieren werden zusätzlich ausschließlich eindeutig von DAI markierte Altinhalte unter `%APPDATA%` entfernt. Fremde Konfigurationen und nicht von DAI verwaltete Skills bleiben unangetastet.

## Erforderliche Schritte nach dem Update

Da der bisherige Token während der Diagnose in einem Werkzeugprotokoll sichtbar wurde, muss er ersetzt werden:

1. DAI 1.1.14 kompilieren und installieren.
2. Delphi vollständig neu starten, damit die neue BPL geladen wird.
3. Unter `Tools → Options → Third Party → DAI` auf `Token erzeugen` klicken.
4. Auf `Registrieren` klicken. Dadurch werden Server, Registry und `%USERPROFILE%\.codex\config.toml` auf denselben Token aktualisiert.
5. Codex vollständig neu starten beziehungsweise den MCP-Server in Codex neu starten.
6. Mit `/mcp` oder `codex mcp list` prüfen, ob `dai` verbunden ist.

Der Token darf nicht in einen Chat oder in Diagnoseausgaben kopiert werden.

## Statische und strukturelle Prüfung

- 27 Pascal-Units erkannt
- 39 MCP-Werkzeuge erkannt
- alle PAS-Dateien besitzen UTF-8 mit BOM
- 4 PAS-Dateien verwenden CRLF, 23 verwenden LF
- keine Datei enthält vermischte Zeilenenden
- keine Tabulatorzeichen in Pascal-Sourcen
- maximale Pascal-Zeilenlänge: 179 von erlaubten 180 Zeichen
- DPK- und DPROJ-Referenzen vollständig
- DPROJ-XML gültig
- erzeugter Codex-TOML-Block mit Python `tomllib` erfolgreich geparst
- Bearer-Schema wird über `OnParseAuthentication` registriert
- geparste Indy-Felder `AuthType` und `AuthPassword` werden für die Tokenprüfung verwendet
- Tokenvergleich bleibt case-sensitiv
- Codex- und Skill-Pfade verwenden `%USERPROFILE%`
- sichere Bereinigung ausschließlich eigener Altregistrierungen unter `%APPDATA%`
- internes SHA-256-Manifest vollständig erzeugt

## Negativtests

Die Regressionstests lehnen folgende absichtlich erzeugte Fehler erwartungsgemäß ab:

1. fehlende Zuweisung von `OnParseAuthentication`
2. Bearer-Handler ohne `VHandled := True`
3. erneute Verwendung von `TPath.GetHomePath` für die Codex-Konfiguration

## Einschränkung

In dieser Umgebung ist keine Delphi-13-Toolchain vorhanden. DAI 1.1.13 wurde vom Benutzer bereits fehler-, warnungs- und hinweisfrei kompiliert und in der IDE installiert. Die neuen Delphi-Änderungen in 1.1.14 müssen einmal lokal mit Delphi 13 kompiliert und anschließend gegen die laufende Codex-App getestet werden.
