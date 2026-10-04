"""Regression tests for compiler-aware Pascal and MCP schema verification.

Run from the repository root with ``python -B Scripts/test_verify.py``.
The tests inspect synthetic source and the shipped MCP unit without changing it.
"""

from __future__ import annotations

import re
import unittest
from unittest.mock import patch

import verify


SEARCH_TOOLS = {
    "source_search",
    "project_directory_files_list",
    "directory_files_list",
    "reference_files_list",
}


def literal_tool(schema_expression: str, name: str = "example") -> str:
    return f"AddTool(Result, '{name}', 'Description', {schema_expression}, True);\r\n"


HELPER_SOURCE = """function ExampleSchema(const IncludeProject: Boolean): string;
begin
  Result := '{"type":"object","properties":{';
  if IncludeProject then
    Result := Result + '"custom_project":{"type":"string"},'
  else
    Result := Result + '"custom_directory":{"type":"string"},';
  Result := Result + '"label":{"type":"string","default":"from_source"}},"additionalProperties":false';
  if not IncludeProject then
    Result := Result + ',"required":["custom_directory"]';
  Result := Result + '}';
end;

procedure RegisterTools;
begin
  AddTool(Result, 'with_project', 'Description', ExampleSchema(True), True);
  AddTool(Result, 'with_directory', 'Description', ExampleSchema(False), True);
end;
"""


class PascalPreprocessorTests(unittest.TestCase):
    def preprocess(self, content: str, version: float, defines: set[str] | None = None) -> str:
        masked, errors = verify.preprocess_pascal(content, version, defines)
        self.assertEqual(errors, [])
        self.assertEqual(len(masked), len(content), "Masking must preserve source offsets")
        self.assertEqual(
            [(index, character) for index, character in enumerate(masked) if character in "\r\n"],
            [(index, character) for index, character in enumerate(content) if character in "\r\n"],
            "Masking must preserve each CR and LF at its original offset",
        )
        return masked

    def test_nested_compiler_guards_choose_one_branch_and_preserve_crlf(self) -> None:
        content = (
            "before;\r\n"
            "{$IF CompilerVersion >= 36.0}\r\n"
            "modern;\r\n"
            "{$IF CompilerVersion >= 37.0}\r\n"
            "newest;\r\n"
            "{$ELSE}\r\n"
            "middle;\r\n"
            "{$ENDIF}\r\n"
            "{$ELSE}\r\n"
            "legacy;\r\n"
            "{$IFEND}\r\n"
            "after;\r\n"
        )
        for version, expected in (
            (35.0, {"before;", "legacy;", "after;"}),
            (36.0, {"before;", "modern;", "middle;", "after;"}),
            (37.0, {"before;", "modern;", "newest;", "after;"}),
        ):
            with self.subTest(version=version):
                masked = self.preprocess(content, version)
                for token in {"before;", "modern;", "newest;", "middle;", "legacy;", "after;"}:
                    self.assertEqual(token in masked, token in expected)
                self.assertNotIn("{$", masked)

    def test_inactive_outer_branch_cannot_be_reactivated_by_nested_else(self) -> None:
        content = (
            "{$IF CompilerVersion >= 36.0}\n"
            "{$IF CompilerVersion >= 37.0}\nfirst;\n{$ELSE}\nsecond;\n{$IFEND}\n"
            "{$ELSE}\nlegacy;\n{$IFEND}\n"
        )
        masked = self.preprocess(content, 35.0)
        self.assertIn("legacy;", masked)
        self.assertNotIn("first;", masked)
        self.assertNotIn("second;", masked)

    def test_fake_directives_in_literals_and_comments_are_ignored(self) -> None:
        content = (
            "const Classic = 'a''{$ELSE}{$ENDIF}';\r\n"
            "const Block = '''\r\n{$IF CompilerVersion >= 37.0}\r\n{$ELSE}\r\n''' ;\r\n"
            "// {$ENDIF}\r\n"
            "{ ordinary comment {$ELSE}\r\n"
            "(* ordinary comment {$IF CompilerVersion >= 37.0} {$ENDIF} *)\r\n"
            "real_code;\r\n"
        )
        self.assertEqual(self.preprocess(content, 35.0), content)

    def test_unmatched_conditional_directives_report_errors(self) -> None:
        for content in (
            "{$IF CompilerVersion >= 36.0}\ncode;\n",
            "{$ELSE}\ncode;\n",
            "{$ENDIF}\n",
            "{$IFEND}\n",
            "{$IF CompilerVersion >= 36.0}\n{$ELSE}\n{$ELSE}\n{$ENDIF}\n",
        ):
            with self.subTest(content=content):
                _, errors = verify.preprocess_pascal(content, 36.0)
                self.assertTrue(errors, "Malformed conditional nesting must fail closed")

    def test_unsupported_conditional_expression_reports_error(self) -> None:
        content = "{$IF MysteryCondition(CompilerVersion)}\ncode;\n{$IFEND}\n"
        _, errors = verify.preprocess_pascal(content, 36.0)
        self.assertTrue(errors, "Unknown conditional expressions must not be silently ignored")

    def test_symbol_guards_use_explicit_defines_case_insensitively(self) -> None:
        content = (
            "{$IFDEF win64}\nwide;\n{$ELSE}\nsmall;\n{$ENDIF}\n"
            "{$IFNDEF DEBUG}\nrelease;\n{$ELSE}\ndebug_code;\n{$ENDIF}\n"
        )
        masked = self.preprocess(content, 36.0, {"WIN64", "debug"})
        self.assertIn("wide;", masked)
        self.assertIn("debug_code;", masked)
        self.assertNotIn("small;", masked)
        self.assertNotIn("release;", masked)

    def test_delphi_generated_symbol_annotations_preserve_branch_selection(self) -> None:
        content = (
            "{$IFDEF IMPLICITBUILDING This IFDEF should not be used by users}\r\n"
            "implicit_build;\r\n"
            "{$ELSE}\r\n"
            "explicit_build;\r\n"
            "{$ENDIF IMPLICITBUILDING}\r\n"
            "{$IFNDEF IMPLICITBUILDING This IFNDEF is an explanatory annotation}\r\n"
            "nonimplicit_build;\r\n"
            "{$ENDIF IMPLICITBUILDING}\r\n"
        )
        for defined in (False, True):
            with self.subTest(defined=defined):
                masked = self.preprocess(content, 37.0, {"IMPLICITBUILDING"} if defined else set())
                self.assertEqual("implicit_build;" in masked.split(), defined)
                self.assertEqual("explicit_build;" in masked.split(), not defined)
                self.assertEqual("nonimplicit_build;" in masked.split(), not defined)


class ToolSchemaExtractionTests(unittest.TestCase):
    def extract(self, content: str, version: float = 36.0) -> dict[str, dict]:
        errors: list[str] = []
        schemas = verify.extract_tool_schemas(content, errors, version)
        self.assertEqual(errors, [])
        return schemas

    def test_classic_literals_concatenation_and_linebreaks(self) -> None:
        source = literal_tool(
            "'{\"type\":\"object\",' + sLineBreak + "
            "'\"properties\":{\"message\":{\"type\":\"string\",\"default\":\"it''s Pascal\"}},' + "
            "'\"additionalProperties\":false}'"
        )
        schema = self.extract(source)["example"]
        self.assertEqual(schema["properties"]["message"]["default"], "it's Pascal")
        self.assertIs(schema["additionalProperties"], False)

    def test_textblock_schema(self) -> None:
        schema = self.extract(
            literal_tool("'''\r\n  {\"type\":\"object\",\"additionalProperties\":false}\r\n  '''")
        )["example"]
        self.assertEqual(schema, {"type": "object", "additionalProperties": False})

    def test_compiler_branches_each_produce_their_own_schema(self) -> None:
        source = (
            "AddTool(Result, 'example', 'Description',\r\n"
            "{$IF CompilerVersion >= 36.0}\r\n"
            "'''\r\n{\"type\":\"object\",\"properties\":{\"modern\":{\"type\":\"boolean\"}},\"additionalProperties\":false}\r\n'''\r\n"
            "{$ELSE}\r\n"
            "'{\"type\":\"object\",\"properties\":{\"legacy\":{\"type\":\"boolean\"}},\"additionalProperties\":false}'\r\n"
            "{$IFEND}\r\n, True);\r\n"
        )
        self.assertIn("legacy", self.extract(source, 35.0)["example"]["properties"])
        self.assertIn("modern", self.extract(source, 36.0)["example"]["properties"])
        self.assertIn("modern", self.extract(source, 37.0)["example"]["properties"])

    def test_boolean_helper_evaluates_true_false_and_actual_source_literals(self) -> None:
        schemas = self.extract(HELPER_SOURCE)
        self.assertEqual(set(schemas), {"with_project", "with_directory"})
        project = schemas["with_project"]
        directory = schemas["with_directory"]
        self.assertIn("custom_project", project["properties"])
        self.assertNotIn("custom_directory", project["properties"])
        self.assertNotIn("required", project)
        self.assertIn("custom_directory", directory["properties"])
        self.assertNotIn("custom_project", directory["properties"])
        self.assertEqual(directory["required"], ["custom_directory"])
        for schema in schemas.values():
            self.assertEqual(schema["properties"]["label"]["default"], "from_source")

        mutated = HELPER_SOURCE.replace('"default":"from_source"', '"default":"changed_source"')
        changed = self.extract(mutated)
        for schema in changed.values():
            self.assertEqual(schema["properties"]["label"]["default"], "changed_source")

    def test_fake_addtool_calls_in_comments_and_literals_are_ignored(self) -> None:
        source = (
            "// AddTool(Result, 'line_fake', 'Description', InvalidSchema(), True);\n"
            "(* AddTool(Result, 'paren_fake', 'Description', InvalidSchema(), True); *)\n"
            "{ AddTool(Result, 'brace_fake', 'Description', InvalidSchema(), True); }\n"
            "S := 'AddTool(Result, ''string_fake'', ''Description'', InvalidSchema(), True);';\n"
            + literal_tool("'{\"type\":\"object\",\"additionalProperties\":false}'")
        )
        self.assertEqual(set(self.extract(source)), {"example"})

    def test_unsupported_schema_expressions_report_errors(self) -> None:
        valid_literal = "'{\"type\":\"object\",\"additionalProperties\":false}'"
        for expression in (
            "UnknownSchema()",
            valid_literal + " + UnknownText()",
            "ExampleSchema(SomeRuntimeValue)",
            "ExampleSchema(True or False)",
        ):
            with self.subTest(expression=expression):
                errors: list[str] = []
                verify.extract_tool_schemas(HELPER_SOURCE + literal_tool(expression, "invalid"), errors, 36.0)
                self.assertTrue(errors, "Unsupported dynamic schema expressions must fail closed")

    def test_invalid_json_from_helper_reports_error(self) -> None:
        errors: list[str] = []
        source = HELPER_SOURCE.replace('"default":"from_source"', '"default":INVALID')
        verify.extract_tool_schemas(source, errors, 36.0)
        self.assertTrue(errors)

    def test_unsupported_helper_body_cannot_be_silently_ignored(self) -> None:
        for replacement in (
            "Result := Result + '}' + RuntimeSuffix();",
            "Result := Result + '}';\n  UnexpectedStatement;",
        ):
            with self.subTest(replacement=replacement):
                source = HELPER_SOURCE.replace("Result := Result + '}';", replacement)
                errors: list[str] = []
                verify.extract_tool_schemas(source, errors, 36.0)
                self.assertTrue(errors, "Unsupported helper code must not produce a guessed schema")

    def test_invalid_json_is_rejected_only_in_selected_branch(self) -> None:
        source = (
            "AddTool(Result, 'example', 'Description',\n"
            "{$IF CompilerVersion >= 36.0}\n"
            "'{\"type\":\"object\",\"additionalProperties\":false}'\n"
            "{$ELSE}\n"
            "'{\"type\":INVALID}'\n"
            "{$IFEND}\n, True);\n"
        )
        self.extract(source, 36.0)
        self.extract(source, 37.0)
        errors: list[str] = []
        verify.extract_tool_schemas(source, errors, 35.0)
        self.assertTrue(errors)


class LexicalContentTests(unittest.TestCase):
    def test_each_selected_branch_balances_independently(self) -> None:
        content = (
            "AddTool(Result, 'example', 'Description',\r\n"
            "{$IF CompilerVersion >= 36.0}\r\n"
            "'''\r\n{\"type\":\"object\",\"additionalProperties\":false}\r\n''', True);\r\n"
            "{$ELSE}\r\n"
            "'{\"type\":\"object\",\"additionalProperties\":false}', True);\r\n"
            "{$IFEND}\r\n"
        )
        for version in (35.0, 36.0, 37.0):
            with self.subTest(version=version):
                masked, errors = verify.preprocess_pascal(content, version)
                self.assertEqual(errors, [])
                self.assertEqual(verify.check_lexical_content(masked), [])

    def test_balance_error_in_active_branch_reports_original_line(self) -> None:
        content = (
            "before;\r\n"
            "{$IF CompilerVersion >= 37.0}\r\n"
            "Broken := (1;\r\n"
            "{$ELSE}\r\n"
            "Valid := (1);\r\n"
            "{$ENDIF}\r\n"
        )
        selected, errors = verify.preprocess_pascal(content, 36.0)
        self.assertEqual(errors, [])
        self.assertEqual(verify.check_lexical_content(selected), [])
        selected, errors = verify.preprocess_pascal(content, 37.0)
        self.assertEqual(errors, [])
        lexical_errors = verify.check_lexical_content(selected)
        self.assertTrue(lexical_errors)
        self.assertTrue(any(re.search(r"\b3\b", message) for message in lexical_errors), lexical_errors)

    def test_comments_and_literals_cannot_create_balance_errors(self) -> None:
        content = (
            "S := '([)]';\r\n"
            "S := '''\r\n([)]\r\n''';\r\n"
            "// ([)]\r\n"
            "{ ([)] }\r\n"
            "(* ([)] *)\r\n"
            "Valid := Values[(Index)];\r\n"
        )
        self.assertEqual(verify.check_lexical_content(content), [])

    def test_incomplete_trivia_and_mismatched_delimiters_report_errors(self) -> None:
        for content in (
            "S := 'unfinished",
            "S := '''\r\nunfinished\r\n",
            "{ unfinished",
            "(* unfinished",
            "Values[);",
            "Values[(Index];",
        ):
            with self.subTest(content=content):
                self.assertTrue(verify.check_lexical_content(content))


class ShippedSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.content = verify.read_project_text(verify.SOURCE / "h5u.DAI.MCP.Tools.pas")

    def extract(self, content: str, version: float) -> dict[str, dict]:
        errors: list[str] = []
        schemas = verify.extract_tool_schemas(content, errors, version)
        self.assertEqual(errors, [], f"CompilerVersion {version}")
        return schemas

    def test_every_shipped_tool_has_a_valid_schema_for_each_supported_compiler(self) -> None:
        for version in (35.0, 36.0, 37.0):
            with self.subTest(version=version):
                schemas = self.extract(self.content, version)
                self.assertEqual(set(schemas), verify.REQUIRED_TOOLS)
                for name, schema in schemas.items():
                    with self.subTest(tool=name):
                        self.assertEqual(schema.get("type"), "object")
                        self.assertIs(schema.get("additionalProperties"), False)
                        self.assertFalse(set(schema.get("required", [])) - set(schema.get("properties", {})))

    def test_four_search_schemas_are_equal_across_compilers_and_expose_new_arguments(self) -> None:
        schemas = {version: self.extract(self.content, version) for version in (35.0, 36.0, 37.0)}
        for name in SEARCH_TOOLS:
            with self.subTest(tool=name):
                self.assertEqual(schemas[35.0][name], schemas[36.0][name])
                self.assertEqual(schemas[36.0][name], schemas[37.0][name])

        source = schemas[35.0]["source_search"]
        self.assertEqual(source["required"], ["query"])
        self.assertEqual(source["properties"]["query"]["maxLength"], 256)
        self.assertEqual(source["properties"]["filename_regex"]["maxLength"], 256)
        self.assertEqual(source["properties"]["use_regex"]["type"], "boolean")
        self.assertIs(source["properties"]["use_regex"]["default"], False)
        self.assertIs(source["properties"]["interfaces_only"]["default"], True)

        for name in SEARCH_TOOLS - {"source_search"}:
            with self.subTest(tool=name):
                schema = schemas[35.0][name]
                properties = schema["properties"]
                for field in ("filename_regex", "content_query"):
                    self.assertEqual(properties[field]["type"], "string")
                    self.assertEqual(properties[field]["maxLength"], 256)
                for field in ("content_use_regex", "case_sensitive", "whole_word"):
                    self.assertEqual(properties[field]["type"], "boolean")
                    self.assertIs(properties[field]["default"], False)
                if name == "project_directory_files_list":
                    self.assertIn("project", properties)
                    self.assertNotIn("directory", properties)
                    self.assertNotIn("directory", schema.get("required", []))
                else:
                    self.assertIn("directory", properties)
                    self.assertEqual(schema["required"], ["directory"])

    def test_mutated_shipped_legacy_schema_cannot_hide_behind_modern_branch(self) -> None:
        tool_start = self.content.index("AddTool(Result, 'source_search'")
        legacy_start = self.content.index("{$ELSE}", tool_start)
        legacy_end = self.content.index("{$IFEND}", legacy_start)
        legacy = self.content[legacy_start:legacy_end]
        mutated_legacy, count = re.subn(r'("default"\s*:\s*)false', r"\1INVALID", legacy, count=1)
        self.assertEqual(count, 1, "The fixture must modify the real legacy use_regex schema")
        mutated = self.content[:legacy_start] + mutated_legacy + self.content[legacy_end:]

        self.extract(mutated, 36.0)
        self.extract(mutated, 37.0)
        errors: list[str] = []
        verify.extract_tool_schemas(mutated, errors, 35.0)
        self.assertTrue(errors, "The actual legacy branch must be parsed, not synthesized")
        self.assertTrue(any("source_search" in error for error in errors), errors)


class ChangelogVersionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.content = verify.read_project_text(verify.ROOT / "CHANGELOG.md")
        match = re.search(r"(?m)^## (\d+\.\d+\.\d+)\s*$", cls.content)
        if match is None:
            raise AssertionError("The shipped changelog must contain a numbered release")
        cls.current_release = match.group(1)

    def check_changelog(self, content: str) -> list[str]:
        original_read = verify.read_project_text

        def read_with_changelog(path):
            if path == verify.ROOT / "CHANGELOG.md":
                return content
            return original_read(path)

        errors: list[str] = []
        with patch.object(verify, "read_project_text", side_effect=read_with_changelog):
            verify.check_version_consistency(errors)
        return errors

    def test_actual_shipped_changelog_is_accepted(self) -> None:
        self.assertEqual(self.check_changelog(self.content), [])

    def test_unpublished_section_is_optional_before_current_release(self) -> None:
        for newline in ("\n", "\r\n"):
            for unpublished in ("", "## Unveröffentlicht\n\n- Work in progress.\n\n"):
                with self.subTest(newline=newline, unpublished=bool(unpublished)):
                    content = "# Änderungsprotokoll\n\n" + unpublished + f"## {self.current_release}\n\n- Release.\n"
                    self.assertEqual(self.check_changelog(content.replace("\n", newline)), [])

    def test_wrong_first_release_cannot_hide_before_the_expected_version(self) -> None:
        content = (
            "# Änderungsprotokoll\n\n## Unveröffentlicht\n\n- Pending.\n\n"
            "## 999.999.999\n\n- Wrong release.\n\n"
            f"## {self.current_release}\n\n- Correct version appearing later.\n"
        )
        errors = self.check_changelog(content)
        self.assertTrue(any("CHANGELOG.md" in error for error in errors), errors)

    def test_missing_release_or_unknown_first_heading_is_rejected(self) -> None:
        for content in (
            "# Änderungsprotokoll\n\n## Unveröffentlicht\n\n- Pending.\n",
            f"# Änderungsprotokoll\n\n## Unknown\n\n## {self.current_release}\n\n- Release.\n",
        ):
            with self.subTest(content=content):
                errors = self.check_changelog(content)
                self.assertTrue(any("CHANGELOG.md" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main(verbosity=2)
