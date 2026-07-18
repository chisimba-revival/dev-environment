#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="$ROOT/dev-environment"
TOOLS="$DEV/tools"
REPORTS="$DEV/reports"

SCRIPT="$TOOLS/audit-legacy-auth-language-stack.py"
TEXT_REPORT="$REPORTS/liveuser-language-dependency-audit.txt"
JSON_REPORT="$REPORTS/liveuser-language-dependency-audit.json"
MARKDOWN_REPORT="$REPORTS/liveuser-language-dependency-audit.md"
OUT="$ROOT/killme.txt"

mkdir -p "$REPORTS"

cat > "$SCRIPT" <<'PY'
#!/usr/bin/env python3

from __future__ import annotations

import argparse
import collections
import datetime
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


SOURCE_SUFFIXES = {
    ".php",
    ".inc",
    ".sql",
    ".xml",
}

IGNORED_PARTS = {
    ".git",
    "node_modules",
    "vendor",
    "__pycache__",
    ".constructor-moderniser-backups",
}

TARGETS = {
    "LiveUser": {
        "class_patterns": [
            r"\bLiveUser::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
            r"->([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        ],
        "file_hints": [
            "LiveUser.php",
            "LiveUser/Admin.php",
        ],
    },
    "LiveUser_Admin": {
        "class_patterns": [
            r"\bLiveUser_Admin::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        ],
        "file_hints": [
            "LiveUser/Admin.php",
        ],
    },
    "Translation2": {
        "class_patterns": [
            r"\bTranslation2::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
            r"\bTranslation2_Admin::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        ],
        "file_hints": [
            "Translation2.php",
            "Translation2/Admin.php",
        ],
    },
    "I18Nv2": {
        "class_patterns": [
            r"\bI18Nv2::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        ],
        "file_hints": [
            "I18Nv2.php",
        ],
    },
    "Event_Dispatcher": {
        "class_patterns": [
            r"\bEvent_Dispatcher::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
            r"->(addObserver|removeObserver|post|postNotification|"
            r"observerRegistered|getObservers)\s*\(",
        ],
        "file_hints": [
            "Event/Dispatcher.php",
            "Event/Notification.php",
        ],
    },
}


@dataclass
class CallSite:
    subsystem: str
    method: str
    file: str
    line: int
    text: str
    call_style: str


@dataclass
class IncludeSite:
    subsystem: str
    file: str
    line: int
    text: str


@dataclass
class TableReference:
    table: str
    file: str
    line: int
    text: str


@dataclass
class ConfigReference:
    key: str
    file: str
    line: int
    text: str


def source_files(roots: Iterable[Path]) -> Iterable[Path]:
    seen: set[Path] = set()

    for root in roots:
        if not root.exists():
            continue

        candidates = [root] if root.is_file() else root.rglob("*")

        for path in candidates:
            if not path.is_file():
                continue

            if any(part in IGNORED_PARTS for part in path.parts):
                continue

            name = path.name.lower()

            if not (
                path.suffix.lower() in SOURCE_SUFFIXES
                or name.endswith(".inc.php")
                or name.endswith("_class_inc.php")
            ):
                continue

            resolved = path.resolve()

            if resolved in seen:
                continue

            seen.add(resolved)
            yield path


def relative(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def line_text(text: str, line: int) -> str:
    lines = text.splitlines()

    if 1 <= line <= len(lines):
        return lines[line - 1].strip()

    return ""


def class_methods(text: str, class_name: str) -> set[str]:
    class_pattern = re.compile(
        rf"\bclass\s+{re.escape(class_name)}\b[^{{]*\{{",
        re.IGNORECASE,
    )

    match = class_pattern.search(text)

    if match is None:
        return set()

    opening = text.find("{", match.start())

    if opening < 0:
        return set()

    depth = 0
    closing = None
    quote = None
    escaped = False

    for index in range(opening, len(text)):
        char = text[index]

        if quote is not None:
            if escaped:
                escaped = False
                continue

            if char == "\\":
                escaped = True
                continue

            if char == quote:
                quote = None

            continue

        if char in ("'", '"'):
            quote = char
            continue

        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1

            if depth == 0:
                closing = index
                break

    if closing is None:
        return set()

    body = text[opening + 1:closing]

    return {
        match.group(1)
        for match in re.finditer(
            r"\bfunction\s+&?\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(",
            body,
            re.IGNORECASE,
        )
    }


def capability_for(
    subsystem: str,
    method: str,
    text: str,
) -> str:
    combined = f"{method} {text}".lower()

    rules = [
        (
            "authentication",
            (
                "login",
                "logout",
                "auth",
                "credential",
                "password",
                "loggedin",
                "forcelogin",
            ),
        ),
        (
            "permissions and roles",
            (
                "permission",
                "perm",
                "right",
                "role",
                "group",
                "area",
                "admin",
            ),
        ),
        (
            "session management",
            (
                "session",
                "freeze",
                "unfreeze",
                "cookie",
                "idle",
                "expire",
            ),
        ),
        (
            "user administration",
            (
                "user",
                "account",
                "container",
                "storage",
                "factory",
                "init",
            ),
        ),
        (
            "translation retrieval",
            (
                "translate",
                "translation",
                "gettext",
                "getstring",
                "get",
            ),
        ),
        (
            "translation administration",
            (
                "add",
                "update",
                "remove",
                "delete",
                "admin",
            ),
        ),
        (
            "locale handling",
            (
                "locale",
                "language",
                "country",
                "currency",
                "date",
            ),
        ),
        (
            "event dispatch",
            (
                "observer",
                "post",
                "notification",
                "dispatch",
            ),
        ),
        (
            "logging and errors",
            (
                "log",
                "error",
                "stack",
            ),
        ),
    ]

    for capability, terms in rules:
        if any(term in combined for term in terms):
            return capability

    if subsystem == "Event_Dispatcher":
        return "event dispatch"

    return "other"


def recommendation(
    subsystem: str,
    external_calls: int,
    used_methods: int,
    available_methods: int,
    capabilities: int,
    table_count: int,
) -> tuple[str, str]:
    usage_ratio = (
        used_methods / available_methods
        if available_methods
        else 0.0
    )

    if subsystem == "Event_Dispatcher":
        return (
            "replace",
            "The used interface is small and maps cleanly to a lightweight "
            "dispatcher or a Chisimba-native event service.",
        )

    if subsystem == "I18Nv2":
        return (
            "replace or isolate",
            "Locale operations are usually replaceable with PHP intl and a "
            "small compatibility adapter.",
        )

    if subsystem == "Translation2":
        if used_methods <= 12 and capabilities <= 4:
            return (
                "replace behind adapter",
                "Observed use is bounded enough to reproduce the required "
                "translation interface without maintaining the full package.",
            )

        return (
            "temporary compatibility fork",
            "Observed use is broad enough that immediate replacement may be "
            "riskier; isolate it first and retire it incrementally.",
        )

    if subsystem in {"LiveUser", "LiveUser_Admin"}:
        if (
            used_methods <= 20
            and capabilities <= 6
            and table_count <= 20
        ):
            return (
                "replace behind authentication adapter",
                "The observed Chisimba-facing interface appears bounded. "
                "Reimplement only the required login, session and permission "
                "contract using the PHP 7.4 runtime as behavioural reference.",
            )

        return (
            "formal compatibility fork, then adapter",
            "The observed surface is broad. Stabilise a clearly versioned "
            "compatibility fork first, while introducing an adapter boundary "
            "for later replacement.",
        )

    return (
        "review",
        "Insufficient evidence for an automatic recommendation.",
    )


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--root",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--json",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--text",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--markdown",
        type=Path,
        required=True,
    )

    args = parser.parse_args()

    root = args.root

    roots = [
        root / "framework" / "app",
        root / "modules",
        root / "canvases",
        root / "dev-environment",
    ]

    files = list(source_files(roots))

    calls: list[CallSite] = []
    includes: list[IncludeSite] = []
    tables: list[TableReference] = []
    configs: list[ConfigReference] = []

    library_methods: dict[str, set[str]] = {
        name: set()
        for name in TARGETS
    }

    library_paths = {
        "LiveUser": [
            root / "framework/app/lib/pear/LiveUser.php",
        ],
        "LiveUser_Admin": [
            root / "framework/app/lib/pear/LiveUser/Admin.php",
        ],
        "Translation2": [
            root / "framework/app/lib/pear/Translation2.php",
            root / "framework/app/lib/pear/Translation2/Admin.php",
            root / "framework/app/lib/pear/Translation2/Decorator.php",
        ],
        "I18Nv2": [
            root / "framework/app/lib/pear/I18Nv2.php",
        ],
        "Event_Dispatcher": [
            root / "framework/app/lib/pear/Event/Dispatcher.php",
            root / "framework/app/lib/pear/Event/Notification.php",
        ],
    }

    class_names = {
        "LiveUser": ["LiveUser"],
        "LiveUser_Admin": ["LiveUser_Admin"],
        "Translation2": [
            "Translation2",
            "Translation2_Admin",
            "Translation2_Decorator",
        ],
        "I18Nv2": ["I18Nv2"],
        "Event_Dispatcher": [
            "Event_Dispatcher",
            "Event_Notification",
        ],
    }

    for subsystem, paths in library_paths.items():
        for path in paths:
            if not path.is_file():
                continue

            text = path.read_text(errors="replace")

            for class_name in class_names[subsystem]:
                library_methods[subsystem].update(
                    class_methods(text, class_name)
                )

    include_patterns = {
        "LiveUser": re.compile(
            r"""(?:require|include)(?:_once)?\s*
                \(?\s*['"][^'"]*LiveUser\.php['"]""",
            re.IGNORECASE | re.VERBOSE,
        ),
        "LiveUser_Admin": re.compile(
            r"""(?:require|include)(?:_once)?\s*
                \(?\s*['"][^'"]*LiveUser/Admin\.php['"]""",
            re.IGNORECASE | re.VERBOSE,
        ),
        "Translation2": re.compile(
            r"""(?:require|include)(?:_once)?\s*
                \(?\s*['"][^'"]*Translation2[^'"]*['"]""",
            re.IGNORECASE | re.VERBOSE,
        ),
        "I18Nv2": re.compile(
            r"""(?:require|include)(?:_once)?\s*
                \(?\s*['"][^'"]*I18Nv2[^'"]*['"]""",
            re.IGNORECASE | re.VERBOSE,
        ),
        "Event_Dispatcher": re.compile(
            r"""(?:require|include)(?:_once)?\s*
                \(?\s*['"][^'"]*Event/Dispatcher\.php['"]""",
            re.IGNORECASE | re.VERBOSE,
        ),
    }

    table_pattern = re.compile(
        r"\b(tbl_[A-Za-z0-9_]+)\b",
        re.IGNORECASE,
    )

    config_pattern = re.compile(
        r"""
        (?:
            getParam|getConfig|getValue|getSetting|getSystemConfig|
            setParam|setConfig|setValue
        )
        \s*\(
        \s*['"]([^'"]+)['"]
        """,
        re.IGNORECASE | re.VERBOSE,
    )

    for path in files:
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue

        rel = relative(path, root)

        is_pear_library = "/lib/pear/" in f"/{rel}"

        for subsystem, include_pattern in include_patterns.items():
            for match in include_pattern.finditer(text):
                line = line_number(text, match.start())

                includes.append(
                    IncludeSite(
                        subsystem=subsystem,
                        file=rel,
                        line=line,
                        text=line_text(text, line),
                    )
                )

        for subsystem, definition in TARGETS.items():
            for pattern_text in definition["class_patterns"]:
                pattern = re.compile(
                    pattern_text,
                    re.IGNORECASE,
                )

                for match in pattern.finditer(text):
                    method = match.group(1)
                    line = line_number(text, match.start())

                    before = text[max(0, match.start() - 50):match.start()]

                    if "::" in match.group(0):
                        call_style = "static"
                    else:
                        call_style = "instance"

                    # Avoid treating arbitrary object calls throughout the
                    # application as LiveUser calls. Instance-call collection
                    # is retained only in likely subsystem files.
                    if (
                        call_style == "instance"
                        and subsystem in {"LiveUser", "Translation2"}
                        and not any(
                            token.lower() in rel.lower()
                            for token in (
                                "liveuser",
                                "language",
                                "translation",
                                "security",
                                "engine",
                            )
                        )
                    ):
                        continue

                    calls.append(
                        CallSite(
                            subsystem=subsystem,
                            method=method,
                            file=rel,
                            line=line,
                            text=line_text(text, line),
                            call_style=call_style,
                        )
                    )

        if not is_pear_library:
            for match in table_pattern.finditer(text):
                line = line_number(text, match.start())

                tables.append(
                    TableReference(
                        table=match.group(1).lower(),
                        file=rel,
                        line=line,
                        text=line_text(text, line),
                    )
                )

            for match in config_pattern.finditer(text):
                line = line_number(text, match.start())

                configs.append(
                    ConfigReference(
                        key=match.group(1),
                        file=rel,
                        line=line,
                        text=line_text(text, line),
                    )
                )

    subsystem_summaries = {}

    for subsystem in TARGETS:
        external_calls = [
            call
            for call in calls
            if call.subsystem == subsystem
            and "/lib/pear/" not in f"/{call.file}"
        ]

        internal_calls = [
            call
            for call in calls
            if call.subsystem == subsystem
            and "/lib/pear/" in f"/{call.file}"
        ]

        used_methods = sorted(
            {
                call.method
                for call in external_calls
            },
            key=str.lower,
        )

        available = sorted(
            library_methods[subsystem],
            key=str.lower,
        )

        capabilities = collections.defaultdict(list)

        for call in external_calls:
            capability = capability_for(
                subsystem,
                call.method,
                call.text,
            )

            capabilities[capability].append(call)

        subsystem_tables: set[str] = set()

        table_terms = {
            "LiveUser": (
                "user",
                "group",
                "role",
                "right",
                "permission",
                "area",
                "login",
                "auth",
            ),
            "LiveUser_Admin": (
                "user",
                "group",
                "role",
                "right",
                "permission",
                "area",
                "login",
                "auth",
            ),
            "Translation2": (
                "language",
                "translation",
                "phrase",
                "word",
                "text",
            ),
            "I18Nv2": (
                "language",
                "locale",
                "country",
            ),
            "Event_Dispatcher": (
                "event",
                "notification",
            ),
        }

        for table_ref in tables:
            if any(
                term in table_ref.table.lower()
                for term in table_terms[subsystem]
            ):
                subsystem_tables.add(table_ref.table)

        decision, rationale = recommendation(
            subsystem=subsystem,
            external_calls=len(external_calls),
            used_methods=len(used_methods),
            available_methods=len(available),
            capabilities=len(capabilities),
            table_count=len(subsystem_tables),
        )

        subsystem_summaries[subsystem] = {
            "external_call_count": len(external_calls),
            "internal_call_count": len(internal_calls),
            "external_file_count": len(
                {
                    call.file
                    for call in external_calls
                }
            ),
            "used_methods": used_methods,
            "used_method_count": len(used_methods),
            "available_methods": available,
            "available_method_count": len(available),
            "usage_ratio": (
                round(len(used_methods) / len(available), 3)
                if available
                else None
            ),
            "capabilities": {
                capability: {
                    "call_count": len(entries),
                    "files": sorted(
                        {
                            entry.file
                            for entry in entries
                        }
                    ),
                    "methods": sorted(
                        {
                            entry.method
                            for entry in entries
                        },
                        key=str.lower,
                    ),
                }
                for capability, entries in sorted(
                    capabilities.items()
                )
            },
            "likely_tables": sorted(subsystem_tables),
            "recommendation": decision,
            "rationale": rationale,
            "external_calls": [
                asdict(call)
                for call in external_calls
            ],
        }

    payload = {
        "generated_at": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(),
        "root": str(root),
        "files_scanned": len(files),
        "summary": subsystem_summaries,
        "include_sites": [
            asdict(item)
            for item in includes
        ],
        "table_references": [
            asdict(item)
            for item in tables
        ],
        "config_references": [
            asdict(item)
            for item in configs
        ],
    }

    args.json.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    args.json.write_text(
        json.dumps(payload, indent=2) + "\n"
    )

    with args.text.open("w") as handle:
        handle.write(
            "Chisimba LiveUser and language-stack dependency audit\n"
        )
        handle.write(
            "=" * 62 + "\n"
        )
        handle.write(
            f"Generated: {payload['generated_at']}\n"
        )
        handle.write(
            f"Files scanned: {payload['files_scanned']}\n\n"
        )

        for subsystem, summary in subsystem_summaries.items():
            handle.write(
                f"{subsystem}\n"
            )
            handle.write(
                "-" * len(subsystem) + "\n"
            )
            handle.write(
                f"External calls: "
                f"{summary['external_call_count']}\n"
            )
            handle.write(
                f"External files: "
                f"{summary['external_file_count']}\n"
            )
            handle.write(
                f"Used methods: "
                f"{summary['used_method_count']} of "
                f"{summary['available_method_count']}\n"
            )
            handle.write(
                f"Usage ratio: "
                f"{summary['usage_ratio']}\n"
            )
            handle.write(
                "Recommendation: "
                f"{summary['recommendation']}\n"
            )
            handle.write(
                f"Rationale: {summary['rationale']}\n"
            )
            handle.write(
                "Methods: "
                + ", ".join(summary["used_methods"])
                + "\n"
            )
            handle.write(
                "Likely tables: "
                + (
                    ", ".join(summary["likely_tables"])
                    or "none identified"
                )
                + "\n"
            )
            handle.write("Capabilities:\n")

            for capability, details in summary[
                "capabilities"
            ].items():
                handle.write(
                    f"  - {capability}: "
                    f"{details['call_count']} calls; "
                    f"methods={', '.join(details['methods'])}\n"
                )

            handle.write("\n")

            handle.write("External call sites:\n")

            for call in summary["external_calls"]:
                handle.write(
                    f"  {call['file']}:{call['line']} "
                    f"{call['call_style']} "
                    f"{call['method']}()\n"
                )

            handle.write("\n")

    with args.markdown.open("w") as handle:
        handle.write(
            "# LiveUser and Language-Stack Dependency Audit\n\n"
        )
        handle.write(
            f"Generated: `{payload['generated_at']}`  \n"
        )
        handle.write(
            f"Files scanned: **{payload['files_scanned']}**\n\n"
        )

        handle.write("## Executive decision table\n\n")
        handle.write(
            "| Subsystem | External calls | Files | "
            "Used methods | Available methods | Recommendation |\n"
        )
        handle.write(
            "|---|---:|---:|---:|---:|---|\n"
        )

        for subsystem, summary in subsystem_summaries.items():
            handle.write(
                f"| {subsystem} "
                f"| {summary['external_call_count']} "
                f"| {summary['external_file_count']} "
                f"| {summary['used_method_count']} "
                f"| {summary['available_method_count']} "
                f"| {summary['recommendation']} |\n"
            )

        handle.write("\n")

        for subsystem, summary in subsystem_summaries.items():
            handle.write(
                f"## {subsystem}\n\n"
            )
            handle.write(
                f"**Recommendation:** "
                f"{summary['recommendation']}\n\n"
            )
            handle.write(
                f"{summary['rationale']}\n\n"
            )
            handle.write(
                f"- External calls: "
                f"{summary['external_call_count']}\n"
            )
            handle.write(
                f"- External files: "
                f"{summary['external_file_count']}\n"
            )
            handle.write(
                f"- Used methods: "
                f"{summary['used_method_count']} of "
                f"{summary['available_method_count']}\n"
            )
            handle.write(
                "- Methods: "
                + (
                    ", ".join(
                        f"`{method}()`"
                        for method in summary["used_methods"]
                    )
                    or "None detected"
                )
                + "\n"
            )
            handle.write(
                "- Likely tables: "
                + (
                    ", ".join(
                        f"`{table}`"
                        for table in summary["likely_tables"]
                    )
                    or "None identified"
                )
                + "\n\n"
            )

            handle.write("### Capabilities\n\n")

            if not summary["capabilities"]:
                handle.write(
                    "No external capabilities detected.\n\n"
                )
            else:
                for capability, details in summary[
                    "capabilities"
                ].items():
                    handle.write(
                        f"- **{capability}:** "
                        f"{details['call_count']} calls; "
                        f"methods "
                        + ", ".join(
                            f"`{method}()`"
                            for method in details["methods"]
                        )
                        + "\n"
                    )

                handle.write("\n")

            handle.write("### External call sites\n\n")

            if not summary["external_calls"]:
                handle.write(
                    "No external call sites detected.\n\n"
                )
            else:
                for call in summary["external_calls"]:
                    handle.write(
                        f"- `{call['file']}:{call['line']}` — "
                        f"`{call['method']}()` "
                        f"({call['call_style']})\n"
                    )

                handle.write("\n")

    print(
        f"Files scanned: {len(files)}"
    )

    for subsystem, summary in subsystem_summaries.items():
        print()
        print(subsystem)
        print(
            f"  External calls: "
            f"{summary['external_call_count']}"
        )
        print(
            f"  External files: "
            f"{summary['external_file_count']}"
        )
        print(
            f"  Used methods: "
            f"{summary['used_method_count']} / "
            f"{summary['available_method_count']}"
        )
        print(
            f"  Recommendation: "
            f"{summary['recommendation']}"
        )

    print()
    print(f"JSON: {args.json}")
    print(f"Text: {args.text}")
    print(f"Markdown: {args.markdown}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$SCRIPT"

{
    echo "============================================================"
    echo "BOUNDED LIVEUSER AND LANGUAGE-STACK DEPENDENCY AUDIT"
    echo "============================================================"
    echo
    echo "Started: $(date --iso-8601=seconds)"
    echo

    python3 "$SCRIPT" \
        --root "$ROOT" \
        --json "$JSON_REPORT" \
        --text "$TEXT_REPORT" \
        --markdown "$MARKDOWN_REPORT"

    echo
    echo "============================================================"
    echo "EXECUTIVE SUMMARY"
    echo "============================================================"
    echo

    sed -n '1,220p' "$TEXT_REPORT"

    echo
    echo "============================================================"
    echo "GIT STATUS"
    echo "============================================================"

    for REPO in \
        framework \
        modules \
        canvases \
        dev-environment
    do
        echo
        echo "REPOSITORY: $REPO"

        git -C "$ROOT/$REPO" status --short || true
    done

    echo
    echo "============================================================"
    echo "AUDIT COMPLETE"
    echo "============================================================"
    echo
    echo "Reports:"
    echo "  $TEXT_REPORT"
    echo "  $MARKDOWN_REPORT"
    echo "  $JSON_REPORT"
    echo
    echo "No application source files or database records were changed."
    echo "Finished: $(date --iso-8601=seconds)"

} > "$OUT" 2>&1
