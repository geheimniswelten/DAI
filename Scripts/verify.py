from __future__ import annotations

import hashlib
import itertools
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
    "ide_window_control",
    "ide_logs_read",
    "ide_dialog_inspect",
    "ide_dialog_click",
    "ide_dialog_close",
    "debugger_windows_list",
    "debugger_stacktrace",
    "debugger_threads_list",
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
    "project_activate",
    "project_options_configurations",
    "project_options_read",
    "project_option_set",
    "project_option_remove",

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
        stripped, _ = strip_pascal_strings_and_comments(read_project_text(path))
        code_lines = stripped.splitlines()
        line_index = 0
        while line_index < len(lines):
            routine_match = ROUTINE_HEADER_START.match(code_lines[line_index])
            if routine_match and routine_match.group(2).lower() not in {"begin", "var"}:
                end_index = find_routine_header_end(code_lines, line_index)
                if end_index is not None:
                    declaration_lines = lines[line_index:end_index + 1]
                    if end_index > line_index and len(normalized_declaration(declaration_lines)) <= MAX_LINE_LENGTH:
                        fail(
                            errors,
                            f"{path.name}:{line_index + 1}: Methodensignatur wird vor {MAX_LINE_LENGTH} Zeichen unnötig umgebrochen",
                        )
                    line_index = end_index + 1
                    continue

            if re.match(r"^\s*property\b", code_lines[line_index], re.IGNORECASE):
                end_index = line_index
                while end_index < len(lines) and ";" not in code_lines[end_index]:
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
        content, _ = strip_pascal_strings_and_comments(content)
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
        stripped, _ = strip_pascal_strings_and_comments(content)
        frame_classes = frame_pattern.findall(stripped)
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
    expected = {"rtl", "vcl", "vclimg", "vclie", "designide", "indysystem", "indycore", "indyprotocols"}
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
    suffix = tree.find("msbuild:PropertyGroup[@Condition=\"'$(Base)'!=''\"]/msbuild:DllSuffix", ns)
    if suffix is None or (suffix.text or "").lower() != "$(auto)":
        fail(errors, "DAI.dproj: DllSuffix muss $(Auto) für versionsgetrennte Packages verwenden")
    if not re.search(r"\{\$LIBSUFFIX\s+AUTO\s*\}", read_project_text(ROOT / "DAI.dpk"), re.IGNORECASE):
        fail(errors, "DAI.dpk: LIBSUFFIX AUTO fehlt")
    target = tree.find("msbuild:PropertyGroup/msbuild:TargetedPlatforms", ns)
    if target is None or target.text != "3":
        fail(errors, "DAI.dproj: TargetedPlatforms muss Win32 und Win64 enthalten (3)")
    for platform in ("Win32", "Win64"):
        node = tree.find(f".//msbuild:Platforms/msbuild:Platform[@value='{platform}']", ns)
        if node is None or (node.text or "").lower() != "true":
            fail(errors, f"DAI.dproj: {platform} muss für die passende IDE aktiviert sein")
        if tree.find(f".//msbuild:Base_{platform}", ns) is None:
            fail(errors, f"DAI.dproj: Base_{platform}-Konfiguration fehlt")


def read_pascal_literal(content: str, start: int) -> tuple[str, int]:
    """Decode one classic literal or text block for static JSON schema verification."""
    quotes = 1
    while start + quotes < len(content) and content[start + quotes] == "'":
        quotes += 1
    after_quotes = content[start + quotes] if start + quotes < len(content) else ""
    if quotes >= 3 and quotes % 2 and after_quotes in {"\r", "\n"}:
        opening_end = start + quotes
        newline_length = 2 if content.startswith("\r\n", opening_end) else 1
        body_start = opening_end + newline_length
        delimiter = "'" * quotes
        closing = re.search(rf"(?m)^([ \t]*){re.escape(delimiter)}(?!')", content[body_start:])
        if closing is None:
            raise ValueError("nicht abgeschlossener Delphi-Textblock")
        body_end = body_start + closing.start()
        body = content[body_start:body_end]
        if body.endswith("\r\n"):
            body = body[:-2]
        elif body.endswith(("\n", "\r")):
            body = body[:-1]
        indent = closing.group(1)
        lines = body.splitlines(keepends=True)
        decoded = "".join(line[len(indent):] if line.startswith(indent) else line for line in lines)
        return decoded, body_start + closing.end()

    index = start + 1
    output: list[str] = []
    while index < len(content):
        if content[index] == "'":
            if index + 1 < len(content) and content[index + 1] == "'":
                output.append("'")
                index += 2
                continue
            return "".join(output), index + 1
        output.append(content[index])
        index += 1
    raise ValueError("nicht abgeschlossene Delphi-Zeichenkette")


def mask_pascal_region(content: str) -> str:
    return "".join(character if character in "\r\n" else " " for character in content)


def preprocess_pascal(content: str, compiler_version: float, defines: set[str] | None = None) -> tuple[str, list[str]]:
    """Select compiler branches while retaining every original offset and line ending."""
    code, errors = strip_pascal_strings_and_comments(content)
    symbols = {symbol.upper() for symbol in (defines or set())}
    stack: list[dict[str, bool | int]] = []
    output: list[str] = []
    active = True
    previous = 0

    def condition(expression: str, line: int) -> bool:
        comparison = re.fullmatch(r"CompilerVersion\s*(>=|<=|<>|>|<|=)\s*(\d+(?:\.\d+)?)", expression, re.IGNORECASE)
        if comparison:
            operator, value = comparison.groups()
            version = float(value)
            return {">=": compiler_version >= version, "<=": compiler_version <= version,
                    ">": compiler_version > version, "<": compiler_version < version,
                    "=": compiler_version == version, "<>": compiler_version != version}[operator]
        symbol = re.fullmatch(r"(not\s+)?(?:Defined|Declared)\s*\(\s*([A-Za-z_]\w*)\s*\)", expression, re.IGNORECASE)
        if symbol:
            found = symbol.group(2).upper() in symbols
            return not found if symbol.group(1) else found
        errors.append(f"{line}: nicht unterstützte bedingte Compileranweisung: {expression}")
        return False

    for directive in re.finditer(r"\{\$([A-Za-z]+)\b([^{}]*)\}", code):
        output.append(content[previous:directive.start()] if active else mask_pascal_region(content[previous:directive.start()]))
        output.append(mask_pascal_region(content[directive.start():directive.end()]))
        previous = directive.end()
        command = directive.group(1).upper()
        expression = directive.group(2).strip()
        line = content.count("\n", 0, directive.start()) + 1
        if command in {"IF", "IFDEF", "IFNDEF", "IFOPT"}:
            if command in {"IFDEF", "IFNDEF"}:
                # Delphi's generated DPK uses explanatory text after IMPLICITBUILDING.
                symbol = re.fullmatch(r"([A-Za-z_]\w*)(?:\s+[^{}]*)?", expression)
                if not symbol:
                    errors.append(f"{line}: ungültiges Symbol in {command}")
                    selected = False
                else:
                    selected = symbol.group(1).upper() in symbols
                    if command == "IFNDEF":
                        selected = not selected
            else:
                selected = condition(expression, line)
            stack.append({"parent": active, "selected": selected, "else": False, "line": line})
            active = active and selected
        elif command in {"ELSE", "ELSEIF"}:
            if not stack:
                errors.append(f"{line}: {command} ohne zugehöriges IF")
                continue
            frame = stack[-1]
            if frame["else"]:
                errors.append(f"{line}: {command} nach ELSE")
            selected = True if command == "ELSE" else condition(expression, line)
            active = bool(frame["parent"]) and not bool(frame["selected"]) and selected
            frame["selected"] = bool(frame["selected"]) or selected
            frame["else"] = command == "ELSE"
        elif command in {"ENDIF", "IFEND"}:
            if not stack:
                errors.append(f"{line}: {command} ohne zugehöriges IF")
            else:
                active = bool(stack.pop()["parent"])
    output.append(content[previous:] if active else mask_pascal_region(content[previous:]))
    for frame in stack:
        errors.append(f"{frame['line']}: nicht abgeschlossene bedingte Compileranweisung")
    return "".join(output), errors


def pascal_compilation_views(content: str) -> list[tuple[str, str, list[str]]]:
    """Check both architectures and each optional symbol occurring in actual guards."""
    code, _ = strip_pascal_strings_and_comments(content)
    symbols = {symbol.upper() for groups in re.findall(
        r"\{\$(?:IFDEF|IFNDEF)\s+([A-Za-z_]\w*)\b|\b(?:Defined|Declared)\s*\(\s*([A-Za-z_]\w*)\s*\)",
        code, re.IGNORECASE) for symbol in groups if symbol}
    architecture_symbols = {"WIN32", "WIN64", "CPUX86", "CPUX64", "MSWINDOWS"}
    architectures = [{"WIN32", "CPUX86", "MSWINDOWS"}, {"WIN64", "CPUX64", "MSWINDOWS"}]
    if not symbols & architecture_symbols:
        architectures = architectures[:1]
    optional = sorted(symbols - architecture_symbols)
    versions = (35.0, 36.0, 37.0) if re.search(r"\{\$IF\s+CompilerVersion\b", code, re.IGNORECASE) else (37.0,)
    views: list[tuple[str, str, list[str]]] = []
    seen: set[str] = set()
    for version, architecture, values in itertools.product(versions, architectures, itertools.product((False, True), repeat=len(optional))):
        defines = architecture | {symbol for symbol, selected in zip(optional, values) if selected}
        selected, errors = preprocess_pascal(content, version, defines)
        if selected not in seen or errors:
            seen.add(selected)
            label = f"CompilerVersion={version:g}, " + ", ".join(sorted(defines))
            views.append((label, selected, errors))
    return views


def pascal_schema_tokens(content: str) -> list[tuple[str, str]]:
    """Tokenize only the small, explicitly supported schema construction language."""
    tokens: list[tuple[str, str]] = []
    index = 0
    while index < len(content):
        if content[index].isspace():
            index += 1
        elif content.startswith("//", index):
            end = content.find("\n", index)
            index = len(content) if end < 0 else end
        elif content.startswith("(*", index) or content[index] == "{":
            terminator = "*)" if content.startswith("(*", index) else "}"
            end = content.find(terminator, index + 2)
            if end < 0:
                raise ValueError("nicht abgeschlossener Kommentar im Schemaausdruck")
            index = end + len(terminator)
        elif content[index] == "'":
            literal, index = read_pascal_literal(content, index)
            tokens.append(("literal", literal))
        elif match := re.match(r"[A-Za-z_]\w*|:=|[+();,]", content[index:]):
            value = match.group()
            tokens.append(("word" if value[0].isalpha() or value[0] == "_" else "symbol", value.lower()))
            index += len(value)
        elif match := re.match(r"#(\d+)", content[index:]):
            tokens.append(("literal", chr(int(match.group(1)))))
            index += len(match.group())
        else:
            raise ValueError(f"nicht unterstütztes Zeichen im Schemaausdruck: {content[index]!r}")
    return tokens


class PascalSchemaExpression:
    """Evaluate actual literals and simple string helpers with one constant Boolean parameter."""

    def __init__(self, content: str, helpers: dict[str, tuple[str, str]], environment: dict[str, str | bool] | None = None,
                 depth: int = 0):
        if depth > 16:
            raise ValueError("rekursiver Schema-Helper")
        self.tokens = pascal_schema_tokens(content)
        self.position = 0
        self.helpers = helpers
        self.environment = environment or {}
        self.depth = depth

    def accept(self, value: str) -> bool:
        if self.position < len(self.tokens) and self.tokens[self.position] == ("word" if value[0].isalpha() else "symbol", value):
            self.position += 1
            return True
        return False

    def require(self, value: str) -> None:
        if not self.accept(value):
            raise ValueError(f"Schema-Helper: {value!r} erwartet")

    def boolean(self) -> bool:
        invert = self.accept("not")
        if self.accept("true"):
            value = True
        elif self.accept("false"):
            value = False
        elif self.position < len(self.tokens) and self.tokens[self.position][0] == "word":
            name = self.tokens[self.position][1]
            self.position += 1
            value = self.environment.get(name)
            if not isinstance(value, bool):
                raise ValueError(f"nicht unterstützte Schema-Bedingung: {name}")
        else:
            raise ValueError("konstante Boolean-Schema-Bedingung erwartet")
        return not value if invert else value

    def primary(self) -> str:
        if self.position >= len(self.tokens):
            raise ValueError("unvollständiger Schemaausdruck")
        kind, value = self.tokens[self.position]
        self.position += 1
        if kind == "literal":
            return value
        if (kind, value) == ("symbol", "("):
            result = self.expression()
            self.require(")")
            return result
        if kind != "word":
            raise ValueError(f"nicht unterstützter Schemaausdruck: {value}")
        if value == "slinebreak":
            return "\r\n"
        if value in self.environment and isinstance(self.environment[value], str):
            return self.environment[value]
        if value not in self.helpers:
            raise ValueError(f"nicht unterstützter Schemaausdruck oder fehlender Helper: {value}")
        parameter, body = self.helpers[value]
        self.require("(")
        argument = self.boolean()
        self.require(")")
        helper = PascalSchemaExpression(body, self.helpers, {"result": "", parameter: argument}, self.depth + 1)
        helper.statement(True)
        helper.accept(";")
        if helper.position != len(helper.tokens):
            raise ValueError(f"nicht unterstützter Schema-Helper: {value}")
        result = helper.environment["result"]
        if not isinstance(result, str):
            raise ValueError(f"Schema-Helper {value} liefert keinen String")
        return result

    def expression(self) -> str:
        result = self.primary()
        while self.accept("+"):
            result += self.primary()
        return result

    def statement(self, execute: bool) -> None:
        if self.accept("begin"):
            while not self.accept("end"):
                if self.position >= len(self.tokens):
                    raise ValueError("nicht abgeschlossener Schema-Helper")
                self.statement(execute)
                if not self.accept(";") and self.tokens[self.position:self.position + 1] != [("word", "end")]:
                    raise ValueError("Schema-Helper: Semikolon erwartet")
        elif self.accept("if"):
            selected = self.boolean()
            self.require("then")
            self.statement(execute and selected)
            if self.accept("else"):
                self.statement(execute and not selected)
        elif self.accept("result"):
            self.require(":=")
            result = self.expression()
            if execute:
                self.environment["result"] = result
        else:
            raise ValueError("nicht unterstützte Anweisung im Schema-Helper")


def pascal_schema_helpers(content: str, code: str) -> dict[str, tuple[str, str]]:
    helpers: dict[str, tuple[str, str]] = {}
    pattern = r"(?im)^function\s+([A-Za-z_]\w*)\(\s*(?:const\s+)?([A-Za-z_]\w*)\s*:\s*Boolean\s*\)\s*:\s*string\s*;\s*(begin)\b"
    for match in re.finditer(pattern, code):
        end = re.search(r"(?im)^end\s*;", code[match.end():])
        if not end:
            raise ValueError(f"nicht abgeschlossener Schema-Helper: {match.group(1)}")
        name = match.group(1).lower()
        if name in helpers:
            raise ValueError(f"mehrdeutiger Schema-Helper: {name}")
        helpers[name] = (match.group(2).lower(), content[match.start(3):match.end() + end.end()])
    return helpers


def pascal_literal_expression(content: str, helpers: dict[str, tuple[str, str]] | None = None) -> str:
    parser = PascalSchemaExpression(content, helpers or {})
    result = parser.expression()
    if parser.position != len(parser.tokens):
        raise ValueError("nicht unterstützter Rest im Schemaausdruck")
    return result


def extract_tool_schemas(content: str, errors: list[str], compiler_version: float) -> dict[str, dict]:
    content, conditional_errors = preprocess_pascal(content, compiler_version)
    errors.extend(conditional_errors)
    code, lexical_errors = strip_pascal_strings_and_comments(content)
    errors.extend(lexical_errors)
    schemas: dict[str, dict] = {}
    try:
        helpers = pascal_schema_helpers(content, code)
    except ValueError as exc:
        errors.append(str(exc))
        return schemas
    for match in re.finditer(r"AddTool\s*\(\s*Result\s*,", code, flags=re.IGNORECASE):
        arguments: list[str] = []
        depth, index, start = 1, match.end(), match.end()
        while index < len(content) and depth:
            character = code[index]
            if character == "," and depth == 1:
                arguments.append(content[start:index])
                start = index + 1
            elif character in "()":
                depth += 1 if character == "(" else -1
                if not depth:
                    arguments.append(content[start:index])
            index += 1
        line = content.count("\n", 0, match.start()) + 1
        if depth or len(arguments) != 4:
            errors.append(f"{line}: MCP-Werkzeugdeklaration besitzt ungültige Argumentanzahl oder Klammerung")
            continue
        name = arguments[0].strip()
        try:
            name = pascal_literal_expression(arguments[0])
            schema = json.loads(pascal_literal_expression(arguments[2], helpers))
            if not isinstance(schema, dict):
                raise ValueError("Eingabeschema muss ein JSON-Objekt sein")
            if name in schemas:
                raise ValueError("doppelte MCP-Werkzeugdeklaration")
            schemas[name] = schema
        except (ValueError, TypeError) as exc:
            errors.append(f"{line}: {name}: ungültiges JSON-Eingabeschema: {exc}")
    return schemas


def check_tools(errors: list[str]) -> None:
    source = read_project_text(SOURCE / "h5u.DAI.MCP.Tools.pas")
    for compiler_version in (35.0, 36.0, 37.0):
        branch_errors: list[str] = []
        content, conditional_errors = preprocess_pascal(source, compiler_version)
        branch_errors.extend(conditional_errors)
        stripped, _ = strip_pascal_strings_and_comments(content)
        declared = {
            match.group(1)
            for match in re.finditer(r"AddTool\s*\(\s*Result\s*,\s*'([^']+)'", content, flags=re.IGNORECASE | re.DOTALL)
            if stripped[match.start():match.start() + 7].lower() == "addtool"
        }
        missing = sorted(REQUIRED_TOOLS - declared)
        extra = sorted(declared - REQUIRED_TOOLS)
        if missing:
            fail(branch_errors, "Fehlende MCP-Werkzeuge: " + ", ".join(missing))
        if extra:
            fail(branch_errors, "Unerwartete MCP-Werkzeuge: " + ", ".join(extra))
        dispatched = {
            match.group(1)
            for match in re.finditer(r"SameText\s*\(\s*AName\s*,\s*'([^']+)'", content, flags=re.IGNORECASE)
            if stripped[match.start():match.start() + 8].lower() == "sametext"
        }
        for name in sorted(declared - dispatched):
            fail(branch_errors, f"MCP-Werkzeug ohne Dispatch: {name}")
        for name, schema in extract_tool_schemas(content, branch_errors, compiler_version).items():
            if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
                fail(branch_errors, f"{name}: Eingabeschema muss ein begrenztes Objekt sein")
            try:
                if set(schema.get("required", [])) - set(schema.get("properties", {})):
                    fail(branch_errors, f"{name}: required nennt nicht deklarierte Eigenschaften")
            except TypeError:
                fail(branch_errors, f"{name}: required/properties besitzen einen ungültigen Typ")
        errors.extend(f"CompilerVersion={compiler_version:g}: {error}" for error in branch_errors)


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
        content, _ = strip_pascal_strings_and_comments(content)
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
    content = "\n".join(strip_pascal_strings_and_comments(read_project_text(path))[0] for path in SOURCE.glob("*.pas"))
    identifiers = set(re.findall(r"\b(?:TDAI|EDAI)[A-Za-z0-9_]*\b", content))
    definitions = set(re.findall(r"\b((?:TDAI|EDAI)[A-Za-z0-9_]*)\s*=\s*(?:class|record|interface|\()", content, re.IGNORECASE))
    definitions.update(re.findall(r"\b((?:TDAI|EDAI)[A-Za-z0-9_]*)\s*=\s*[^;]+;", content, re.IGNORECASE))
    for identifier in sorted(identifiers - definitions):
        fail(errors, f"DAI-Typ wird verwendet, aber nicht deklariert: {identifier}")


def direct_used_units(content: str) -> set[str]:
    content, _ = strip_pascal_strings_and_comments(content)
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
        "TDAICodeInsightCallbacks = class(TInterfacedObject)",
        "FStateLock: TCriticalSection",
        "if FState.Completed then",
        "if not ACallbacks.MarkCancelled then",
        "CMaximumPendingCallbacks = 256",
        "FPendingCallbacks.Count >= CMaximumPendingCallbacks",
        "RetainCallback(LCallbacks)",
        "ReleaseCallback(Self)",
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
    expected = "1.2.16"
    consts = read_project_text(SOURCE / "h5u.DAI.Consts.pas")
    dproj = read_project_text(ROOT / "DAI.dproj")
    test_client = read_project_text(ROOT / "Test-MCP.ps1")
    changelog = read_project_text(ROOT / "CHANGELOG.md").replace("\r\n", "\n")

    if f"CDAIVersion = '{expected}'" not in consts:
        fail(errors, f"h5u.DAI.Consts.pas: CDAIVersion muss {expected} sein")
    # VERSIONINFO is optional; the current IDE-saved project does not enable it.
    version_info_enabled = re.search(r"<VerInfo_IncludeVerInfo>\s*true\s*</VerInfo_IncludeVerInfo>", dproj, re.IGNORECASE)
    if version_info_enabled and (f"FileVersion={expected}.0" not in dproj or f"ProductVersion={expected}.0" not in dproj):
        fail(errors, f"DAI.dproj: aktivierte Datei- und Produktversion müssen {expected}.0 sein")
    if f"version = '{expected}'" not in test_client:
        fail(errors, f"Test-MCP.ps1: Clientversion muss {expected} sein")
    first_release = re.match(
        r"\A# Änderungsprotokoll\n\n(?:## Unveröffentlicht\n[\s\S]*?(?=^## ))?## (\d+\.\d+\.\d+)\n",
        changelog, flags=re.MULTILINE,
    )
    if not first_release or first_release.group(1) != expected:
        fail(errors, f"CHANGELOG.md: erster Versionseintrag muss {expected} sein; Unveröffentlicht ist davor optional")


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
        content, _ = strip_pascal_strings_and_comments(content)
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
    """Mask Pascal trivia without changing offsets or newline counts, including Delphi text blocks."""
    errors: list[str] = []
    output: list[str] = []
    i = 0
    line = 1
    state = "code"
    textblock_quotes = 0
    textblock_line_prefix = False
    while i < len(content):
        ch = content[i]
        nxt = content[i + 1] if i + 1 < len(content) else ""

        if ch == "\n":
            line += 1

        if state == "code":
            if ch == "'":
                quotes = 1
                while i + quotes < len(content) and content[i + quotes] == "'":
                    quotes += 1
                after_quotes = content[i + quotes] if i + quotes < len(content) else ""
                if quotes >= 3 and quotes % 2 and after_quotes in {"\r", "\n"}:
                    state = "textblock"
                    textblock_quotes = quotes
                    textblock_line_prefix = True
                    output.extend(" " * quotes)
                    i += quotes - 1
                else:
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
        elif state == "textblock":
            if ch in {"\r", "\n"}:
                textblock_line_prefix = True
                output.append("\n" if ch == "\n" else " ")
            elif textblock_line_prefix and ch in {" ", "\t"}:
                output.append(" ")
            elif textblock_line_prefix and ch == "'":
                quotes = 1
                while i + quotes < len(content) and content[i + quotes] == "'":
                    quotes += 1
                output.extend(" " * quotes)
                i += quotes - 1
                if quotes == textblock_quotes:
                    state = "code"
                textblock_line_prefix = False
            else:
                textblock_line_prefix = False
                output.append(" ")
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
    elif state == "textblock":
        errors.append("nicht abgeschlossener Textblock")
    elif state in {"brace_comment", "paren_comment"}:
        errors.append("nicht abgeschlossener Kommentar")
    return "".join(output), errors


def check_lexical_content(content: str) -> list[str]:
    stripped, errors = strip_pascal_strings_and_comments(content)
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "["}
    line = 1
    for character in stripped:
        if character == "\n":
            line += 1
        elif character in "([":
            stack.append((character, line))
        elif character in ")]":
            if not stack or stack[-1][0] != pairs[character]:
                errors.append(f"{line}: unausgeglichene Klammer {character}")
                break
            stack.pop()
    if stack:
        errors.append(f"{stack[-1][1]}: nicht geschlossene Klammer {stack[-1][0]}")
    return errors


def check_lexical_balance(errors: list[str]) -> None:
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.dpk"]):
        for label, content, conditional_errors in pascal_compilation_views(read_project_text(path)):
            for error in conditional_errors + check_lexical_content(content):
                fail(errors, f"{path.relative_to(ROOT)} [{label}]: {error}")

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
