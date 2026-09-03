# DAI 1.1.12 – Prüfbericht

## Änderung

DAI 1.1.12 erweitert ausschließlich den MCP-Bereich des IDE-Options-Frames:

- neben dem Portfeld wird der aus `CDAIDefaultPort` gelesene Standardwert angezeigt
- das Bearer-Token-Feld wurde von 500 auf 330 Pixel verkürzt
- rechts daneben befindet sich die Schaltfläche `Token erzeugen`
- die bestehende GUID-basierte Erzeugung aus `TDAISettings.GenerateToken` wird wiederverwendet
- der Schaltflächen-Hinweis erinnert daran, eine vorhandene Codex-Konfiguration anschließend erneut zu registrieren

## Token-Verhalten

Ein Bearer-Token muss keine GUID sein. DAI behält die bisherige GUID-Erzeugung als Standard bei, weil der erzeugte Wert ohne geschweifte Klammern und mit
kleingeschriebenen Hexadezimalzeichen problemlos als HTTP-Bearer-Token und in der verwalteten TOML-Konfiguration verwendet werden kann.

Die Schaltfläche ändert zunächst nur `FTokenEdit.Text`. Die persistente Einstellung, der laufende MCP-Server und die Codex-Registrierung werden dadurch
nicht sofort verändert. Erst Anwenden beziehungsweise OK speichert den neuen Wert. Für eine bereits registrierte Codex-Konfiguration ist danach zusätzlich
`Registrieren` aufzurufen.

## Relevanter Code

```pascal
with NewLabel(Self, Format('Standard: %d', [CDAIDefaultPort]), FPortEdit.Left + FPortEdit.Width + 12, LTop + 4) do
  Font.Color := clGrayText;

FTokenEdit.Width := 330;

FGenerateTokenButton := TButton.Create(Self);
FGenerateTokenButton.Parent := Self;
FGenerateTokenButton.Left := FTokenEdit.Left + FTokenEdit.Width + 12;
FGenerateTokenButton.Top := LTop;
FGenerateTokenButton.Width := 158;
FGenerateTokenButton.Caption := 'Token erzeugen';
FGenerateTokenButton.OnClick := GenerateTokenClicked;
```

```pascal
procedure TDAIOptionsFrame.GenerateTokenClicked(Sender: TObject);
begin
  FTokenEdit.Text := TDAISettings.Instance.GenerateToken;
  FTokenEdit.SetFocus;
  FTokenEdit.SelectAll;
end;
```

## Statische Prüfung

- 27 Pascal-Units erkannt
- 39 MCP-Werkzeuge erkannt
- alle PAS-Dateien besitzen UTF-8 mit BOM
- keine Tabulatorzeichen in Pascal-Sourcen
- keine gemischten Zeilenenden innerhalb einer Pascal-Datei
- maximale Pascal-Zeilenlänge: höchstens 180 Zeichen
- DPK- und DPROJ-Referenzen vollständig
- DPROJ-XML gültig
- Options-Frame ohne eigene ScrollBox und weiterhin mit `Align := alTop; Height := LTop`
- Standardport-Anzeige, verkürztes Tokenfeld, Ereignisverknüpfung und öffentliche Token-Erzeugung statisch geprüft

## Einschränkung

In dieser Umgebung ist keine Delphi-13-Toolchain vorhanden. Ein Binärbuild mit `dcc32.exe` und ein Laufzeittest im IDE-Optionsdialog konnten daher nicht
ausgeführt werden.
