# DAI 1.1.8 – Prüfbericht

## Fehlerbild

Das Package wurde von Delphi 13 erfolgreich kompiliert. Beim Installieren beziehungsweise Laden brach jedoch die Package-Registrierung mit folgender Exception ab:

```text
EIdCouldNotBindSocket: Socket konnte nicht gebunden werden.
```

Der Fehler entsteht während `RegisterPackageWizard(TDAIWizard.Create)`. Der Konstruktor des Wizards startet bisher unmittelbar die DAI-Laufzeit. Ist DAI aktiviert, führt der Aufrufpfad zu:

```text
TDAIWizard.Create
  TDAIRuntime.Start
    TDAIRuntime.ApplySettings
      TDAIMCPServer.ApplySettings
        TDAIMCPServer.Start
          FHTTPServer.Active := True
```

War der konfigurierte Listener `127.0.0.1:7331` bereits belegt, ließ `FHTTPServer.Active := True` die Indy-Exception bis zur IDE durchlaufen. Damit scheiterte nicht nur der optionale MCP-Server, sondern die vollständige Package-Registrierung.

## Typische Ursache

Der Port kann insbesondere durch eine andere Delphi-Instanz mit geladenem DAI-Package, eine noch laufende ältere DAI-Instanz oder einen anderen lokalen Prozess belegt sein. DAI darf in diesem Fall nicht stillschweigend auf einen anderen Port wechseln: Die Codex-Konfiguration enthält den fest registrierten Port und könnte sonst unbemerkt mit der falschen IDE-Instanz verbunden werden.

## Korrektur

### `h5u.DAI.MCP.Server.pas`

- `Start`, `Stop` und `ApplySettings` liefern jetzt `Boolean`.
- `EIdCouldNotBindSocket` wird ausdrücklich über `IdException` behandelt.
- Ein fehlgeschlagener Start setzt `LastError`, bereinigt einen teilweise aktivierten Listener und gibt `False` zurück.
- Auch sonstige Start- und Stop-Exceptions werden in einen nichtfatalen Serverstatus übersetzt.
- Ein automatischer Portwechsel findet nicht statt.

Das zentrale Verhalten lautet sinngemäß:

```pascal
try
  FHTTPServer.Active := True;
  Result := True;
except
  on E: EIdCouldNotBindSocket do
  begin
    ResetAfterFailedStart;
    FLastError := Format(...);
    TDAILog.Error(FLastError);
    Result := False;
  end;
end;
```

### `h5u.DAI.Runtime.pas`

- `ApplySettings` ist jetzt eine Funktion und fängt sämtliche Fehler der optionalen Serverkomponente ab.
- `LastServerError` stellt den letzten Start- oder Stopfehler für die IDE-Oberfläche bereit.
- `Start` lässt Fehler beim Laden beziehungsweise Anwenden der Servereinstellungen nicht bis zur Package-Registrierung durchlaufen.

### `h5u.DAI.Wizard.pas`

Der Aufruf von `TDAIRuntime.Start` ist zusätzlich durch einen eigenen `try/except`-Block geschützt. Damit bleibt die OpenToolsAPI-Erweiterung selbst dann geladen, wenn die optionale MCP-Laufzeit unerwartet fehlschlägt.

### `h5u.DAI.Log.pas`

Fehler von `IOTAMessageServices.AddTitleMessage` dürfen nicht ihrerseits die Package-Registrierung abbrechen. Das Logging fällt daher auf `OutputDebugString` zurück.

### `h5u.DAI.Options.Frame.pas`

Die Optionsseite zeigt jetzt einen eigenen Serverstatus:

```text
Status: deaktiviert.
Status: aktiv auf http://127.0.0.1:<Port>/mcp
Status: nicht aktiv. <konkrete Fehlermeldung>
```

Beim Übernehmen der Optionen wird ein fehlgeschlagener Neustart zusätzlich als Warnung angezeigt. Nach Auswahl eines freien Ports kann der Server unmittelbar erneut gestartet werden.

## Manuelle Sofortdiagnose

Der Prozess, der Port 7331 belegt, kann unter PowerShell ermittelt werden:

```powershell
$listener = Get-NetTCPConnection -LocalPort 7331 -State Listen
$listener | Select-Object LocalAddress, LocalPort, OwningProcess
$listener | ForEach-Object { Get-Process -Id $_.OwningProcess }
```

Um die bisherige Package-Version trotz belegtem Port installieren zu können, kann der automatische Serverstart vorübergehend deaktiviert werden:

```cmd
reg add "HKCU\Software\Embarcadero\BDS\37.0\DAI" /v Enabled /t REG_DWORD /d 0 /f
```

## Statische und negative Prüfungen

`Scripts/verify.py` prüft zusätzlich:

- die ausdrückliche Behandlung von `EIdCouldNotBindSocket`,
- die Listener-Bereinigung nach fehlgeschlagenem Start,
- die nichtwerfende Laufzeitbehandlung,
- die zusätzliche Absicherung in `TDAIWizard`,
- den Logging-Fallback auf `OutputDebugString`,
- und die Anzeige von `LastServerError` in der Optionsseite.

Ausgeführte Negativtests:

```text
EIdCouldNotBindSocket-Behandlung entfernt: erkannt
Runtime-ApplySettings nicht mehr als geschützte Boolean-Funktion: erkannt
Fehleranzeige in der Optionsseite entfernt: erkannt
```

## Dateiformate und Formatierung

- Alle 25 PAS-Dateien sind UTF-8 mit BOM.
- Vorhandenes einheitliches CRLF beziehungsweise LF bleibt je Datei erhalten.
- Keine Pascal-Datei enthält vermischte Zeilenenden.
- Keine Pascal-Source enthält Tabulatorzeichen.
- Die maximale Pascal-Zeilenlänge beträgt 180 Zeichen.
- Methodensignaturen und Property-Deklarationen bleiben bis zur Grenze von 180 Zeichen in einer Zeile.
- Die DFM-Datei bleibt von der PAS-Encoding-Regel ausgenommen.

## Prüfergebnis

```text
Pascal-Units:                         25
MCP-Werkzeuge:                        34
PAS-Dateien mit UTF-8-BOM:            25 von 25
Gemischte Pascal-Zeilenenden:          0
Tabulatoren in Pascal-Sourcen:         0
Maximal erlaubte Pascal-Zeilenlänge: 180
Tatsächlich längste Pascal-Zeile:    179
DPK-/DPROJ-Referenzen:               vollständig
DPROJ-XML:                           gültig
Statische Prüfung:                   bestanden
Negative Portkonflikttests:          bestanden
```

## Abgrenzung

Die vorherige Version erreichte nach Benutzerangabe erfolgreich die Delphi-13-Package-Installation; der Fehler entstand erst in der Registrierungsprozedur beim Aktivieren des Indy-Listeners. DAI 1.1.8 konnte in dieser Umgebung mangels Delphi-13-Toolchain nicht erneut mit `dcc32.exe` gebaut werden. Die geänderten Signaturen und verwendeten Indy-Typen müssen daher abschließend einmal in der vorhandenen Delphi-13-Installation kompiliert werden.
