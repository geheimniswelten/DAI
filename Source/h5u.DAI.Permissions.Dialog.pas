unit h5u.DAI.Permissions.Dialog;

interface

uses
  System.JSON,
  h5u.DAI.Types;

type
  TDAIPermissionPromptResult = record
  public
    Level: TDAIPermissionLevel;
    ApplyGlobally: Boolean;
  end;

  TDAIPermissionDialog = class sealed
  public
    class function Ask(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext):
      TDAIPermissionPromptResult; static;
    class function SelectForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext; const ACurrentLevel: TDAIPermissionLevel;
      out AResult: TDAIPermissionPromptResult): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Forms,
  Winapi.Windows,
  h5u.DAI.Windows.Inspection,
  h5u.DAI.Localization;

type
  TPermissionWindowObserver = class
  private
    FHandle: HWND;
  public
    destructor Destroy; override;
    procedure DialogCreated(ASender: TObject);
    procedure DialogDestroyed(ASender: TObject);
  end;

const
  mrDAINever = 1101;
  mrDAIDeny = 1102;
  mrDAIOnce = 1103;
  mrDAISession = 1104;
  mrDAIAlways = 1105;
  mrDAIAsk = 1106;

destructor TPermissionWindowObserver.Destroy;
begin
  TDAIWindowService.UnregisterPermissionWindow(FHandle);
  inherited;
end;

procedure TPermissionWindowObserver.DialogCreated(ASender: TObject);
begin
  FHandle := TTaskDialog(ASender).Handle;
  TDAIWindowService.RegisterPermissionWindow(FHandle);
end;

procedure TPermissionWindowObserver.DialogDestroyed(ASender: TObject);
begin
  TDAIWindowService.UnregisterPermissionWindow(FHandle);
  FHandle := 0;
end;

procedure AddCommandButton(const ADialog: TTaskDialog; const ACaption: string; const AHint: string; const AModalResult: TModalResult; const ADefault: Boolean = False);
var
  LButton: TTaskDialogButtonItem;
begin
  LButton := TTaskDialogButtonItem(ADialog.Buttons.Add);
  LButton.Caption := ACaption;
  LButton.CommandLinkHint := AHint;
  LButton.ModalResult := AModalResult;
  LButton.Default := ADefault;
end;

function PermissionCategoryCaption(const ACategory: TDAIPermissionCategory): string;
begin
  case ACategory of
    pcReferenceRead:
      Result := DAIText(
        'Delphi-/GetIt-Sourcen und IDE-Optionen lesen',
        'Read Delphi/GetIt sources and IDE options',
        'Lire les sources Delphi/GetIt et les options de l’EDI',
        'Delphi/GetIt ソースと IDE オプションの読み取り');
    pcIDEOptions:
      Result := DAIText(
        'IDE-Optionen ändern',
        'Change IDE options',
        'Modifier les options de l’EDI',
        'IDE オプションの変更');
    pcProjectRead:
      Result := DAIText(
        'Projekt und Projektdateien lesen',
        'Read the project and its files',
        'Lire le projet et ses fichiers',
        'プロジェクトとプロジェクトファイルの読み取り');
    pcProjectWrite:
      Result := DAIText(
        'Projekt und Projektdateien ändern',
        'Change the project and its files',
        'Modifier le projet et ses fichiers',
        'プロジェクトとプロジェクトファイルの変更');
    pcCompile:
      Result := DAIText(
        'Kompilieren',
        'Compile',
        'Compiler',
        'コンパイル');
    pcExecute:
      Result := DAIText(
        'Projekt ausführen und debuggen',
        'Run and debug the project',
        'Exécuter et déboguer le projet',
        'プロジェクトの実行とデバッグ');
  else
    Result := DAIText(
      'Unbekannte Funktionalität',
      'Unknown capability',
      'Fonction inconnue',
      '不明な機能');
  end;
end;

function PermissionOperationCaption(const AOperation: string): string;
var
  LCaption: string;

  function Matches(const AGerman, AEnglish, AFrench, AJapanese: string; const APrefix: Boolean = False): Boolean;
  begin
    if APrefix then
      Result := Copy(AOperation, 1, Length(AGerman)) = AGerman
    else
      Result := AOperation = AGerman;
    if Result then
    begin
      LCaption := DAIText(AGerman, AEnglish, AFrench, AJapanese);
      if APrefix then
        LCaption := LCaption + Copy(AOperation, Length(AGerman) + 1, MaxInt);
    end;
  end;

begin
  // Only DAI-authored operation text is translated. Technical suffixes and
  // unknown caller-provided operations are preserved exactly.
  if Matches(
    'Delphi-/GetIt-Deklarationsindex lesen',
    'Read the Delphi/GetIt declaration index',
    'Lire l’index des déclarations Delphi/GetIt',
    'Delphi/GetIt 宣言インデックスの読み取り') then
    Exit(LCaption);
  if Matches(
    'Gemeinsamen DAI-Deklarationsindex erstellen, aktualisieren oder löschen',
    'Create, update or delete the shared DAI declaration index',
    'Créer, actualiser ou supprimer l’index partagé des déclarations DAI',
    '共有 DAI 宣言インデックスの作成、更新、削除') then
    Exit(LCaption);
  if Matches(
    'Deklarationsindex und seine Projektquellen lesen',
    'Read the declaration index and its project sources',
    'Lire l’index des déclarations et les sources de son projet',
    '宣言インデックスとプロジェクトソースの読み取り') then
    Exit(LCaption);
  if Matches(
    'Projekt-Deklarationsindex erstellen, aktualisieren oder löschen',
    'Create, update or delete the project declaration index',
    'Créer, actualiser ou supprimer l’index des déclarations du projet',
    'プロジェクト宣言インデックスの作成、更新、削除') then
    Exit(LCaption);
  if Matches(
    'Status der Delphi-IDE lesen',
    'Read the Delphi IDE status',
    'Lire l’état de l’EDI Delphi',
    'Delphi IDE の状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'Verfügbare OTA-KI-Provider lesen',
    'Read the available OTA AI providers',
    'Lire les fournisseurs IA OTA disponibles',
    '利用可能な OTA AI プロバイダーの読み取り') then
    Exit(LCaption);
  if Matches(
    'Status der Deklarationsindizes lesen',
    'Read the declaration index status',
    'Lire l’état des index des déclarations',
    '宣言インデックスの状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'Delphi-IDE-Fenster steuern: ',
    'Control the Delphi IDE window: ',
    'Contrôler la fenêtre de l’EDI Delphi : ',
    'Delphi IDE ウィンドウの操作: ', True) then
    Exit(LCaption);
  if Matches(
    'Delphi-IDE normal schließen',
    'Close the Delphi IDE normally',
    'Fermer normalement l’EDI Delphi',
    'Delphi IDE の通常終了') then
    Exit(LCaption);
  if Matches(
    'IDE-Compiler- oder Debuggerlog lesen',
    'Read the IDE compiler or debugger log',
    'Lire le journal du compilateur ou du débogueur de l’EDI',
    'IDE のコンパイラーまたはデバッガーログの読み取り') then
    Exit(LCaption);
  if Matches(
    'Fenster des Debuggerprozesses lesen',
    'Read the debugger process windows',
    'Lire les fenêtres du processus débogué',
    'デバッグ対象プロセスのウィンドウの読み取り') then
    Exit(LCaption);
  if Matches(
    'Fenster und Controls der IDE lesen',
    'Read IDE windows and controls',
    'Lire les fenêtres et contrôles de l’EDI',
    'IDE のウィンドウとコントロールの読み取り') then
    Exit(LCaption);
  if Matches(
    'Referenzquelltexte durchsuchen',
    'Search reference source files',
    'Rechercher dans les sources de référence',
    '参照ソースファイルの検索') then
    Exit(LCaption);
  if Matches(
    'Projektgruppenverzeichnis durchsuchen',
    'Search the project group directory',
    'Rechercher dans le dossier du groupe de projets',
    'プロジェクトグループフォルダーの検索') then
    Exit(LCaption);
  if Matches(
    'Projektquelltexte durchsuchen',
    'Search project source files',
    'Rechercher dans les sources du projet',
    'プロジェクトソースファイルの検索') then
    Exit(LCaption);
  if Matches(
    'Liste der aktuell geöffneten Dateien lesen',
    'Read the list of currently open files',
    'Lire la liste des fichiers actuellement ouverts',
    '現在開いているファイル一覧の読み取り') then
    Exit(LCaption);
  if Matches(
    'Projekte und Projektpfade der aktuellen Projektgruppe lesen',
    'Read projects and their paths in the current project group',
    'Lire les projets et leurs chemins dans le groupe de projets actuel',
    '現在のプロジェクトグループにあるプロジェクトとパスの読み取り') then
    Exit(LCaption);
  if Matches(
    'Dateien eines Projekts lesen',
    'Read the files of a project',
    'Lire les fichiers d’un projet',
    'プロジェクトファイルの読み取り') then
    Exit(LCaption);
  if Matches(
    'Dateien im Projektverzeichnis auflisten',
    'List files in the project directory',
    'Lister les fichiers du dossier du projet',
    'プロジェクトフォルダーのファイル一覧の取得') then
    Exit(LCaption);
  if Matches(
    'Freigegebenes Verzeichnis auflisten',
    'List an authorized directory',
    'Lister un dossier autorisé',
    '許可されたフォルダーの一覧の取得') then
    Exit(LCaption);
  if Matches(
    'Delphi-, Demo-, GetIt- und zusätzliche Referenzpfade lesen',
    'Read Delphi, demo, GetIt and additional reference paths',
    'Lire les chemins de référence Delphi, démos, GetIt et supplémentaires',
    'Delphi、デモ、GetIt、追加の参照パスの読み取り') then
    Exit(LCaption);
  if Matches(
    'Dateien eines schreibgeschützten Referenzpfads auflisten',
    'List files in a read-only reference path',
    'Lister les fichiers d’un chemin de référence en lecture seule',
    '読み取り専用参照パスのファイル一覧の取得') then
    Exit(LCaption);
  if Matches(
    'Dateiinhalt lesen',
    'Read file contents',
    'Lire le contenu d’un fichier',
    'ファイル内容の読み取り') then
    Exit(LCaption);
  if Matches(
    'Status der IDE-Code-Insight-Provider lesen',
    'Read the IDE Code Insight provider status',
    'Lire l’état des fournisseurs Code Insight de l’EDI',
    'IDE Code Insight プロバイダーの状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'Semantische Definition über IDE Code Insight ermitteln',
    'Resolve a semantic definition through IDE Code Insight',
    'Résoudre une définition sémantique via Code Insight de l’EDI',
    'IDE Code Insight による意味的な定義の取得') then
    Exit(LCaption);
  if Matches(
    'Help Insight für eine Quelltextposition lesen',
    'Read Help Insight for a source position',
    'Lire Help Insight pour une position dans le code source',
    'ソース位置の Help Insight の読み取り') then
    Exit(LCaption);
  if Matches(
    'Error-Insight-Diagnosen einer IDE-Datei lesen',
    'Read Error Insight diagnostics for an IDE file',
    'Lire les diagnostics Error Insight d’un fichier de l’EDI',
    'IDE ファイルの Error Insight 診断の読み取り') then
    Exit(LCaption);
  if Matches(
    'Aktiven Projekt- und Compilerkontext lesen',
    'Read the active project and compiler context',
    'Lire le contexte du projet actif et du compilateur',
    'アクティブなプロジェクトとコンパイラーのコンテキストの読み取り') then
    Exit(LCaption);
  if Matches(
    'Geöffnetes Gruppenprojekt aktivieren',
    'Activate an open project in the project group',
    'Activer un projet ouvert du groupe de projets',
    'プロジェクトグループで開いているプロジェクトのアクティブ化') then
    Exit(LCaption);
  if Matches(
    'Konfigurationen des aktiven Projekts lesen',
    'Read the active project configurations',
    'Lire les configurations du projet actif',
    'アクティブなプロジェクトの構成の読み取り') then
    Exit(LCaption);
  if Matches(
    'Optionen und Vererbung des aktiven Projekts lesen',
    'Read the active project options and inheritance',
    'Lire les options et l’héritage du projet actif',
    'アクティブなプロジェクトのオプションと継承設定の読み取り') then
    Exit(LCaption);
  if Matches(
    'Lokale Projektoption setzen',
    'Set a local project option',
    'Définir une option locale du projet',
    'プロジェクトのローカルオプションの設定') then
    Exit(LCaption);
  if Matches(
    'Lokale Projektoption entfernen und Vererbung wiederherstellen',
    'Remove a local project option and restore inheritance',
    'Supprimer une option locale du projet et rétablir l’héritage',
    'プロジェクトのローカルオプションの削除と継承設定の復元') then
    Exit(LCaption);
  if Matches(
    'Projektdatei bearbeiten',
    'Edit a project file',
    'Modifier un fichier du projet',
    'プロジェクトファイルの編集') then
    Exit(LCaption);
  if Matches(
    'Projekt in der aktuellen Projektgruppe erstellen',
    'Create a project in the current project group',
    'Créer un projet dans le groupe de projets actuel',
    '現在のプロジェクトグループでのプロジェクトの作成') then
    Exit(LCaption);
  if Matches(
    'Projekt öffnen',
    'Open a project',
    'Ouvrir un projet',
    'プロジェクトを開く') then
    Exit(LCaption);
  if Matches(
    'Projekt speichern',
    'Save a project',
    'Enregistrer un projet',
    'プロジェクトの保存') then
    Exit(LCaption);
  if Matches(
    'Projekt aus der aktuellen Projektgruppe entfernen',
    'Remove a project from the current project group',
    'Retirer un projet du groupe de projets actuel',
    '現在のプロジェクトグループからのプロジェクトの削除') then
    Exit(LCaption);
  if Matches(
    'Unit erstellen und zum Projekt hinzufügen',
    'Create a unit and add it to the project',
    'Créer une unité et l’ajouter au projet',
    'ユニットの作成とプロジェクトへの追加') then
    Exit(LCaption);
  if Matches(
    'Form-Unit erstellen und zum Projekt hinzufügen',
    'Create a form unit and add it to the project',
    'Créer une unité de fiche et l’ajouter au projet',
    'フォームユニットの作成とプロジェクトへの追加') then
    Exit(LCaption);
  if Matches(
    'Datei in der IDE öffnen',
    'Open a file in the IDE',
    'Ouvrir un fichier dans l’EDI',
    'IDE でファイルを開く') then
    Exit(LCaption);
  if Matches(
    'Datei in der IDE aktivieren',
    'Activate a file in the IDE',
    'Activer un fichier dans l’EDI',
    'IDE でのファイルのアクティブ化') then
    Exit(LCaption);
  if Matches(
    'Datei in der IDE schließen',
    'Close a file in the IDE',
    'Fermer un fichier dans l’EDI',
    'IDE でファイルを閉じる') then
    Exit(LCaption);
  if Matches(
    'Datei aus dem Projekt entfernen',
    'Remove a file from the project',
    'Retirer un fichier du projet',
    'プロジェクトからのファイルの削除') then
    Exit(LCaption);
  if Matches(
    'Formular in den DFM-Textmodus umschalten',
    'Switch a form to DFM text mode',
    'Passer une fiche en mode texte DFM',
    'フォームを DFM テキストモードに切り替える') then
    Exit(LCaption);
  if Matches(
    'Formdesigner und veröffentlichte Eigenschaften lesen',
    'Read the form designer and published properties',
    'Lire le concepteur de fiches et les propriétés publiées',
    'フォームデザイナーと公開プロパティの読み取り') then
    Exit(LCaption);
  if Matches(
    'Formdesigner in der IDE anzeigen',
    'Show the form designer in the IDE',
    'Afficher le concepteur de fiches dans l’EDI',
    'IDE でのフォームデザイナーの表示') then
    Exit(LCaption);
  if Matches(
    'Komponenten und Kategorien der IDE-Palette lesen',
    'Read IDE palette components and categories',
    'Lire les composants et catégories de la palette de l’EDI',
    'IDE パレットのコンポーネントとカテゴリの読み取り') then
    Exit(LCaption);
  if Matches(
    'Komponenten und Eigenschaften des Formdesigners lesen',
    'Read form designer components and properties',
    'Lire les composants et propriétés du concepteur de fiches',
    'フォームデザイナーのコンポーネントとプロパティの読み取り') then
    Exit(LCaption);
  if Matches(
    'Komponenten im Formdesigner bearbeiten oder auswählen',
    'Edit or select form designer components',
    'Modifier ou sélectionner des composants dans le concepteur de fiches',
    'フォームデザイナーのコンポーネントの編集と選択') then
    Exit(LCaption);
  if Matches(
    'Debugger-, Prozess- und Threadstatus lesen',
    'Read debugger, process and thread status',
    'Lire l’état du débogueur, des processus et des threads',
    'デバッガー、プロセス、スレッドの状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'Ausdruck im aktiven Quelleditor lesen',
    'Read an expression in the active source editor',
    'Lire une expression dans l’éditeur de code source actif',
    'アクティブなソースエディターの式の読み取り') then
    Exit(LCaption);
  if Matches(
    'Debuggerausdruck und seinen Wert lesen',
    'Read a debugger expression and its value',
    'Lire une expression du débogueur et sa valeur',
    'デバッガーの式と値の読み取り') then
    Exit(LCaption);
  if Matches(
    'Status und Ergebnis einer Debuggerauswertung lesen',
    'Read the status and result of a debugger evaluation',
    'Lire l’état et le résultat d’une évaluation du débogueur',
    'デバッガーによる式の評価の状態と結果の読み取り') then
    Exit(LCaption);
  if Matches(
    'Status der nativen Debuggeraktion lesen',
    'Read the native debugger action status',
    'Lire l’état de l’action native du débogueur',
    'デバッガーのネイティブ操作の状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'Ziel der nativen Debuggeraktion lesen',
    'Read the native debugger action target',
    'Lire la cible de l’action native du débogueur',
    'デバッガーのネイティブ操作の対象の読み取り') then
    Exit(LCaption);
  if Matches(
    'Native Debuggeraktion ausführen: ',
    'Execute a native debugger action: ',
    'Exécuter une action native du débogueur : ',
    'デバッガーのネイティブ操作の実行: ', True) then
    Exit(LCaption);
  if Matches(
    'Stacktrace eines angehaltenen Debuggerthreads lesen',
    'Read the stack trace of a paused debugger thread',
    'Lire la pile d’appels d’un thread débogué suspendu',
    '一時停止中のデバッグ対象スレッドのスタックトレースの読み取り') then
    Exit(LCaption);
  if Matches(
    'Threads der ausgewählten Debuggerprozesse lesen',
    'Read the threads of the selected debugger processes',
    'Lire les threads des processus débogués sélectionnés',
    '選択したデバッグ対象プロセスのスレッドの読み取り') then
    Exit(LCaption);
  if Matches(
    'Quellhaltepunkte lesen',
    'Read source breakpoints',
    'Lire les points d’arrêt du code source',
    'ソースブレークポイントの読み取り') then
    Exit(LCaption);
  if Matches(
    'Quellhaltepunkt erstellen oder ändern',
    'Create or modify a source breakpoint',
    'Créer ou modifier un point d’arrêt du code source',
    'ソースブレークポイントの作成と変更') then
    Exit(LCaption);
  if Matches(
    'Quellhaltepunkt entfernen',
    'Remove a source breakpoint',
    'Supprimer un point d’arrêt du code source',
    'ソースブレークポイントの削除') then
    Exit(LCaption);
  if Matches(
    'Debugger steuern: ',
    'Control the debugger: ',
    'Contrôler le débogueur : ',
    'デバッガーの操作: ', True) then
    Exit(LCaption);
  if Matches(
    'MCP-Registrierung der KI-Clients prüfen',
    'Check AI client MCP registration',
    'Vérifier l’inscription MCP des clients IA',
    'AI クライアントの MCP 登録の確認') then
    Exit(LCaption);
  if Matches(
    'DAI beim KI-Client registrieren: ',
    'Register DAI with the AI client: ',
    'Inscrire DAI auprès du client IA : ',
    'AI クライアントへの DAI の登録: ', True) then
    Exit(LCaption);
  if Matches(
    'DAI beim KI-Client deregistrieren: ',
    'Unregister DAI from the AI client: ',
    'Désinscrire DAI du client IA : ',
    'AI クライアントからの DAI の登録解除: ', True) then
    Exit(LCaption);
  if Matches(
    'Optionsnamen und IDE-Insight-Metadaten durchsuchen',
    'Search option names and IDE Insight metadata',
    'Rechercher les noms d’options et les métadonnées IDE Insight',
    'オプション名と IDE Insight メタデータの検索') then
    Exit(LCaption);
  if Matches(
    'Status der Optionsnavigation lesen',
    'Read the option navigation status',
    'Lire l’état de la navigation vers les options',
    'オプションへの移動状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'IDE-Optionsdialog öffnen und Option auswählen',
    'Open the IDE options dialog and select an option',
    'Ouvrir les options de l’EDI et sélectionner une option',
    'IDE オプションダイアログを開いてオプションを選択') then
    Exit(LCaption);
  if Matches(
    'Projektoptionsdialog öffnen und Option auswählen',
    'Open the project options dialog and select an option',
    'Ouvrir les options du projet et sélectionner une option',
    'プロジェクトオプションダイアログを開いてオプションを選択') then
    Exit(LCaption);
  if Matches(
    'Package-Ziel und Installationsstatus lesen',
    'Read the package target and installation status',
    'Lire la cible du paquet et son état d’installation',
    'パッケージのターゲットとインストール状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'Package in dieser IDE installieren',
    'Install a package in this IDE',
    'Installer un paquet dans cet EDI',
    'この IDE へのパッケージのインストール') then
    Exit(LCaption);
  if Matches(
    'Package-Code in dieser IDE laden',
    'Load package code in this IDE',
    'Charger le code d’un paquet dans cet EDI',
    'この IDE へのパッケージコードの読み込み') then
    Exit(LCaption);
  if Matches(
    'Package aus dieser IDE deinstallieren',
    'Uninstall a package from this IDE',
    'Désinstaller un paquet de cet EDI',
    'この IDE からのパッケージのアンインストール') then
    Exit(LCaption);
  if Matches(
    'Package-Code in dieser IDE entladen',
    'Unload package code from this IDE',
    'Décharger le code d’un paquet de cet EDI',
    'この IDE からのパッケージコードの読み込み解除') then
    Exit(LCaption);
  if Matches(
    'Projekt kompilieren',
    'Compile a project',
    'Compiler un projet',
    'プロジェクトのコンパイル') then
    Exit(LCaption);
  if Matches(
    'Projekt der Projektgruppe kompilieren',
    'Compile a project in the project group',
    'Compiler un projet du groupe de projets',
    'プロジェクトグループにあるプロジェクトのコンパイル') then
    Exit(LCaption);
  if Matches(
    'Projekt starten',
    'Start a project',
    'Démarrer un projet',
    'プロジェクトの起動') then
    Exit(LCaption);
  if Matches(
    'Projekt vor dem Start kompilieren',
    'Compile a project before starting it',
    'Compiler un projet avant de le démarrer',
    '起動前のプロジェクトのコンパイル') then
    Exit(LCaption);
  if Matches(
    'Laufendes Projekt stoppen',
    'Stop the running project',
    'Arrêter le projet en cours d’exécution',
    '実行中のプロジェクトの停止') then
    Exit(LCaption);
  if Matches(
    'Aktiven modalen VCL-Dialog lesen',
    'Read the active modal VCL dialog',
    'Lire la boîte de dialogue VCL modale active',
    'アクティブな VCL モーダルダイアログの読み取り') then
    Exit(LCaption);
  if Matches(
    'Button im erkannten VCL-Dialog betätigen',
    'Press a button in the identified VCL dialog',
    'Appuyer sur un bouton de la boîte de dialogue VCL identifiée',
    '検出された VCL ダイアログのボタンを押す') then
    Exit(LCaption);
  if Matches(
    'VCL-Dialogaktion ausführen',
    'Execute a VCL dialog action',
    'Exécuter une action de boîte de dialogue VCL',
    'VCL ダイアログ操作の実行') then
    Exit(LCaption);
  if Matches(
    'Erkannten VCL-Dialog über ModalResult schließen',
    'Close the identified VCL dialog through ModalResult',
    'Fermer la boîte de dialogue VCL identifiée via ModalResult',
    'ModalResult による検出済み VCL ダイアログの終了') then
    Exit(LCaption);
  if Matches(
    'VCL-Dialogabschluss ausführen',
    'Complete a VCL dialog',
    'Terminer une boîte de dialogue VCL',
    'VCL ダイアログの終了操作の実行') then
    Exit(LCaption);
  if Matches(
    'MessageBox in der Delphi-IDE anzeigen',
    'Show a MessageBox in the Delphi IDE',
    'Afficher une MessageBox dans l’EDI Delphi',
    'Delphi IDE での MessageBox の表示') then
    Exit(LCaption);
  if Matches(
    'InputBox in der Delphi-IDE anzeigen',
    'Show an InputBox in the Delphi IDE',
    'Afficher une InputBox dans l’EDI Delphi',
    'Delphi IDE での InputBox の表示') then
    Exit(LCaption);
  if Matches(
    'BalloonHint in der Delphi-IDE anzeigen',
    'Show a BalloonHint in the Delphi IDE',
    'Afficher une BalloonHint dans l’EDI Delphi',
    'Delphi IDE での BalloonHint の表示') then
    Exit(LCaption);
  if Matches(
    'Status der Codex- und Skill-Registrierung lesen',
    'Read the Codex and skill registration status',
    'Lire l’état des inscriptions de Codex et des skills',
    'Codex とスキルの登録状態の読み取り') then
    Exit(LCaption);
  if Matches(
    'DAI in .codex und .agents registrieren',
    'Register DAI in .codex and .agents',
    'Inscrire DAI dans .codex et .agents',
    '.codex と .agents への DAI の登録') then
    Exit(LCaption);
  if Matches(
    'DAI aus .codex und .agents deregistrieren',
    'Unregister DAI from .codex and .agents',
    'Désinscrire DAI de .codex et .agents',
    '.codex と .agents からの DAI の登録解除') then
    Exit(LCaption);
  if Matches(
    'MSBuild.exe direkt ausführen',
    'Run MSBuild.exe directly',
    'Exécuter MSBuild.exe directement',
    'MSBuild.exe の直接実行') then
    Exit(LCaption);
  if Matches(
    'DCC32.exe direkt ausführen',
    'Run DCC32.exe directly',
    'Exécuter DCC32.exe directement',
    'DCC32.exe の直接実行') then
    Exit(LCaption);
  Result := AOperation;
end;

function BuildDialogText(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext): string;
var
  LContextText: string;
begin
  LContextText := '';
  if Trim(AContext.ThreadId) <> '' then
    LContextText := sLineBreak + sLineBreak + DAIText(
      'KI-Chat: ',
      'AI chat: ',
      'Conversation IA : ',
      'AI チャット: ') + AContext.ThreadId
  else if Trim(AContext.TransportSessionId) <> '' then
    LContextText := sLineBreak + sLineBreak + DAIText(
      'MCP-Sitzung: ',
      'MCP session: ',
      'Session MCP : ',
      'MCP セッション: ') + AContext.TransportSessionId
  else
    LContextText := sLineBreak + sLineBreak + DAIText(
      'Hinweis: Der anfragende KI-Chat konnte nicht eindeutig identifiziert werden.',
      'Note: The requesting AI chat could not be uniquely identified.',
      'Remarque : la conversation IA à l’origine de la demande n’a pas pu être identifiée.',
      '注: 要求元の AI チャットを一意に識別できませんでした。');
  if AContext.ClientName <> '' then
    LContextText := LContextText + sLineBreak + DAIText(
      'Client: ',
      'Client: ',
      'Client : ',
      'クライアント: ') + AContext.ClientName;

  Result := PermissionCategoryCaption(ACategory) + sLineBreak + sLineBreak + PermissionOperationCaption(AOperation);
  if Trim(AResource) <> '' then
    Result := Result + sLineBreak + sLineBreak + DAIText(
      'Ziel: ',
      'Target: ',
      'Cible : ',
      '対象: ') + AResource;
  if DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '') then
    Result := Result + sLineBreak + sLineBreak + DAIText(
      'Berechtigungsbereich: global',
      'Permission scope: global',
      'Portée de l’autorisation : globale',
      'アクセス許可の範囲: グローバル')
  else
    Result := Result + sLineBreak + sLineBreak + DAIText(
      'Projekt: ',
      'Project: ',
      'Projet : ',
      'プロジェクト: ') + AContext.ProjectKey;
  Result := Result + LContextText;
end;

function BuildOptionsText(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
begin
  Result := PermissionCategoryCaption(ACategory) + sLineBreak + sLineBreak;
  if DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '') then
    Result := Result + DAIText(
      'Globaler Standard für Projekte ohne eigene Festlegung.',
      'Global default for projects without an override.',
      'Valeur globale par défaut pour les projets sans règle spécifique.',
      '個別設定のないプロジェクトに適用するグローバル既定値です。')
  else
    Result := Result + DAIText(
      'Aktuelles Projekt: ',
      'Current project: ',
      'Projet actuel : ',
      '現在のプロジェクト: ') + AContext.ProjectKey;
  Result := Result + sLineBreak + sLineBreak + DAIText(
    'Die Auswahl wird erst beim Speichern der IDE-Optionen oder beim Registrieren übernommen.',
    'The selection is applied only when saving the IDE options or registering.',
    'Le choix est appliqué uniquement lors de l’enregistrement des options de l’EDI ou de l’inscription.',
    '選択内容は IDE オプションの保存時または登録時に適用されます。');
end;

function ExecutePermissionDialog(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext;
  const AForOptions: Boolean; const ACurrentLevel: TDAIPermissionLevel; out AResult: TDAIPermissionPromptResult): Boolean;
var
  LDialog: TTaskDialog;
  LObserver: TPermissionWindowObserver;
  LScopeText: string;
  LSessionCaption: string;
  LSessionHint: string;
begin
  Result := False;
  AResult.Level := plDeny;
  AResult.ApplyGlobally := DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '');

  LDialog := TTaskDialog.Create(nil);
  LObserver := nil;
  try
    LObserver := TPermissionWindowObserver.Create;
    LDialog.OnDialogCreated := LObserver.DialogCreated;
    LDialog.OnDialogDestroyed := LObserver.DialogDestroyed;
    LDialog.Caption := 'DAI';
    if AForOptions then
    begin
      if DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '') then
      begin
        LDialog.Title := DAIText(
          'Berechtigung festlegen – global',
          'Set permission – global',
          'Définir l’autorisation – globale',
          'アクセス許可の設定 – グローバル');
        LScopeText := DAIText(
          'als globalen Standard',
          'as the global default',
          'comme règle globale par défaut',
          'グローバル既定として');
        LSessionCaption := DAIText(
          'Für diese IDE-Sitzung',
          'For this IDE session',
          'Pour cette session de l’EDI',
          'この IDE セッションのみ');
        LSessionHint := DAIText(
          'Für alle KI-Chats und Projekte dieser IDE bis zum Zurücksetzen der Sitzungsfreigaben oder zum Schließen der IDE zulassen.',
          'Allow for all AI chats and projects in this IDE until session permissions are reset or the IDE is closed.',
          'Autoriser pour toutes les conversations IA et tous les projets jusqu’à la réinitialisation des droits de session ou la fermeture de l’EDI.',
          'セッションの許可をリセットするか IDE を閉じるまで、この IDE のすべての AI チャットとプロジェクトに許可します。');
      end
      else
      begin
        LDialog.Title := DAIText(
          'Berechtigung festlegen – aktuelles Projekt',
          'Set permission – current project',
          'Définir l’autorisation – projet actuel',
          'アクセス許可の設定 – 現在のプロジェクト');
        LScopeText := DAIText(
          'im gewählten Projekt- oder globalen Bereich',
          'in the selected project or global scope',
          'dans la portée projet ou globale choisie',
          '選択したプロジェクトまたはグローバル範囲で');
        LSessionCaption := DAIText(
          'Für diese Session',
          'For this session',
          'Pour cette session',
          'このセッションのみ');
        LSessionHint := DAIText(
          'Für alle KI-Chats im gewählten Projekt- oder globalen Bereich bis zum Zurücksetzen oder zum Schließen der IDE zulassen.',
          'Allow for all AI chats in the selected scope until permissions are reset or the IDE is closed.',
          'Autoriser pour toutes les conversations IA dans la portée choisie jusqu’à la réinitialisation des droits ou la fermeture de l’EDI.',
          '許可をリセットするか IDE を閉じるまで、選択した範囲のすべての AI チャットに許可します。') +
          DAIText(
            ' Bei Projekt-Auswahl endet die Freigabe auch beim Schließen des Projekts.',
            ' For project scope, closing the project also ends the permission.',
            ' Pour la portée projet, fermer le projet met également fin à l’autorisation.',
            ' プロジェクト範囲の場合、プロジェクトを閉じると許可も終了します。');
      end;
      LDialog.Text := BuildOptionsText(ACategory, AContext);
    end
    else
    begin
      LDialog.Title := DAIText(
        'Zugriff durch Delphi AI',
        'Delphi AI access request',
        'Demande d’accès de Delphi AI',
        'Delphi AI のアクセス要求');
      LDialog.Text := BuildDialogText(ACategory, AOperation, AResource, AContext);
      if DAIPermissionCategoryIsGlobal(ACategory) or (Trim(AContext.ProjectKey) = '') then
      begin
        LScopeText := DAIText(
          'als globalen Standard',
          'as the global default',
          'comme règle globale par défaut',
          'グローバル既定として');
        LSessionHint := DAIText(
          'Für diesen KI-Chat bis zum Zurücksetzen der Sitzungsfreigaben oder zum Schließen der Delphi-IDE zulassen.',
          'Allow for this AI chat until session permissions are reset or the Delphi IDE is closed.',
          'Autoriser pour cette conversation IA jusqu’à la réinitialisation des droits de session ou la fermeture de l’EDI Delphi.',
          'セッションの許可をリセットするか Delphi IDE を閉じるまで、この AI チャットに許可します。');
      end
      else
      begin
        LScopeText := DAIText(
          'im gewählten Projekt- oder globalen Bereich',
          'in the selected project or global scope',
          'dans la portée projet ou globale choisie',
          '選択したプロジェクトまたはグローバル範囲で');
        LSessionHint := DAIText(
          'Für diesen KI-Chat im gewählten Projekt- oder globalen Bereich bis zum Zurücksetzen oder zum Schließen der IDE zulassen.',
          'Allow for this AI chat in the selected scope until permissions are reset or the IDE is closed.',
          'Autoriser pour cette conversation IA dans la portée choisie jusqu’à la réinitialisation des droits ou la fermeture de l’EDI.',
          '許可をリセットするか IDE を閉じるまで、選択した範囲でこの AI チャットに許可します。') +
          DAIText(
            ' Bei Projekt-Auswahl endet die Freigabe auch beim Schließen des Projekts.',
            ' For project scope, closing the project also ends the permission.',
            ' Pour la portée projet, fermer le projet met également fin à l’autorisation.',
            ' プロジェクト範囲の場合、プロジェクトを閉じると許可も終了します。');
      end;
    end;
    LDialog.MainIcon := tdiShield;
    LDialog.CommonButtons := [];
    LDialog.Flags := [tfAllowDialogCancellation, tfUseCommandLinks];
    if not AResult.ApplyGlobally then
    begin
      LDialog.VerificationText := DAIText(
        'Auswahl für globales Setting',
        'Apply selection globally',
        'Appliquer le choix globalement',
        '選択内容をグローバルに適用');
      LDialog.Text := LDialog.Text + sLineBreak + sLineBreak +
        DAIText(
          'Ohne Häkchen gilt die Auswahl für dieses Projekt. Global setzt dessen eigene Festlegung auf Default zurück.',
          'Without the check mark, the selection applies to this project. A global selection resets its project override to Default.',
          'Sans coche, le choix s’applique à ce projet. Un choix global rétablit sa règle spécifique sur Default.',
          'チェックしない場合はこのプロジェクトに適用します。グローバルに適用すると、プロジェクトの個別設定は Default に戻ります。');
    end;

    AddCommandButton(
      LDialog,
      DAIText(
        'Nie erlauben',
        'Never allow',
        'Ne jamais autoriser',
        '常に拒否'),
      Format(DAIText(
        'Diese Funktionalität %s dauerhaft sperren.',
        'Permanently block this capability %s.',
        'Bloquer définitivement cette fonction %s.',
        'この機能を%s常に拒否します。'), [LScopeText]),
      mrDAINever,
      AForOptions and (ACurrentLevel = plNever)
    );
    if AForOptions then
    begin
      AddCommandButton(
        LDialog,
        DAIText(
          'Nachfragen',
          'Ask',
          'Demander',
          '確認する'),
        Format(DAIText(
          'Für Zugriffe %s jeweils nachfragen.',
          'Ask for each access request %s.',
          'Demander pour chaque accès %s.',
          '%sアクセスのたびに確認します。'), [LScopeText]),
        mrDAIAsk,
        ACurrentLevel = plAsk
      );
      AddCommandButton(
        LDialog,
        DAIText(
          'Verweigern – nächste Anfrage',
          'Deny – next request',
          'Refuser – prochaine demande',
          '次の要求を拒否'),
        DAIText(
          'Die nächste passende Anfrage ablehnen; danach wieder die gespeicherte Berechtigung verwenden.',
          'Deny the next matching request, then use the saved permission again.',
          'Refuser la prochaine demande correspondante, puis réutiliser l’autorisation enregistrée.',
          '次の該当する要求を拒否し、その後は保存されたアクセス許可に戻ります。'),
        mrDAIDeny,
        ACurrentLevel = plDeny
      );
      AddCommandButton(
        LDialog,
        DAIText(
          'Nur einmal – nächste Anfrage',
          'Allow once – next request',
          'Autoriser une fois – prochaine demande',
          '次の要求を一度だけ許可'),
        DAIText(
          'Die nächste passende Anfrage zulassen; danach wieder die gespeicherte Berechtigung verwenden.',
          'Allow the next matching request, then use the saved permission again.',
          'Autoriser la prochaine demande correspondante, puis réutiliser l’autorisation enregistrée.',
          '次の該当する要求を許可し、その後は保存されたアクセス許可に戻ります。'),
        mrDAIOnce,
        ACurrentLevel = plOnce
      );
      AddCommandButton(
        LDialog,
        LSessionCaption,
        LSessionHint,
        mrDAISession,
        ACurrentLevel = plSession
      );
    end
    else
    begin
      AddCommandButton(
        LDialog,
        DAIText(
          'Verweigern',
          'Deny',
          'Refuser',
          '拒否'),
        DAIText(
          'Nur diese konkrete Anfrage ablehnen. Bei der nächsten Anfrage erneut fragen.',
          'Deny only this request. Ask again for the next request.',
          'Refuser uniquement cette demande. Redemander pour la suivante.',
          'この要求のみ拒否します。次の要求で再度確認します。'),
        mrDAIDeny
      );
      AddCommandButton(
        LDialog,
        DAIText(
          'Nur diesmal',
          'Allow once',
          'Autoriser une fois',
          '今回のみ許可'),
        DAIText(
          'Nur diese konkrete Anfrage zulassen.',
          'Allow only this request.',
          'Autoriser uniquement cette demande.',
          'この要求のみ許可します。'),
        mrDAIOnce,
        True
      );
      AddCommandButton(
        LDialog,
        DAIText(
          'Für diese Session',
          'For this session',
          'Pour cette session',
          'このセッションのみ'),
        LSessionHint,
        mrDAISession
      );
    end;
    AddCommandButton(
      LDialog,
      DAIText(
        'Immer erlauben',
        'Always allow',
        'Toujours autoriser',
        '常に許可'),
      Format(DAIText(
        'Diese Funktionalität %s dauerhaft zulassen.',
        'Permanently allow this capability %s.',
        'Autoriser définitivement cette fonction %s.',
        'この機能を%s常に許可します。'), [LScopeText]),
      mrDAIAlways,
      AForOptions and (ACurrentLevel = plAlways)
    );

    if not LDialog.Execute then
      Exit;

    AResult.ApplyGlobally := AResult.ApplyGlobally or (tfVerificationFlagChecked in LDialog.Flags);
    case LDialog.ModalResult of
      mrDAINever:
        AResult.Level := plNever;
      mrDAIDeny:
        AResult.Level := plDeny;
      mrDAIAsk:
        AResult.Level := plAsk;
      mrDAIOnce:
        AResult.Level := plOnce;
      mrDAISession:
        AResult.Level := plSession;
      mrDAIAlways:
        AResult.Level := plAlways;
    else
      Exit;
    end;
    Result := True;
  finally
    try
      LDialog.Free;
    finally
      LObserver.Free;
    end;
  end;
end;

class function TDAIPermissionDialog.Ask(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext):
  TDAIPermissionPromptResult;
begin
  ExecutePermissionDialog(ACategory, AOperation, AResource, AContext, False, plOnce, Result);
end;

class function TDAIPermissionDialog.SelectForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext;
  const ACurrentLevel: TDAIPermissionLevel; out AResult: TDAIPermissionPromptResult): Boolean;
begin
  Result := ExecutePermissionDialog(ACategory, '', '', AContext, True, ACurrentLevel, AResult);
end;

end.
