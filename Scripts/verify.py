from __future__ import annotations

import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Source"
MAX_LINE_LENGTH = 180

REQUIRED_TOOLS = {
    "source_search",
    "ide_windows_list",
    "debugger_windows_list",
    "form_designer_inspect",
    "form_show_designer",
    "debugger_status",
    "breakpoints_list",
    "breakpoint_set",
    "breakpoint_remove",
    "debugger_control",
    "clients_registration_status",
    "clients_register",
    "clients_unregister",
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


def check_no_getit_dependencies(errors: list[str]) -> None:
    """DAI uses its own MCP implementation and the Delphi/Indy standard packages."""
    dpk, _ = strip_pascal_strings_and_comments(read_project_text(ROOT / "DAI.dpk"))
    match = re.search(r"\brequires\s+(.*?);", dpk, flags=re.IGNORECASE | re.DOTALL)
    expected = {"rtl", "vcl", "vclie", "designide", "indysystem", "indycore", "indyprotocols"}
    actual = {name.strip().lower() for name in match.group(1).split(",")} if match else set()
    if actual != expected:
        fail(errors, "DAI.dpk: ausschließlich die dokumentierten Delphi-/Indy-Standardpakete sind erlaubt")

    vendor = re.compile(r"^(?:mcpconnect|neon|logify|jose)(?:[0-9]|\.|$)|^d\.mcpserver(?:\.|$)|^sdm", re.IGNORECASE)
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.McpBridge.dpr"]):
        code, _ = strip_pascal_strings_and_comments(read_project_text(path))
        for uses in re.finditer(r"\buses\s+(.*?);", code, flags=re.IGNORECASE | re.DOTALL):
            for unit in uses.group(1).split(","):
                name = unit.strip()
                if vendor.match(name):
                    fail(errors, f"{path.relative_to(ROOT)}: unerwünschte GetIt-Unit {name}")

    tree = ET.parse(ROOT / "DAI.dproj")
    for node in tree.iter():
        tag = node.tag.rsplit("}", 1)[-1]
        if tag in {"DCC_UnitSearchPath", "DCC_UsePackage"}:
            value = node.text or ""
            if "catalogrepository" in value.lower() or any(vendor.match(item.strip()) for item in value.split(";")):
                fail(errors, f"DAI.dproj: unerwünschter GetIt-Bezug in {tag}")


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
    ns = {"msbuild": "http://schemas.microsoft.com/developer/msbuild/2003"}
    target = tree.find("msbuild:PropertyGroup/msbuild:TargetedPlatforms", ns)
    if target is None or target.text != "3":
        fail(errors, "DAI.dproj: TargetedPlatforms muss Win32 und Win64 enthalten (3)")
    for platform in ("Win32", "Win64"):
        node = tree.find(f".//msbuild:Platforms/msbuild:Platform[@value='{platform}']", ns)
        if node is None or (node.text or "").lower() != "true":
            fail(errors, f"DAI.dproj: {platform} muss für die passende IDE aktiviert sein")
        if tree.find(f".//msbuild:Base_{platform}", ns) is None:
            fail(errors, f"DAI.dproj: Base_{platform}-Konfiguration fehlt")


def check_tools(errors: list[str]) -> None:
    content = read_project_text(SOURCE / "h5u.DAI.MCP.Tools.pas")
    declared = set(re.findall(r"AddTool\s*\(\s*Result\s*,\s*'([^']+)'", content, flags=re.IGNORECASE | re.DOTALL))
    missing = sorted(REQUIRED_TOOLS - declared)
    extra = sorted(declared - REQUIRED_TOOLS)
    if missing:
        fail(errors, "Fehlende MCP-Werkzeuge: " + ", ".join(missing))
    if extra:
        fail(errors, "Unerwartete MCP-Werkzeuge: " + ", ".join(extra))
    dispatched = set(re.findall(r"SameText\s*\(\s*AName\s*,\s*'([^']+)'", content, flags=re.IGNORECASE))
    for name in sorted(declared - dispatched):
        fail(errors, f"MCP-Werkzeug ohne Dispatch: {name}")

    for match in re.finditer(r"AddTool\s*\(\s*Result\s*,", content, flags=re.IGNORECASE):
        args = [""]
        depth, index, quoted = 1, match.end(), False
        while index < len(content) and depth:
            char = content[index]
            if char == "'":
                args[-1] += char
                if quoted and index + 1 < len(content) and content[index + 1] == "'":
                    args[-1] += "'"
                    index += 2
                    continue
                quoted = not quoted
            elif not quoted and char == "," and depth == 1:
                args.append("")
            elif not quoted and char in "()":
                depth += 1 if char == "(" else -1
                if depth:
                    args[-1] += char
            else:
                args[-1] += char
            index += 1
        if len(args) != 4:
            fail(errors, "MCP-Werkzeugdeklaration besitzt ungültige Argumentanzahl")
            continue
        name = args[0].strip()
        try:
            schema_text = "".join(s.replace("''", "'") for s in re.findall(r"'((?:''|[^'])*)'", args[2]))
            schema = json.loads(schema_text)
            if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
                fail(errors, f"{name}: Eingabeschema muss ein begrenztes Objekt sein")
            if set(schema.get("required", [])) - set(schema.get("properties", {})):
                fail(errors, f"{name}: required nennt nicht deklarierte Eigenschaften")
        except (ValueError, TypeError) as exc:
            fail(errors, f"{name}: ungültiges JSON-Eingabeschema: {exc}")


def check_old_names(errors: list[str]) -> None:
    old_names = ("CodexMCPIDE", "Codex MCP IDE", "CodexMCP.")
    for path in deliverable_files():
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


def check_qualified_system_monitor(errors: list[str]) -> None:
    pattern = re.compile(r"(?<![A-Za-z0-9_.])TMonitor\b", re.IGNORECASE)
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.dpk"]):
        content = read_project_text(path)
        stripped, _ = strip_pascal_strings_and_comments(content)
        for match in pattern.finditer(stripped):
            line = stripped.count("\n", 0, match.start()) + 1
            fail(errors, f"{path.relative_to(ROOT)}:{line}: Synchronisationszugriffe müssen System.TMonitor verwenden")

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
    if "Formulardateien werden ausschließlich über einen verfügbaren IDE-Textpuffer geändert" not in files_content:
        fail(errors, "h5u.DAI.OTA.Files.pas: DFM-Direktschreibschutz fehlt")
    if "SameText(TPath.GetExtension(LExpandedFileName), '.dfm')" not in tools_content:
        fail(errors, "h5u.DAI.MCP.Tools.pas: DFM-Schreibzugriffe müssen als IDE-Bearbeitung autorisiert werden")
    if "SameText(TPath.GetExtension(LExpandedFileName), '.fmx')" not in tools_content:
        fail(errors, "h5u.DAI.MCP.Tools.pas: FMX-Schreibzugriffe müssen als IDE-Bearbeitung autorisiert werden")
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

    if "Format('Standard: %d', [CDAIDefaultPort])" not in content:
        fail(errors, "h5u.DAI.Options.Frame.pas: der konfigurierbare Port muss den Standardport aus CDAIDefaultPort anzeigen")
    if "FGenerateTokenButton" not in content or "FGenerateTokenButton.OnClick := GenerateTokenClicked" not in content:
        fail(errors, "h5u.DAI.Options.Frame.pas: Schaltfläche zum Erzeugen eines neuen Bearer-Tokens fehlt")
    if not re.search(r"(?is)procedure\s+TDAIOptionsFrame\.GenerateTokenClicked.*?TDAISettings\.Instance\.GenerateToken", content):
        fail(errors, "h5u.DAI.Options.Frame.pas: Token-Schaltfläche muss TDAISettings.GenerateToken verwenden")
    token_width = re.search(r"FTokenEdit\.Width\s*:=\s*(\d+)", content)
    if not token_width or int(token_width.group(1)) > 360:
        fail(errors, "h5u.DAI.Options.Frame.pas: Bearer-Token-Edit muss genügend Platz für die Token-Schaltfläche lassen")

    restart_notice = "Nach dem Ändern von Port oder Bearer-Token sowie nach dem Registrieren oder Deregistrieren muss die Codex-App neu gestartet werden."
    if restart_notice not in content:
        fail(errors, "h5u.DAI.Options.Frame.pas: Hinweis zum erforderlichen Neustart der Codex-App fehlt")
    notice_position = content.find(restart_notice)
    unregister_position = content.find("FUnregisterButton.OnClick := UnregisterClicked")
    align_position = content.find("Align := alTop", unregister_position)
    if unregister_position < 0 or align_position < 0 or not (unregister_position < notice_position < align_position):
        fail(errors, "h5u.DAI.Options.Frame.pas: Neustart-Hinweis muss ganz unten zwischen Registrierungsbuttons und Frame-Ausrichtung stehen")

    settings = read_project_text(SOURCE / "h5u.DAI.Settings.pas")
    public_part = re.split(r"(?im)^\s*implementation\s*$", settings, maxsplit=1)[0]
    public_section = re.search(r"(?is)\bpublic\b(.*?)(?:\bend\s*;)", public_part)
    if not public_section or "function GenerateToken: string;" not in public_section.group(1):
        fail(errors, "h5u.DAI.Settings.pas: GenerateToken muss für den Options-Frame öffentlich sein")
    if not re.search(r"(?is)function\s+TDAISettings\.GenerateToken\s*:\s*string.*?CreateGUID", settings):
        fail(errors, "h5u.DAI.Settings.pas: Bearer-Token-Erzeugung muss weiterhin eine neue GUID erzeugen")


def check_version_consistency(errors: list[str]) -> None:
    expected = "1.2.4"
    consts = read_project_text(SOURCE / "h5u.DAI.Consts.pas")
    dproj = read_project_text(ROOT / "DAI.dproj")
    test_client = read_project_text(ROOT / "Test-MCP.ps1")
    changelog = read_project_text(ROOT / "CHANGELOG.md").replace("\r\n", "\n")

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
    for variable_name, type_name in (
        ("LGetExtendedTcpTable", "TGetExtendedTcpTable"),
        ("LQueryFullProcessImageNameW", "TQueryFullProcessImageNameW"),
    ):
        if re.search(rf"Pointer\s*\(\s*{variable_name}\s*\)\s*:=", tcp_owner):
            fail(errors, f"h5u.DAI.WinAPI.TCP.pas: {variable_name} darf auf der linken Seite nicht nach Pointer gecastet werden")
        expected_assignment = rf"{variable_name}\s*:=\s*{type_name}\s*\(\s*GetProcAddress\s*\("
        if not re.search(expected_assignment, tcp_owner):
            fail(errors, f"h5u.DAI.WinAPI.TCP.pas: {variable_name} muss direkt aus dem typisierten GetProcAddress-Ergebnis zugewiesen werden")
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


def check_bearer_authentication_and_registration_paths(errors: list[str]) -> None:
    server = read_project_text(SOURCE / "h5u.DAI.MCP.Server.pas")
    registration = read_project_text(SOURCE / "h5u.DAI.Codex.Registration.pas")
    tools = read_project_text(SOURCE / "h5u.DAI.MCP.Tools.pas")

    if "FHTTPServer.OnParseAuthentication := HandleParseAuthentication" not in server:
        fail(errors, "h5u.DAI.MCP.Server.pas: Indy benötigt einen OnParseAuthentication-Handler für Bearer")
    if not re.search(
        r"(?is)procedure\s+TDAIMCPServer\.HandleParseAuthentication.*?SameText\s*\(\s*AAuthType\s*,\s*'Bearer'\s*\).*?VPassword\s*:=\s*Trim\s*\(\s*AAuthData\s*\).*?VHandled\s*:=\s*True",
        server,
    ):
        fail(errors, "h5u.DAI.MCP.Server.pas: Bearer muss vor HandleCommand als unterstütztes Indy-Authentifizierungsschema markiert werden")
    if "HasValidBearerToken" not in server or "ARequestInfo.AuthType" not in server or "ARequestInfo.AuthPassword" not in server or "SameStr(ARequestInfo.AuthPassword, AExpectedToken)" not in server:
        fail(errors, "h5u.DAI.MCP.Server.pas: der von Indy geparste Bearer-Token muss case-sensitiv geprüft werden")
    if "WWW-Authenticate" not in server or 'Bearer realm="DAI"' not in server:
        fail(errors, "h5u.DAI.MCP.Server.pas: eine fehlgeschlagene Prüfung muss eine Bearer-Challenge liefern")

    if "class function UserProfileDirectory: string; static;" not in registration:
        fail(errors, "h5u.DAI.Codex.Registration.pas: UserProfileDirectory muss öffentlich verfügbar sein")
    if "GetEnvironmentVariable('USERPROFILE')" not in registration:
        fail(errors, "h5u.DAI.Codex.Registration.pas: Codex-Dateien müssen aus USERPROFILE abgeleitet werden")
    if "TPath.GetHomePath" in registration or "TPath.GetHomePath" in tools:
        fail(errors, "Codex- und Skill-Registrierung darf TPath.GetHomePath unter Windows nicht verwenden")
    if "LegacyApplicationDataDirectory" not in registration or "RemoveLegacyRegistration" not in registration:
        fail(errors, "h5u.DAI.Codex.Registration.pas: DAI muss eigene Altregistrierungen unter APPDATA bereinigen")
    for required in (".codex\\config.toml", ".agents\\skills\\", 'http_headers = { Authorization = ', "TomlQuotedString('Bearer "):
        if required not in registration:
            fail(errors, f"h5u.DAI.Codex.Registration.pas: Registrierungselement fehlt: {required}")
    if tools.count("TDAICodexRegistration.UserProfileDirectory") < 2:
        fail(errors, "h5u.DAI.MCP.Tools.pas: Registrieren und Deregistrieren müssen USERPROFILE als Berechtigungsziel verwenden")


def check_duplicate_implementations(errors: list[str]) -> None:
    pattern = re.compile(
        r"(?ims)^\s*((?:class\s+)?(?:function|procedure|constructor|destructor)\s+"
        r"[A-Za-z0-9_.]+\s*(?:\([^)]*\))?(?:\s*:\s*[^;\n]+)?\s*;)"
        r"(?=\s*(?:var|const|type|begin|asm)\b)"
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

def deliverable_files() -> list[Path]:
    """Check the shipped source, excluding builds, personal chats and permission files."""
    files = [p for folder in (SOURCE, ROOT / "Scripts") for p in folder.rglob("*")
             if p.is_file() and "__pycache__" not in p.parts and p.suffix.lower() != ".pyc"]
    names = ("DAI.dpk", "DAI.dproj", "DAI.McpBridge.dpr", "Build.ps1", "Test-MCP.ps1", ".gitignore",
             "README.md", "CHANGELOG.md", "FINAL_VERIFICATION.md", "GETIT_COMPARISON.txt", "OPENTOOLSAPI_CODE_INSIGHT.md")
    files.extend(ROOT / name for name in names if (ROOT / name).is_file())
    return files


def write_manifest() -> None:
    files = deliverable_files()
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
    if not any("kein gültiges XML" in error for error in errors):
        check_no_getit_dependencies(errors)
    check_tools(errors)
    check_old_names(errors)
    check_referenced_units(errors)
    check_known_invalid_symbols(errors)
    check_qualified_system_monitor(errors)
    check_dai_type_definitions(errors)
    check_required_uses(errors)
    check_creator_definitions(errors)
    check_encoding_policy(errors)
    check_code_insight_integration(errors)
    check_options_frame_layout(errors)
    check_version_consistency(errors)
    check_nonfatal_server_binding(errors)
    check_bearer_authentication_and_registration_paths(errors)
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
