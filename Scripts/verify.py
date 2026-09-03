from __future__ import annotations

import hashlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Source"
MAX_LINE_LENGTH = 180

REQUIRED_TOOLS = {
    "ide_status",
    "open_files_list",
    "projects_list",
    "project_files_list",
    "project_directory_files_list",
    "directory_files_list",
    "reference_roots_list",
    "reference_files_list",
    "file_read",
    "reference_file_read",
    "code_insight_status",
    "code_definition",
    "code_hover",
    "file_diagnostics",
    "project_context",
    "file_write",
    "project_create",
    "project_open",
    "project_save",
    "project_remove",
    "unit_create",
    "form_unit_create",
    "file_open",
    "file_activate",
    "file_close",
    "project_file_remove",
    "form_show_as_text",
    "project_compile",
    "project_group_compile",
    "project_run",
    "project_stop",
    "ui_message_box",
    "ui_input_box",
    "ui_balloon_hint",
    "codex_registration_status",
    "codex_register",
    "codex_unregister",
    "msbuild_execute",
    "dcc32_execute",
}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)




def read_project_text(path: Path) -> str:
    data = path.read_bytes()
    if path.suffix.lower() not in {".pas", ".dpk"}:
        return data.decode("utf-8-sig")
    if data.startswith(b"\xef\xbb\xbf"):
        return data.decode("utf-8-sig")
    try:
        return data.decode("ascii")
    except UnicodeDecodeError:
        return data.decode("cp1252")


def check_pascal_encodings(errors: list[str]) -> None:
    for path in sorted(SOURCE.glob("*.pas")):
        data = path.read_bytes()
        if not data.startswith(b"\xef\xbb\xbf"):
            fail(errors, f"{path.relative_to(ROOT)}: DAI-PAS-Dateien müssen als UTF-8 mit BOM ausgeliefert werden")
            continue
        try:
            data.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            fail(errors, f"{path.relative_to(ROOT)}: ungültiges UTF-8 mit BOM: {exc}")


def check_source_whitespace_and_line_endings(errors: list[str]) -> None:
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.dpk"]):
        data = path.read_bytes()
        body = data[3:] if data.startswith(b"\xef\xbb\xbf") else data
        for number, line in enumerate(read_project_text(path).splitlines(), start=1):
            if "\t" in line:
                fail(errors, f"{path.relative_to(ROOT)}:{number}: Tabulatoren sind in Pascal-Sourcen nicht erlaubt; zwei Leerzeichen verwenden")

        crlf_count = body.count(b"\r\n")
        lf_count = body.count(b"\n") - crlf_count
        cr_count = body.count(b"\r") - crlf_count
        if cr_count > 0 or (crlf_count > 0 and lf_count > 0):
            fail(errors, f"{path.relative_to(ROOT)}: gemischte oder alleinstehende CR-Zeilenenden sind nicht erlaubt")


def check_line_lengths(errors: list[str]) -> None:
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.dpk"]):
        for number, line in enumerate(read_project_text(path).splitlines(), start=1):
            if len(line) > MAX_LINE_LENGTH:
                fail(errors, f"{path.relative_to(ROOT)}:{number}: {len(line)} Zeichen")


ROUTINE_HEADER_START = re.compile(
    r"^(\s*)(?:(?:class)\s+)?(?:function|procedure|constructor|destructor)\s+([A-Za-z_][A-Za-z0-9_.]*)\b",
    re.IGNORECASE,
)


def find_routine_header_end(lines: list[str], start: int) -> int | None:
    parenthesis_depth = 0
    in_string = False
    for line_index in range(start, len(lines)):
        line = lines[line_index]
        character_index = 0
        while character_index < len(line):
            character = line[character_index]
            if character == "'":
                if in_string and character_index + 1 < len(line) and line[character_index + 1] == "'":
                    character_index += 2
                    continue
                in_string = not in_string
            elif not in_string:
                if character == "(":
                    parenthesis_depth += 1
                elif character == ")":
                    parenthesis_depth -= 1
                elif character == ";" and parenthesis_depth == 0:
                    return line_index
            character_index += 1
    return None


def normalized_declaration(lines: list[str]) -> str:
    indent_match = re.match(r"^(\s*)", lines[0])
    indent = indent_match.group(1) if indent_match else ""
    declaration = " ".join(line.strip() for line in lines)
    declaration = re.sub(r"\s+", " ", declaration).strip()
    declaration = re.sub(r"\(\s+", "(", declaration)
    declaration = re.sub(r"\s+\)", ")", declaration)
    declaration = re.sub(r"\s+;", ";", declaration)
    declaration = re.sub(r"\s+,", ",", declaration)
    declaration = re.sub(r"\s+:", ":", declaration)
    return indent + declaration


def check_declaration_layout(errors: list[str]) -> None:
    for path in sorted(SOURCE.glob("*.pas")):
        lines = read_project_text(path).splitlines()
        line_index = 0
        while line_index < len(lines):
            routine_match = ROUTINE_HEADER_START.match(lines[line_index])
            if routine_match and routine_match.group(2).lower() not in {"begin", "var"}:
                end_index = find_routine_header_end(lines, line_index)
                if end_index is not None:
                    declaration_lines = lines[line_index:end_index + 1]
                    if end_index > line_index and len(normalized_declaration(declaration_lines)) <= MAX_LINE_LENGTH:
                        fail(
                            errors,
                            f"{path.name}:{line_index + 1}: Methodensignatur wird vor {MAX_LINE_LENGTH} Zeichen unnötig umgebrochen",
                        )
                    line_index = end_index + 1
                    continue

            if re.match(r"^\s*property\b", lines[line_index], re.IGNORECASE):
                end_index = line_index
                while end_index < len(lines) and ";" not in lines[end_index]:
                    end_index += 1
                if end_index < len(lines) and end_index > line_index:
                    declaration_lines = lines[line_index:end_index + 1]
                    if len(normalized_declaration(declaration_lines)) <= MAX_LINE_LENGTH:
                        fail(
                            errors,
                            f"{path.name}:{line_index + 1}: Property-Deklaration wird vor {MAX_LINE_LENGTH} Zeichen unnötig umgebrochen",
                        )
                line_index = end_index + 1
                continue

            line_index += 1


def check_initialization_finalization(errors: list[str]) -> None:
    for path in sorted(SOURCE.glob("*.pas")):
        content = read_project_text(path)
        stripped, _ = strip_pascal_strings_and_comments(content)
        initialization_match = re.search(r"(?im)^\s*initialization\b", stripped)
        finalization_match = re.search(r"(?im)^\s*finalization\b", stripped)
        if finalization_match and (not initialization_match or initialization_match.start() > finalization_match.start()):
            fail(errors, f"{path.name}: finalization erfordert einen vorherigen initialization-Abschnitt")


def check_unit_names(errors: list[str]) -> None:
    for path in sorted(SOURCE.glob("*.pas")):
        if not path.name.startswith("h5u."):
            fail(errors, f"Pascal-Datei ohne h5u.-Präfix: {path.name}")
        content = read_project_text(path)
        match = re.search(r"(?im)^\s*unit\s+([A-Za-z0-9_.]+)\s*;", content)
        if not match:
            fail(errors, f"Keine Unit-Deklaration: {path.name}")
            continue
        if match.group(1).lower() != path.stem.lower():
            fail(errors, f"Unit/Dateiname abweichend: {match.group(1)} <> {path.stem}")



def read_dfm_text(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        return data.decode("utf-8-sig")
    try:
        return data.decode("ascii")
    except UnicodeDecodeError:
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError:
            return data.decode("cp1252")


def check_frame_resources(errors: list[str]) -> None:
    dproj_text = read_project_text(ROOT / "DAI.dproj")
    frame_pattern = re.compile(r"\b(T[A-Za-z_][A-Za-z0-9_]*)\s*=\s*class\s*\(\s*TFrame\s*\)", re.IGNORECASE)
    for path in sorted(SOURCE.glob("*.pas")):
        content = read_project_text(path)
        frame_classes = frame_pattern.findall(content)
        if not frame_classes:
            continue

        dfm_path = path.with_suffix(".dfm")
        if not re.search(r"\{\$R\s+\*\.dfm\}", content, flags=re.IGNORECASE):
            fail(errors, f"{path.name}: TFrame-Nachkomme benötigt {{$R *.dfm}}")
        if not dfm_path.is_file():
            fail(errors, f"{path.name}: passende DFM-Ressource fehlt: {dfm_path.name}")
            continue

        dfm_data = dfm_path.read_bytes()
        body = dfm_data[3:] if dfm_data.startswith(b"\xef\xbb\xbf") else dfm_data
        crlf_count = body.count(b"\r\n")
        lf_count = body.count(b"\n") - crlf_count
        cr_count = body.count(b"\r") - crlf_count
        if cr_count > 0 or (crlf_count > 0 and lf_count > 0):
            fail(errors, f"{dfm_path.name}: gemischte oder alleinstehende CR-Zeilenenden sind nicht erlaubt")

        reference_pattern = re.compile(
            rf'<DCCReference\s+Include="Source\\{re.escape(path.name)}">(.*?)</DCCReference>',
            flags=re.IGNORECASE | re.DOTALL,
        )
        reference_match = reference_pattern.search(dproj_text)
        if not reference_match:
            fail(errors, f"DAI.dproj: Frame-Unit {path.name} benötigt einen nicht selbstschließenden DCCReference-Eintrag")
            continue
        reference_body = reference_match.group(1)

        dfm_text = read_dfm_text(dfm_path)
        for frame_class in frame_classes:
            root_pattern = re.compile(
                rf"(?im)^\s*(?:object|inherited)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*{re.escape(frame_class)}\s*$"
            )
            root_match = root_pattern.search(dfm_text)
            if not root_match:
                fail(errors, f"{dfm_path.name}: Root-Komponente für {frame_class} fehlt")
                continue

            root_name = root_match.group(1)
            if not re.search(rf"<Form>{re.escape(root_name)}</Form>", reference_body, flags=re.IGNORECASE):
                fail(errors, f"DAI.dproj: Form-Metadatum für Root-Komponente {root_name} fehlt")

        if not re.search(r"<FormType>dfm</FormType>", reference_body, flags=re.IGNORECASE):
            fail(errors, f"DAI.dproj: FormType=dfm für {path.name} fehlt")
        if not re.search(r"<DesignClass>TFrame</DesignClass>", reference_body, flags=re.IGNORECASE):
            fail(errors, f"DAI.dproj: DesignClass=TFrame für {path.name} fehlt")

def check_package_references(errors: list[str]) -> None:
    dpk = read_project_text(ROOT / "DAI.dpk")
    for path in sorted(SOURCE.glob("*.pas")):
        expected = f"{path.stem} in 'Source\\{path.name}'"
        if expected.lower() not in dpk.lower():
            fail(errors, f"DAI.dpk referenziert {path.name} nicht korrekt")
    if "package DAI;" not in dpk:
        fail(errors, "Package heißt nicht DAI")


def check_dproj(errors: list[str]) -> None:
    try:
        tree = ET.parse(ROOT / "DAI.dproj")
    except ET.ParseError as exc:
        fail(errors, f"DAI.dproj ist kein gültiges XML: {exc}")
        return

    text = read_project_text(ROOT / "DAI.dproj")
    if "<MainSource>DAI.dpk</MainSource>" not in text:
        fail(errors, "DAI.dproj verwendet nicht DAI.dpk")
    for path in sorted(SOURCE.glob("*.pas")):
        reference = f'Source\\{path.name}'
        if reference.lower() not in text.lower():
            fail(errors, f"DAI.dproj referenziert {path.name} nicht")
    del tree


def check_tools(errors: list[str]) -> None:
    content = read_project_text(SOURCE / "h5u.DAI.MCP.Tools.pas")
    declared = set(re.findall(r"AddTool\s*\(\s*Result\s*,\s*'([^']+)'", content, flags=re.IGNORECASE | re.DOTALL))
    missing = sorted(REQUIRED_TOOLS - declared)
    extra = sorted(declared - REQUIRED_TOOLS)
    if missing:
        fail(errors, "Fehlende MCP-Werkzeuge: " + ", ".join(missing))
    if extra:
        fail(errors, "Unerwartete MCP-Werkzeuge: " + ", ".join(extra))


def check_old_names(errors: list[str]) -> None:
    old_names = ("CodexMCPIDE", "Codex MCP IDE", "CodexMCP.")
    for path in ROOT.rglob("*"):
        if path.resolve() == Path(__file__).resolve():
            continue
        if "__pycache__" in path.parts or path.suffix.lower() == ".pyc":
            continue
        if not path.is_file() or path.suffix.lower() in {".zip", ".sha256"}:
            continue
        try:
            content = read_project_text(path)
        except UnicodeDecodeError:
            continue
        for old_name in old_names:
            if old_name.lower() in content.lower():
                fail(errors, f"Altbezeichnung {old_name!r} in {path.relative_to(ROOT)}")

def check_referenced_units(errors: list[str]) -> None:
    available = {path.stem.lower() for path in SOURCE.glob("*.pas")}
    pattern = re.compile(r"\bh5u\.DAI(?:\.[A-Za-z0-9_]+)+")
    for path in SOURCE.glob("*.pas"):
        content = read_project_text(path)
        stripped, _ = strip_pascal_strings_and_comments(content)
        for token in pattern.findall(stripped):
            parts = token.split(".")
            candidates = [".".join(parts[:index]).lower() for index in range(len(parts), 1, -1)]
            if not any(candidate in available for candidate in candidates):
                fail(errors, f"{path.name}: referenzierte Unit fehlt: {token}")


def check_known_invalid_symbols(errors: list[str]) -> None:
    invalid_symbols = ("EFileExistsException", "EFileNotFoundException")
    unsuitable_file_exception_types = ("EFCreateError", "EFOpenError")
    for path in SOURCE.glob("*.pas"):
        content = read_project_text(path)
        for symbol in invalid_symbols:
            if re.search(rf"\b{re.escape(symbol)}\b", content):
                fail(errors, f"{path.name}: nicht vorhandener Delphi-Typ {symbol}")
        for symbol in unsuitable_file_exception_types:
            if re.search(rf"\b{re.escape(symbol)}\b", content):
                fail(errors, f"{path.name}: {symbol} nicht verwenden; die von EFileStreamError deklarierte Create-Signatur verdeckt Exception.Create(string)")


def check_dai_type_definitions(errors: list[str]) -> None:
    content = "\n".join(read_project_text(path) for path in SOURCE.glob("*.pas"))
    identifiers = set(re.findall(r"\b(?:TDAI|EDAI)[A-Za-z0-9_]*\b", content))
    definitions = set(re.findall(r"\b((?:TDAI|EDAI)[A-Za-z0-9_]*)\s*=\s*(?:class|record|interface|\()", content, re.IGNORECASE))
    definitions.update(re.findall(r"\b((?:TDAI|EDAI)[A-Za-z0-9_]*)\s*=\s*[^;]+;", content, re.IGNORECASE))
    for identifier in sorted(identifiers - definitions):
        fail(errors, f"DAI-Typ wird verwendet, aber nicht deklariert: {identifier}")


def direct_used_units(content: str) -> set[str]:
    return {
        match.lower()
        for match in re.findall(r"(?im)^\s*([A-Za-z0-9_.]+)\s*(?:,|;|\bin\s)", content)
    }


def check_required_uses(errors: list[str]) -> None:
    requirements = {
        "System.Classes": ("EInvalidOperation", "TThread", "TStreamReader"),
        "System.SysUtils": ("EArgumentException", "EArgumentOutOfRangeException", "EConvertError", "EDirectoryNotFoundException"),
        "Vcl.Dialogs": ("TTaskDialog", "TTaskDialogButtonItem", "TaskMessageDlg", "InputQuery"),
        "ToolsAPI": ("BorlandIDEServices", "IOTAModule", "IOTAProject", "INTAServices", "SplashScreenServices"),
    }
    for path in sorted(SOURCE.glob("*.pas")):
        content = read_project_text(path)
        used_units = direct_used_units(content)
        stripped, _ = strip_pascal_strings_and_comments(content)
        for unit_name, symbols in requirements.items():
            if any(re.search(rf"\b{re.escape(symbol)}\b", stripped) for symbol in symbols):
                if unit_name.lower() not in used_units:
                    fail(errors, f"{path.name}: {unit_name} fehlt für verwendete Typen/Funktionen")


def check_creator_definitions(errors: list[str]) -> None:
    path = SOURCE / "h5u.DAI.OTA.Creators.pas"
    if not path.is_file():
        fail(errors, "Creator-Unit h5u.DAI.OTA.Creators.pas fehlt")
        return
    content = read_project_text(path)
    required = (
        "TDAIModuleCreator",
        "TDAIProjectCreator",
        "TDAIProjectKind",
        "pkConsole",
        "pkVCL",
        "IOTAModuleCreator",
        "IOTAProjectCreator160",
        "IOTAProjectCreator190",
    )
    for symbol in required:
        if not re.search(rf"\b{re.escape(symbol)}\b", content):
            fail(errors, f"Creator-Unit deklariert oder implementiert {symbol} nicht")

def check_encoding_policy(errors: list[str]) -> None:
    files_content = read_project_text(SOURCE / "h5u.DAI.OTA.Files.pas")
    tools_content = read_project_text(SOURCE / "h5u.DAI.MCP.Tools.pas")
    encoding_content = read_project_text(SOURCE / "h5u.DAI.Text.Encoding.pas")

    if "TDAITextEncoding.PrepareWrite" not in files_content:
        fail(errors, "h5u.DAI.OTA.Files.pas: geschlossene Dateien werden nicht codierungserhaltend geschrieben")
    if re.search(r"TFile\.WriteAllText\s*\(\s*LFileName\s*,\s*AContent\s*,\s*TEncoding\.UTF8", files_content):
        fail(errors, "h5u.DAI.OTA.Files.pas: Dateiinhalt darf nicht pauschal als UTF-8 geschrieben werden")
    if "DFM-Dateien werden ausschließlich über den IDE-Textpuffer geändert" not in files_content:
        fail(errors, "h5u.DAI.OTA.Files.pas: DFM-Direktschreibschutz fehlt")
    if "SameText(TPath.GetExtension(LExpandedFileName), '.dfm')" not in tools_content:
        fail(errors, "h5u.DAI.MCP.Tools.pas: DFM-Schreibzugriffe müssen als IDE-Bearbeitung autorisiert werden")
    for required in (
        "tekANSI",
        "tekUTF8BOM",
        "CanEncodeWithSystemANSI",
        "NormalizeLineEndings",
        "PrepareText",
        "ResolveLineEndingKind",
        "IsDelphiTextFile",
        "UsesUTF8BOMByDefault",
    ):
        if required not in encoding_content:
            fail(errors, f"h5u.DAI.Text.Encoding.pas: Encoding-Policy fehlt: {required}")

    default_match = re.search(
        r"class function TDAITextEncoding\.UsesUTF8BOMByDefault.*?begin(.*?)end;",
        encoding_content,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not default_match or "'.pas'" not in default_match.group(1).lower():
        fail(errors, "h5u.DAI.Text.Encoding.pas: UTF-8 mit BOM muss der Standard für neue PAS-Dateien sein")
    elif "'.dfm'" in default_match.group(1).lower():
        fail(errors, "h5u.DAI.Text.Encoding.pas: Die PAS-Standardcodierung darf nicht auf DFM-Dateien angewendet werden")

    if not re.search(r"StringReplace\s*\(\s*Result\s*,\s*#9\s*,\s*'  '\s*,", encoding_content, flags=re.IGNORECASE):
        fail(errors, "h5u.DAI.Text.Encoding.pas: Pascal-Tabulatoren müssen beim Schreiben durch zwei Leerzeichen ersetzt werden")
    if not re.search(r"lekCR\s*,\s*lekMixed\s*:\s*Result\s*:=\s*lekCRLF", encoding_content, flags=re.IGNORECASE | re.DOTALL):
        fail(errors, "h5u.DAI.Text.Encoding.pas: gemischte Zeilenenden benötigen einen eindeutigen CRLF-Fallback")
    if "TDAITextEncoding.PrepareText(LFileName, AContent" not in files_content:
        fail(errors, "h5u.DAI.OTA.Files.pas: Editor-Schreibzugriffe müssen Zeilenenden und Source-Tabs normalisieren")


def check_code_insight_integration(errors: list[str]) -> None:
    path = SOURCE / "h5u.DAI.OTA.CodeInsight.pas"
    if not path.is_file():
        fail(errors, "Code-Insight-Unit h5u.DAI.OTA.CodeInsight.pas fehlt")
        return

    content = read_project_text(path)
    required = (
        "IOTACodeInsightServices",
        "IOTAAsyncCodeInsightManager",
        "IOTAAsyncCodeInsightManager290",
        "AsyncGotoDefinitionEx",
        "AsyncGetHintText",
        "AsyncOperationCanceled",
        "SetQueryContext(nil, nil)",
        "IOTAModuleErrors",
        "GetCompleteFileList",
        "DCC_UnitSearchPath",
        "TDAIOTA.RunOnMainThread",
        "TMonitor.Enter(GOperationLock)",
        "function MarkRequestCancelled",
        "if GState.Completed then",
        "if not MarkRequestCancelled(ARequestId) then",
    )
    for symbol in required:
        if symbol not in content:
            fail(errors, f"h5u.DAI.OTA.CodeInsight.pas: erforderliche Integration fehlt: {symbol}")

    if content.count("if LRequestId < 0 then") < 2:
        fail(errors, "h5u.DAI.OTA.CodeInsight.pas: ungültige Request-IDs müssen für Definition und Help Insight behandelt werden")

    tools = read_project_text(SOURCE / "h5u.DAI.MCP.Tools.pas")
    for tool in ("code_insight_status", "code_definition", "code_hover", "file_diagnostics", "project_context"):
        if not re.search(rf"SameText\s*\(\s*AName\s*,\s*'{re.escape(tool)}'", tools, flags=re.IGNORECASE):
            fail(errors, f"h5u.DAI.MCP.Tools.pas: Dispatch für {tool} fehlt")


def check_options_frame_layout(errors: list[str]) -> None:
    content = read_project_text(SOURCE / "h5u.DAI.Options.Frame.pas")
    stripped, _ = strip_pascal_strings_and_comments(content)

    for forbidden in ("FScrollBox", "TScrollBox", "VertScrollBar.Range", "Align := alClient"):
        if forbidden in stripped:
            fail(errors, f"h5u.DAI.Options.Frame.pas: eigene ScrollBox beziehungsweise alClient-Layout ist nicht erlaubt: {forbidden}")

    if "vcl.extctrls" in direct_used_units(content):
        fail(errors, "h5u.DAI.Options.Frame.pas: Vcl.ExtCtrls darf nicht nur für eine eigene ScrollBox eingebunden werden")

    build_match = re.search(
        r"(?is)procedure\s+TDAIOptionsFrame\.BuildControls\s*;.*?begin(.*?)end\s*;",
        stripped,
    )
    if not build_match:
        fail(errors, "h5u.DAI.Options.Frame.pas: BuildControls-Implementierung fehlt")
        return

    body = build_match.group(1)
    if not re.search(r"Align\s*:=\s*alTop\s*;\s*Height\s*:=\s*LTop\s*;\s*$", body, flags=re.IGNORECASE):
        fail(errors, "h5u.DAI.Options.Frame.pas: BuildControls muss mit Align := alTop und Height := LTop enden")


def check_version_consistency(errors: list[str]) -> None:
    expected = "1.1.11"
    consts = read_project_text(SOURCE / "h5u.DAI.Consts.pas")
    dproj = read_project_text(ROOT / "DAI.dproj")
    test_client = read_project_text(ROOT / "Test-MCP.ps1")
    changelog = read_project_text(ROOT / "CHANGELOG.md")

    if f"CDAIVersion = '{expected}'" not in consts:
        fail(errors, f"h5u.DAI.Consts.pas: CDAIVersion muss {expected} sein")
    if f"FileVersion={expected}.0" not in dproj or f"ProductVersion={expected}.0" not in dproj:
        fail(errors, f"DAI.dproj: Datei- und Produktversion müssen {expected}.0 sein")
    if f"version = '{expected}'" not in test_client:
        fail(errors, f"Test-MCP.ps1: Clientversion muss {expected} sein")
    if not changelog.startswith(f"# Änderungsprotokoll\n\n## {expected}\n"):
        fail(errors, f"CHANGELOG.md: erster Eintrag muss Version {expected} sein")


def check_nonfatal_server_binding(errors: list[str]) -> None:
    server = read_project_text(SOURCE / "h5u.DAI.MCP.Server.pas")
    runtime = read_project_text(SOURCE / "h5u.DAI.Runtime.pas")
    wizard = read_project_text(SOURCE / "h5u.DAI.Wizard.pas")
    log = read_project_text(SOURCE / "h5u.DAI.Log.pas")
    options = read_project_text(SOURCE / "h5u.DAI.Options.Frame.pas")

    if "EIdCouldNotBindSocket" not in server or "IdException" not in server:
        fail(errors, "MCP-Server muss EIdCouldNotBindSocket ausdrücklich behandeln")
    if not re.search(r"(?is)on\s+E\s*:\s*EIdCouldNotBindSocket\s+do.*?Result\s*:=\s*False", server):
        fail(errors, "MCP-Bindefehler muss ohne erneutes Auslösen der Ausnahme als Startfehler zurückgegeben werden")
    if "ResetAfterFailedStart" not in server or "Der Port ist bereits belegt" not in server:
        fail(errors, "MCP-Bindefehler benötigt Listener-Bereinigung und eine verständliche Portkonflikt-Meldung")
    if "TDAITCPListener.DescribeIPv4Owner" not in server:
        fail(errors, "MCP-Bindefehler muss PID und Prozessname des vorhandenen TCP-Listeners ermitteln")

    tcp_owner = read_project_text(SOURCE / "h5u.DAI.WinAPI.TCP.pas")
    for required in ("GetExtendedTcpTable", "QueryFullProcessImageNameW", "GetCurrentProcessId", "OwningProcessId"):
        if required not in tcp_owner:
            fail(errors, f"h5u.DAI.WinAPI.TCP.pas: Portbesitzer-Ermittlung fehlt: {required}")
    if "das verantwortliche Package oder Plugin ist über die TCP-Tabelle nicht ermittelbar" not in tcp_owner:
        fail(errors, "h5u.DAI.WinAPI.TCP.pas: Hinweis zur fehlenden BPL-/Plugin-Zuordnung innerhalb von bds.exe fehlt")
    if not re.search(r"(?is)class\s+function\s+TDAIRuntime\.ApplySettings\s*:\s*Boolean.*?except.*?Result\s*:=\s*False", runtime):
        fail(errors, "TDAIRuntime.ApplySettings muss Serverstartfehler abfangen")
    if "LastServerError" not in runtime:
        fail(errors, "TDAIRuntime muss den letzten Serverfehler für die Optionsseite bereitstellen")
    if not re.search(r"(?is)try\s+TDAIRuntime\.Start\s*;\s*except", wizard):
        fail(errors, "TDAIWizard muss den optionalen Laufzeitstart gegen Package-Registrierungsfehler absichern")
    if "OutputDebugString" not in log or not re.search(r"(?is)class\s+procedure\s+TDAILog\.AddMessage.*?except", log):
        fail(errors, "DAI-Logging muss bei Fehlern von IOTAMessageServices auf OutputDebugString zurückfallen")
    if "RefreshServerStatus" not in options or "TDAIRuntime.LastServerError" not in options:
        fail(errors, "DAI-Optionsseite muss den inaktiven Server und den letzten Startfehler anzeigen")


def check_duplicate_implementations(errors: list[str]) -> None:
    pattern = re.compile(
        r"(?ims)^\s*((?:class\s+)?(?:function|procedure|constructor|destructor)\s+"
        r"[A-Za-z0-9_.]+\s*(?:\([^;]*?\))?(?:\s*:\s*[^;]+)?\s*;)"
    )
    for path in SOURCE.glob("*.pas"):
        content = read_project_text(path)
        implementation = re.split(r"(?im)^\s*implementation\s*$", content, maxsplit=1)
        if len(implementation) != 2:
            fail(errors, f"{path.name}: implementation-Abschnitt fehlt")
            continue
        headers: dict[str, int] = {}
        for header in pattern.findall(implementation[1]):
            key = re.sub(r"\s+", " ", header.strip().lower())
            headers[key] = headers.get(key, 0) + 1
        for header, count in headers.items():
            if count > 1:
                fail(errors, f"{path.name}: doppelte Implementierung {header} ({count}x)")



def strip_pascal_strings_and_comments(content: str) -> tuple[str, list[str]]:
    errors: list[str] = []
    output: list[str] = []
    i = 0
    line = 1
    state = "code"
    while i < len(content):
        ch = content[i]
        nxt = content[i + 1] if i + 1 < len(content) else ""

        if ch == "\n":
            line += 1

        if state == "code":
            if ch == "'":
                state = "string"
                output.append(" ")
            elif ch == "/" and nxt == "/":
                state = "line_comment"
                output.extend([" ", " "])
                i += 1
            elif ch == "{" and nxt != "$":
                state = "brace_comment"
                output.append(" ")
            elif ch == "(" and nxt == "*":
                state = "paren_comment"
                output.extend([" ", " "])
                i += 1
            else:
                output.append(ch)
        elif state == "string":
            if ch == "'" and nxt == "'":
                output.extend([" ", " "])
                i += 1
            elif ch == "'":
                state = "code"
                output.append(" ")
            else:
                output.append("\n" if ch == "\n" else " ")
        elif state == "line_comment":
            if ch == "\n":
                state = "code"
                output.append("\n")
            else:
                output.append(" ")
        elif state == "brace_comment":
            if ch == "}":
                state = "code"
            output.append("\n" if ch == "\n" else " ")
        elif state == "paren_comment":
            if ch == "*" and nxt == ")":
                state = "code"
                output.extend([" ", " "])
                i += 1
            else:
                output.append("\n" if ch == "\n" else " ")
        i += 1

    if state == "string":
        errors.append("nicht abgeschlossene Zeichenkette")
    elif state in {"brace_comment", "paren_comment"}:
        errors.append("nicht abgeschlossener Kommentar")
    return "".join(output), errors


def check_lexical_balance(errors: list[str]) -> None:
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.dpk"]):
        content = read_project_text(path)
        stripped, lexical_errors = strip_pascal_strings_and_comments(content)
        for lexical_error in lexical_errors:
            fail(errors, f"{path.relative_to(ROOT)}: {lexical_error}")

        stack: list[tuple[str, int]] = []
        pairs = {")": "(", "]": "["}
        line = 1
        for ch in stripped:
            if ch == "\n":
                line += 1
            elif ch in "([":
                stack.append((ch, line))
            elif ch in ")]":
                if not stack or stack[-1][0] != pairs[ch]:
                    fail(errors, f"{path.relative_to(ROOT)}:{line}: unausgeglichene Klammer {ch}")
                    break
                stack.pop()
        if stack:
            fail(errors, f"{path.relative_to(ROOT)}:{stack[-1][1]}: nicht geschlossene Klammer {stack[-1][0]}")

def write_manifest() -> None:
    files = [
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and path.name not in {"MANIFEST.sha256"}
        and ".git" not in path.parts
        and "__pycache__" not in path.parts
        and path.suffix.lower() != ".pyc"
    ]
    lines = []
    for path in sorted(files):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(ROOT).as_posix()}")
    (ROOT / "MANIFEST.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    check_pascal_encodings(errors)
    check_source_whitespace_and_line_endings(errors)
    check_line_lengths(errors)
    check_declaration_layout(errors)
    check_initialization_finalization(errors)
    check_unit_names(errors)
    check_frame_resources(errors)
    check_package_references(errors)
    check_dproj(errors)
    check_tools(errors)
    check_old_names(errors)
    check_referenced_units(errors)
    check_known_invalid_symbols(errors)
    check_dai_type_definitions(errors)
    check_required_uses(errors)
    check_creator_definitions(errors)
    check_encoding_policy(errors)
    check_code_insight_integration(errors)
    check_options_frame_layout(errors)
    check_version_consistency(errors)
    check_nonfatal_server_binding(errors)
    check_duplicate_implementations(errors)
    check_lexical_balance(errors)

    if errors:
        print("DAI-Prüfung fehlgeschlagen:")
        for error in errors:
            print(f"  - {error}")
        return 1

    write_manifest()
    print(f"DAI-Prüfung erfolgreich: {len(list(SOURCE.glob('*.pas')))} Pascal-Units, {len(REQUIRED_TOOLS)} MCP-Werkzeuge.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
