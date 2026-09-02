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


def check_line_lengths(errors: list[str]) -> None:
    for path in sorted([*SOURCE.glob("*.pas"), ROOT / "DAI.dpk"]):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if len(line) > MAX_LINE_LENGTH:
                fail(errors, f"{path.relative_to(ROOT)}:{number}: {len(line)} Zeichen")


def check_unit_names(errors: list[str]) -> None:
    for path in sorted(SOURCE.glob("*.pas")):
        if not path.name.startswith("h5u."):
            fail(errors, f"Pascal-Datei ohne h5u.-Präfix: {path.name}")
        content = path.read_text(encoding="utf-8")
        match = re.search(r"(?im)^\s*unit\s+([A-Za-z0-9_.]+)\s*;", content)
        if not match:
            fail(errors, f"Keine Unit-Deklaration: {path.name}")
            continue
        if match.group(1).lower() != path.stem.lower():
            fail(errors, f"Unit/Dateiname abweichend: {match.group(1)} <> {path.stem}")


def check_package_references(errors: list[str]) -> None:
    dpk = (ROOT / "DAI.dpk").read_text(encoding="utf-8")
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

    text = (ROOT / "DAI.dproj").read_text(encoding="utf-8")
    if "<MainSource>DAI.dpk</MainSource>" not in text:
        fail(errors, "DAI.dproj verwendet nicht DAI.dpk")
    for path in sorted(SOURCE.glob("*.pas")):
        reference = f'Source\\{path.name}'
        if reference.lower() not in text.lower():
            fail(errors, f"DAI.dproj referenziert {path.name} nicht")
    del tree


def check_tools(errors: list[str]) -> None:
    content = (SOURCE / "h5u.DAI.MCP.Tools.pas").read_text(encoding="utf-8")
    declared = set(re.findall(r"AddTool\s*\(\s*Result\s*,\s*'([^']+)'", content, flags=re.IGNORECASE | re.DOTALL))
    missing = sorted(REQUIRED_TOOLS - declared)
    extra = sorted(declared - REQUIRED_TOOLS)
    if missing:
        fail(errors, "Fehlende MCP-Werkzeuge: " + ", ".join(missing))
    if extra:
        fail(errors, "Unerwartete MCP-Werkzeuge: " + ", ".join(extra))


def check_old_names(errors: list[str]) -> None:
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() in {".zip", ".sha256"}:
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if "DAI" in content:
            fail(errors, f"Altbezeichnung in {path.relative_to(ROOT)}")
        if re.search(r"(?i)\bunit\s+DAI", content):
            fail(errors, f"Alte Unit-Bezeichnung in {path.relative_to(ROOT)}")


def check_referenced_units(errors: list[str]) -> None:
    available = {path.stem.lower() for path in SOURCE.glob("*.pas")}
    pattern = re.compile(r"\bh5u\.DAI(?:\.[A-Za-z0-9_]+)+")
    for path in SOURCE.glob("*.pas"):
        content = path.read_text(encoding="utf-8")
        for token in pattern.findall(content):
            parts = token.split(".")
            candidates = [".".join(parts[:index]).lower() for index in range(len(parts), 1, -1)]
            if not any(candidate in available for candidate in candidates):
                fail(errors, f"{path.name}: referenzierte Unit fehlt: {token}")


def check_duplicate_implementations(errors: list[str]) -> None:
    pattern = re.compile(
        r"(?ims)^\s*((?:class\s+)?(?:function|procedure|constructor|destructor)\s+"
        r"[A-Za-z0-9_.]+\s*(?:\([^;]*?\))?(?:\s*:\s*[^;]+)?\s*;)"
    )
    for path in SOURCE.glob("*.pas"):
        content = path.read_text(encoding="utf-8")
        implementation = content.split("\nimplementation\n", 1)
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
        content = path.read_text(encoding="utf-8")
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
        if path.is_file() and path.name not in {"MANIFEST.sha256"} and ".git" not in path.parts
    ]
    lines = []
    for path in sorted(files):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(ROOT).as_posix()}")
    (ROOT / "MANIFEST.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    check_line_lengths(errors)
    check_unit_names(errors)
    check_package_references(errors)
    check_dproj(errors)
    check_tools(errors)
    check_old_names(errors)
    check_referenced_units(errors)
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
