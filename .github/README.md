# DAI – Delphi AI (MCP-Server für Delphi-IDE)

Clients: Codex, Claude Code (CLI / VS Code), Claude Desktop, Eigent, Gemini CLI / Code Assist, ~~Gemini Desktop~~, Hermes, LM Studio and OpenClaw
<details>
  <summary><b>Client-List</b></summary>

  | Client                    | DAI connection    | Setup/Register |
  |---------------------------|-------------------|----------------|
  | Codex App / CLI / IDE     | HTTP              | via DAI        |
  | Claude Code CLI / VS Code | HTTP              | via DAI        |
  | Claude Desktop            | **STDIO**+Bridge  | via DAI        |
  | Gemini CLI / Code Assist, VS-Code-AgentMode   | HTTP | via DAI |
  | Hermes                    | HTTP              | via DAI        |
  | LM Studio                 | HTTP              | via DAI        |
  | OpenClaw                  | HTTP              | via DAI        |
  | Eigent                    | HTTP or **STDIO** | manually via its MCP settings |
  | Gemini Desktop / Consumer | -                 | **not implemented** |
</details>

Home: <https://geheimniswelten.github.io/#dai>

Download: ~~<https://github.com/geheimniswelten/DAI/releases>~~

### Install

**Script** : compile and register (Delphi 11 ➔ 13)
* .\\Build+Register.cmd -> .\\Build.ps1 

**Manual** : open in Delphi and "install"
* .\\DAI.dproj

**only Register** : 
* copy .\\Build\\Win32\\Debug\\Bpl\\DAI???.bpl
* copy .\\Build\\Win32\\Debug\\Bpl\\DAI.McpBridge.exe in same directory (if MCP-Client uses STDIO)
* register in HKEY_CURRENT_USER\\Software\\Embarcadero\\BDS\\??.0\\Known Packages -> C:\\...\\DAI???.bpl = DelphiAI (DAI)

---

<details>
  <summary><b>[EN] English</b></summary>

  - **Manage the Delphi-IDE and create, modify or debug your Applications with AI**
  - Tested with Delphi 11 and 13
    <details>
      <summary><b>Details</b></summary>
      | Function group | Tools | Functions |
      |---|---:|---|
      | IDE status and control | 2 | Read status; control IDE windows and close the IDE |
      | Windows and dialogs | 5 | Inspect windows and active dialogs; operate dialog buttons |
      | Logs and messages | 4 | Read compiler/debugger logs; display messages, input dialogs and hints |
      | Projects and project group | 7 | Create, open, activate, save and remove projects from the group; read project information and build context |
      | File lists and search | 4 | List project/directory files; search names and contents, including RegEx |
      | Files and editor | 7 | List open files; read, write, open, activate, close and remove files from projects |
      | Reference sources | 3 | List Delphi, demo and GetIt paths; list and read reference files |
      | Unit and form creation | 2 | Create units and VCL form units |
      | Form designer | 3 | Open the designer or form text; inspect components, selection and properties |
      | Code Insight | 4 | Query provider status, symbol definitions, symbol help and diagnostics |
      | Project options | 4 | Read configurations, platforms and option values; set or remove values |
      | Find and open options | 2 | Find and open IDE/project options; navigate and focus fields, including through IDE Insight |
      | Packages | 3 | Install and uninstall built packages; check installation status |
      | Compilation | 4 | Compile projects and the project group; run MSBuild and DCC32 |
      | Execution | 2 | Run projects with or without the debugger; stop execution |
      | Debugger control and overview | 4 | Read status, threads and stack; pause, resume and step |
      | Debugger expressions | 5 | Read, evaluate and modify cursor expressions; query results and invoke native watch/inspector actions |
      | Breakpoints | 3 | List, set, update and remove breakpoints |
      | Client and skill registration | 6 | Configure, inspect and remove MCP client connections and the Codex skill |
    </details>
</details>

---

<details open>
  <summary><b>[DE] Deutsch</b></summary>

  - **Verwalte die Delphi-IDE und erstelle, bearbeite oder debugge deine Applications with AI**
  - Delphi 11 und 13 getestet
  - Quellcodes durchsuchen (readonly): OpenTooolsAPI, Delphi-Sources (RTL/VCL/FMX), Delphi-Demos (wenn installiert), installierte GitHub-Repos und optional auch weitere Verzeichnisse (z.B. eigne Codes-Sammlungen)
    <details>
      <summary><b>Details</b></summary>
      | Funktionsgruppe | Tools | Funktionen |
      |---|---:|---|
      | IDE-Status und Steuerung | 2 | Status abfragen; IDE-Fenster steuern und IDE schließen |
      | Fenster und Dialoge | 5 | Fenster und aktive Dialoge untersuchen; Dialogbuttons bedienen |
      | Logs und Meldungen | 4 | Compiler-/Debuggerlogs lesen; Meldungen, Eingabedialoge und Hinweise anzeigen |
      | Projekte und Projektgruppe | 7 | Projekte erstellen, öffnen, aktivieren, speichern und aus der Gruppe entfernen; Projektinfos und Buildkontext lesen |
      | Dateilisten und Suche | 4 | Projekt-/Verzeichnisdateien auflisten; Namen und Inhalte suchen, auch mit RegEx |
      | Dateien und Editor | 7 | Geöffnete Dateien auflisten; Dateien lesen, schreiben, öffnen, aktivieren, schließen und aus Projekten entfernen |
      | Referenzquellen | 3 | Delphi-, Demo- und GetIt-Pfade sowie Referenzdateien auflisten und lesen |
      | Units und Formulare erstellen | 2 | Neue Units und VCL-Formular-Units erstellen |
      | Formdesigner | 3 | Designer oder Formulartext öffnen; Komponenten, Auswahl und Eigenschaften lesen |
      | Code Insight | 4 | Providerstatus, Symboldefinitionen, Symbolhilfe und Diagnosen abfragen |
      | Projektoptionen | 4 | Konfigurationen, Plattformen und Optionswerte lesen; Werte setzen oder entfernen |
      | Optionen suchen und öffnen | 2 | IDE-/Projektoptionen suchen und öffnen; Navigation und Feldfokus, auch über IDE Insight |
      | Packages | 3 | Bereits gebaute Packages installieren, deinstallieren und Installationsstatus prüfen |
      | Kompilieren | 4 | Projekte und Projektgruppe kompilieren; MSBuild und DCC32 ausführen |
      | Ausführen | 2 | Projekte mit oder ohne Debugger starten und stoppen |
      | Debuggersteuerung und Übersicht | 4 | Status, Threads und Stack lesen; pausieren, fortsetzen und Einzelschritte ausführen |
      | Debugger-Ausdrücke | 5 | Cursorausdrücke lesen, auswerten und ändern; Ergebnisstatus und native Watch-/Inspektoraktionen |
      | Haltepunkte | 3 | Haltepunkte auflisten, setzen, aktualisieren und entfernen |
      | Client- und Skillregistrierung | 6 | MCP-Clientanbindungen und Codex-Skill einrichten, prüfen und entfernen |
    </details>
</details>

---

<!-- ![status](Status-activity.png) -->

<!-- Install Temporary: <br>
![temporary](Install-temporarily.png) -->

