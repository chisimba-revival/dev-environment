#!/usr/bin/env python3

from __future__ import annotations

import argparse
import collections
import datetime
import json
import os
import re
from dataclasses import asdict, dataclass
from pathlib import Path


TABLES = (
    "tbl_users",
    "tbl_perms_groups",
    "tbl_perms_groupusers",
    "tbl_perms_perm_users",
)

ROOT_DIRS = (
    "framework/app",
    "modules",
    "canvases",
)

IGNORED_DIRS = {
    ".git",
    "node_modules",
    "vendor",
    "__pycache__",
}

ALLOWED_SUFFIXES = (
    ".php",
    ".inc",
    ".inc.php",
    "_class_inc.php",
    ".sql",
    ".xml",
)

SQL_OPERATION_PATTERNS = {
    "select": re.compile(r"\bSELECT\b", re.IGNORECASE),
    "insert": re.compile(r"\bINSERT\b", re.IGNORECASE),
    "update": re.compile(r"\bUPDATE\b", re.IGNORECASE),
    "delete": re.compile(r"\bDELETE\b", re.IGNORECASE),
    "create": re.compile(r"\bCREATE\s+TABLE\b", re.IGNORECASE),
    "alter": re.compile(r"\bALTER\s+TABLE\b", re.IGNORECASE),
    "replace": re.compile(r"\bREPLACE\b", re.IGNORECASE),
}

METHOD_PATTERN = re.compile(
    r"""
    function
    \s+
    &?
    \s*
    (?P<name>[A-Za-z_][A-Za-z0-9_]*)
    \s*
    \(
    """,
    re.IGNORECASE | re.VERBOSE,
)

CLASS_PATTERN = re.compile(
    r"""
    class
    \s+
    (?P<name>[A-Za-z_][A-Za-z0-9_]*)
    """,
    re.IGNORECASE | re.VERBOSE,
)


@dataclass
class Reference:
    table: str
    file: str
    line: int
    operation: str
    class_name: str
    method_name: str
    text: str


def iter_files(root: Path):
    for relative_root in ROOT_DIRS:
        source_root = root / relative_root

        if not source_root.exists():
            continue

        for directory, dirnames, filenames in os.walk(source_root):
            dirnames[:] = [
                name
                for name in dirnames
                if name not in IGNORED_DIRS
            ]

            for filename in filenames:
                lower = filename.lower()

                if not any(
                    lower.endswith(suffix)
                    for suffix in ALLOWED_SUFFIXES
                ):
                    continue

                yield Path(directory) / filename


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def line_text(text: str, number: int) -> str:
    lines = text.splitlines()

    if 1 <= number <= len(lines):
        return lines[number - 1].strip()

    return ""


def enclosing_name(
    text: str,
    offset: int,
    pattern: re.Pattern[str],
) -> str:
    found = ""

    for match in pattern.finditer(text, 0, offset):
        found = match.group("name")

    return found


def operation_for(line: str, context: str) -> str:
    combined = f"{context}\n{line}"

    for operation, pattern in SQL_OPERATION_PATTERNS.items():
        if pattern.search(combined):
            return operation

    lower = combined.lower()

    if "getall" in lower or "getrow" in lower or "query" in lower:
        return "read/unknown"

    if "insert" in lower or "add" in lower:
        return "insert/unknown"

    if "update" in lower or "edit" in lower:
        return "update/unknown"

    if "delete" in lower or "remove" in lower:
        return "delete/unknown"

    return "reference"


def table_fields(text: str, table: str) -> set[str]:
    fields: set[str] = set()

    create_pattern = re.compile(
        rf"""
        CREATE
        \s+TABLE
        .*?
        \b{re.escape(table)}\b
        \s*
        \(
        (?P<body>.*?)
        \)
        """,
        re.IGNORECASE | re.DOTALL | re.VERBOSE,
    )

    for match in create_pattern.finditer(text):
        body = match.group("body")

        for line in body.splitlines():
            field = re.match(
                r"""
                \s*
                [`"]?
                ([A-Za-z_][A-Za-z0-9_]*)
                [`"]?
                \s+
                [A-Za-z]
                """,
                line,
                re.VERBOSE,
            )

            if field:
                name = field.group(1)

                if name.upper() not in {
                    "PRIMARY",
                    "UNIQUE",
                    "KEY",
                    "CONSTRAINT",
                    "INDEX",
                    "FOREIGN",
                }:
                    fields.add(name)

    return fields


def infer_capability(
    table: str,
    method: str,
    operation: str,
    text: str,
) -> str:
    combined = f"{method} {operation} {text}".lower()

    if table == "tbl_users":
        if any(term in combined for term in (
            "password",
            "login",
            "username",
            "email",
            "authenticate",
        )):
            return "user authentication"

        if any(term in combined for term in (
            "create",
            "insert",
            "adduser",
            "register",
        )):
            return "user creation"

        if any(term in combined for term in (
            "update",
            "edit",
            "modify",
        )):
            return "user profile update"

        if any(term in combined for term in (
            "delete",
            "remove",
        )):
            return "user deletion"

        return "user lookup"

    if table == "tbl_perms_groups":
        return "group definition and lookup"

    if table == "tbl_perms_groupusers":
        return "group membership"

    if table == "tbl_perms_perm_users":
        return "direct user permissions"

    return "other"


def recommendation(
    table: str,
    file_count: int,
    method_count: int,
    operations: set[str],
) -> str:
    if file_count <= 5 and method_count <= 15:
        return (
            "Low coupling: preserve the table and reproduce the bounded "
            "operations behind a native authentication adapter."
        )

    if file_count <= 15 and method_count <= 35:
        return (
            "Moderate coupling: introduce repository classes first, then move "
            "existing callers behind the authentication adapter."
        )

    return (
        "High coupling: retain the schema initially and add a compatibility "
        "repository layer before attempting behavioural replacement."
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--text", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()

    references: list[Reference] = []
    files_scanned = 0
    relevant_files: set[str] = set()
    schema_fields: dict[str, set[str]] = {
        table: set()
        for table in TABLES
    }

    for path in iter_files(args.root):
        files_scanned += 1

        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue

        matched_tables = [
            table
            for table in TABLES
            if table.lower() in text.lower()
        ]

        if not matched_tables:
            continue

        relative = str(path.relative_to(args.root))
        relevant_files.add(relative)

        for table in matched_tables:
            schema_fields[table].update(
                table_fields(text, table)
            )

            pattern = re.compile(
                rf"\b{re.escape(table)}\b",
                re.IGNORECASE,
            )

            for match in pattern.finditer(text):
                number = line_number(text, match.start())
                current_line = line_text(text, number)

                lines = text.splitlines()
                start = max(0, number - 4)
                end = min(len(lines), number + 3)
                context = "\n".join(lines[start:end])

                references.append(
                    Reference(
                        table=table,
                        file=relative,
                        line=number,
                        operation=operation_for(
                            current_line,
                            context,
                        ),
                        class_name=enclosing_name(
                            text,
                            match.start(),
                            CLASS_PATTERN,
                        ),
                        method_name=enclosing_name(
                            text,
                            match.start(),
                            METHOD_PATTERN,
                        ),
                        text=current_line,
                    )
                )

    summaries = {}

    for table in TABLES:
        table_refs = [
            reference
            for reference in references
            if reference.table == table
        ]

        files = sorted({
            reference.file
            for reference in table_refs
        })

        methods = sorted({
            (
                reference.class_name,
                reference.method_name,
            )
            for reference in table_refs
            if reference.method_name
        })

        operations = collections.Counter(
            reference.operation
            for reference in table_refs
        )

        capabilities = collections.defaultdict(list)

        for reference in table_refs:
            capability = infer_capability(
                table,
                reference.method_name,
                reference.operation,
                reference.text,
            )

            capabilities[capability].append(reference)

        summaries[table] = {
            "reference_count": len(table_refs),
            "file_count": len(files),
            "files": files,
            "method_count": len(methods),
            "methods": [
                {
                    "class": class_name,
                    "method": method_name,
                }
                for class_name, method_name in methods
            ],
            "operations": dict(sorted(operations.items())),
            "fields": sorted(schema_fields[table]),
            "capabilities": {
                name: {
                    "reference_count": len(entries),
                    "files": sorted({
                        entry.file
                        for entry in entries
                    }),
                    "methods": sorted({
                        entry.method_name
                        for entry in entries
                        if entry.method_name
                    }),
                }
                for name, entries in sorted(capabilities.items())
            },
            "recommendation": recommendation(
                table,
                len(files),
                len(methods),
                set(operations),
            ),
            "references": [
                asdict(reference)
                for reference in table_refs
            ],
        }

    payload = {
        "generated_at": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(),
        "scope": list(ROOT_DIRS),
        "files_scanned": files_scanned,
        "relevant_files": len(relevant_files),
        "tables": summaries,
        "limitations": [
            "Dynamic table names cannot be detected reliably.",
            "Operations assembled over many variables may be classified as unknown.",
            "This audit maps source coupling, not runtime query frequency.",
            "The PHP 7.4 baseline remains the behavioural reference.",
        ],
    }

    args.json.write_text(
        json.dumps(payload, indent=2) + "\n"
    )

    with args.text.open("w") as handle:
        handle.write(
            "Chisimba authentication database coupling audit\n"
        )
        handle.write("=" * 48 + "\n\n")
        handle.write(f"Files scanned: {files_scanned}\n")
        handle.write(
            f"Relevant files: {len(relevant_files)}\n\n"
        )

        for table, summary in summaries.items():
            handle.write(f"{table}\n")
            handle.write("-" * len(table) + "\n")
            handle.write(
                f"References: {summary['reference_count']}\n"
            )
            handle.write(
                f"Files: {summary['file_count']}\n"
            )
            handle.write(
                f"Methods: {summary['method_count']}\n"
            )
            handle.write(
                "Operations: "
                + ", ".join(
                    f"{name}={count}"
                    for name, count
                    in summary["operations"].items()
                )
                + "\n"
            )
            handle.write(
                "Fields: "
                + (
                    ", ".join(summary["fields"])
                    or "not detected"
                )
                + "\n"
            )
            handle.write(
                f"Recommendation: "
                f"{summary['recommendation']}\n"
            )
            handle.write("Capabilities:\n")

            for name, details in summary[
                "capabilities"
            ].items():
                handle.write(
                    f"  {name}: "
                    f"{details['reference_count']} references; "
                    f"methods={', '.join(details['methods'])}\n"
                )

            handle.write("Methods:\n")

            for method in summary["methods"]:
                class_name = method["class"] or "(no class)"
                handle.write(
                    f"  {class_name}::{method['method']}()\n"
                )

            handle.write("\n")

    with args.markdown.open("w") as handle:
        handle.write(
            "# Authentication Database Coupling Audit\n\n"
        )
        handle.write(
            f"Files scanned: **{files_scanned}**  \n"
        )
        handle.write(
            f"Relevant files: **{len(relevant_files)}**\n\n"
        )

        handle.write("## Executive table\n\n")
        handle.write(
            "| Table | References | Files | Methods | "
            "Detected fields | Assessment |\n"
        )
        handle.write(
            "|---|---:|---:|---:|---:|---|\n"
        )

        for table, summary in summaries.items():
            handle.write(
                f"| `{table}` "
                f"| {summary['reference_count']} "
                f"| {summary['file_count']} "
                f"| {summary['method_count']} "
                f"| {len(summary['fields'])} "
                f"| {summary['recommendation']} |\n"
            )

        handle.write("\n")

        for table, summary in summaries.items():
            handle.write(f"## `{table}`\n\n")
            handle.write(
                f"{summary['recommendation']}\n\n"
            )
            handle.write(
                "- Operations: "
                + ", ".join(
                    f"`{name}`: {count}"
                    for name, count
                    in summary["operations"].items()
                )
                + "\n"
            )
            handle.write(
                "- Fields: "
                + (
                    ", ".join(
                        f"`{field}`"
                        for field in summary["fields"]
                    )
                    or "Not detected"
                )
                + "\n\n"
            )

            handle.write("### Capabilities\n\n")

            for name, details in summary[
                "capabilities"
            ].items():
                handle.write(
                    f"- **{name}:** "
                    f"{details['reference_count']} references; "
                    + ", ".join(
                        f"`{method}()`"
                        for method in details["methods"]
                    )
                    + "\n"
                )

            handle.write("\n### Owning methods\n\n")

            for method in summary["methods"]:
                class_name = method["class"] or "(no class)"
                handle.write(
                    f"- `{class_name}::{method['method']}()`\n"
                )

            handle.write("\n### Source references\n\n")

            for reference in summary["references"]:
                handle.write(
                    f"- `{reference['file']}:{reference['line']}` — "
                    f"{reference['operation']} — "
                    f"`{reference['text']}`\n"
                )

            handle.write("\n")

        handle.write("## Limitations\n\n")

        for limitation in payload["limitations"]:
            handle.write(f"- {limitation}\n")

    print(f"Files scanned: {files_scanned}")
    print(f"Relevant files: {len(relevant_files)}")

    for table, summary in summaries.items():
        print(
            f"{table}: "
            f"{summary['reference_count']} references, "
            f"{summary['file_count']} files, "
            f"{summary['method_count']} methods"
        )

    print(f"Text: {args.text}")
    print(f"Markdown: {args.markdown}")
    print(f"JSON: {args.json}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
