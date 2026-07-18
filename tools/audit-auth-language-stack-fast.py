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


TARGET_TERMS = (
    "LiveUser",
    "LiveUser_Admin",
    "Translation2",
    "I18Nv2",
    "Event_Dispatcher",
)

ALLOWED_SUFFIXES = (
    ".php",
    ".inc",
    ".inc.php",
    "_class_inc.php",
    ".xml",
    ".sql",
)

IGNORED_DIRS = {
    ".git",
    "node_modules",
    "vendor",
    "__pycache__",
}

STATIC_PATTERNS = {
    "LiveUser": re.compile(
        r"\bLiveUser::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        re.IGNORECASE,
    ),
    "LiveUser_Admin": re.compile(
        r"\bLiveUser_Admin::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        re.IGNORECASE,
    ),
    "Translation2": re.compile(
        r"\b(?:Translation2|Translation2_Admin|Translation2_Decorator)"
        r"::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        re.IGNORECASE,
    ),
    "I18Nv2": re.compile(
        r"\bI18Nv2::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        re.IGNORECASE,
    ),
    "Event_Dispatcher": re.compile(
        r"\bEvent_Dispatcher::([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        re.IGNORECASE,
    ),
}

INSTANCE_PATTERNS = {
    "LiveUser": re.compile(
        r"""
        (?:
            \$this->lu|
            \$this->_lu|
            \$_lu|
            \$liveUser|
            \$objLiveUser
        )
        ->([A-Za-z_][A-Za-z0-9_]*)\s*\(
        """,
        re.IGNORECASE | re.VERBOSE,
    ),
    "LiveUser_Admin": re.compile(
        r"""
        (?:
            \$this->luAdmin|
            \$this->_luAdmin|
            \$_luAdmin|
            \$liveUserAdmin
        )
        ->([A-Za-z_][A-Za-z0-9_]*)\s*\(
        """,
        re.IGNORECASE | re.VERBOSE,
    ),
    "Translation2": re.compile(
        r"""
        (?:
            \$this->translation|
            \$this->translation2|
            \$this->_translation|
            \$translation|
            \$translation2|
            \$decorator
        )
        ->([A-Za-z_][A-Za-z0-9_]*)\s*\(
        """,
        re.IGNORECASE | re.VERBOSE,
    ),
    "I18Nv2": re.compile(
        r"""
        (?:
            \$this->i18n|
            \$this->i18nv2|
            \$i18n|
            \$locale
        )
        ->([A-Za-z_][A-Za-z0-9_]*)\s*\(
        """,
        re.IGNORECASE | re.VERBOSE,
    ),
    "Event_Dispatcher": re.compile(
        r"""
        (?:
            \$this->eventDispatcher|
            \$this->dispatcher|
            \$eventDispatcher|
            \$dispatcher|
            ->dispatcher
        )
        ->(addObserver|removeObserver|post|postNotification|
           observerRegistered|getObservers)\s*\(
        """,
        re.IGNORECASE | re.VERBOSE,
    ),
}

LIBRARY_FILES = {
    "LiveUser": (
        "framework/app/lib/pear/LiveUser.php",
    ),
    "LiveUser_Admin": (
        "framework/app/lib/pear/LiveUser/Admin.php",
    ),
    "Translation2": (
        "framework/app/lib/pear/Translation2.php",
        "framework/app/lib/pear/Translation2/Admin.php",
        "framework/app/lib/pear/Translation2/Decorator.php",
    ),
    "I18Nv2": (
        "framework/app/lib/pear/I18Nv2.php",
    ),
    "Event_Dispatcher": (
        "framework/app/lib/pear/Event/Dispatcher.php",
        "framework/app/lib/pear/Event/Notification.php",
    ),
}

TABLE_TERMS = {
    "LiveUser": (
        "user",
        "group",
        "role",
        "right",
        "permission",
        "login",
        "auth",
        "area",
    ),
    "LiveUser_Admin": (
        "user",
        "group",
        "role",
        "right",
        "permission",
        "login",
        "auth",
        "area",
    ),
    "Translation2": (
        "language",
        "translation",
        "phrase",
        "text",
        "word",
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


@dataclass
class Call:
    subsystem: str
    method: str
    file: str
    line: int
    style: str
    text: str


def iter_source_files(roots: list[Path]):
    for root in roots:
        if not root.exists():
            continue

        for directory, dirnames, filenames in os.walk(root):
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


def relevant_file(path: Path) -> tuple[bool, str]:
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return False, ""

    return any(term in text for term in TARGET_TERMS), text


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def line_content(text: str, number: int) -> str:
    lines = text.splitlines()

    if 1 <= number <= len(lines):
        return lines[number - 1].strip()

    return ""


def library_methods(root: Path, subsystem: str) -> set[str]:
    methods: set[str] = set()

    for relative in LIBRARY_FILES[subsystem]:
        path = root / relative

        if not path.is_file():
            continue

        text = path.read_text(errors="replace")

        methods.update(
            re.findall(
                r"\bfunction\s+&?\s*"
                r"([A-Za-z_][A-Za-z0-9_]*)\s*\(",
                text,
                re.IGNORECASE,
            )
        )

    return methods


def capability(subsystem: str, method: str) -> str:
    value = method.lower()

    if any(term in value for term in (
        "login", "logout", "auth", "password", "credential"
    )):
        return "authentication"

    if any(term in value for term in (
        "right", "permission", "perm", "role", "group", "area"
    )):
        return "permissions and roles"

    if any(term in value for term in (
        "session", "cookie", "freeze", "idle", "expire"
    )):
        return "sessions"

    if any(term in value for term in (
        "user", "admin", "container", "storage"
    )):
        return "user administration"

    if any(term in value for term in (
        "translate", "string", "message", "text"
    )):
        return "translation"

    if any(term in value for term in (
        "locale", "language", "country", "currency", "date"
    )):
        return "locale handling"

    if any(term in value for term in (
        "observer", "post", "notification", "dispatch"
    )):
        return "event dispatch"

    if any(term in value for term in (
        "factory", "singleton", "loadclass", "init"
    )):
        return "object construction and configuration"

    return "other"


def decision(
    subsystem: str,
    used_count: int,
    available_count: int,
    capability_count: int,
) -> tuple[str, str]:
    if subsystem == "Event_Dispatcher":
        return (
            "replace",
            "The exposed interface is small and maps naturally to a "
            "Chisimba-native event dispatcher.",
        )

    if subsystem == "I18Nv2":
        return (
            "replace behind adapter",
            "PHP intl can provide the core locale services while an adapter "
            "preserves Chisimba-facing method names.",
        )

    if subsystem == "Translation2":
        if used_count <= 15:
            return (
                "replace behind adapter",
                "The detected external method surface is bounded enough to "
                "reimplement without preserving the full abandoned package.",
            )

        return (
            "isolate temporarily, then replace",
            "Usage is broader than expected; first add a Chisimba translation "
            "interface and move callers behind it.",
        )

    if subsystem in {"LiveUser", "LiveUser_Admin"}:
        if used_count <= 25 and capability_count <= 7:
            return (
                "replace behind authentication adapter",
                "The detected Chisimba-facing surface is bounded. Reproduce "
                "login, sessions, users, groups and rights using PHP 7.4 as "
                "the behavioural reference.",
            )

        return (
            "formal compatibility fork, then adapter",
            "The detected surface is broad enough that immediate replacement "
            "would be risky. Stabilise it behind an adapter first.",
        )

    return "review", "No automatic recommendation available."


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--json", required=True, type=Path)
    parser.add_argument("--text", required=True, type=Path)
    parser.add_argument("--markdown", required=True, type=Path)
    args = parser.parse_args()

    root = args.root

    roots = [
        root / "framework" / "app",
        root / "modules",
        root / "canvases",
    ]

    scanned = 0
    relevant = 0
    calls: list[Call] = []
    table_refs: dict[str, set[str]] = {
        subsystem: set()
        for subsystem in STATIC_PATTERNS
    }
    relevant_files: list[str] = []

    for path in iter_source_files(roots):
        scanned += 1

        is_relevant, text = relevant_file(path)

        if not is_relevant:
            continue

        relevant += 1
        relative = str(path.relative_to(root))
        relevant_files.append(relative)

        for subsystem, pattern in STATIC_PATTERNS.items():
            for match in pattern.finditer(text):
                number = line_number(text, match.start())

                calls.append(
                    Call(
                        subsystem=subsystem,
                        method=match.group(1),
                        file=relative,
                        line=number,
                        style="static",
                        text=line_content(text, number),
                    )
                )

        for subsystem, pattern in INSTANCE_PATTERNS.items():
            for match in pattern.finditer(text):
                number = line_number(text, match.start())

                calls.append(
                    Call(
                        subsystem=subsystem,
                        method=match.group(1),
                        file=relative,
                        line=number,
                        style="instance",
                        text=line_content(text, number),
                    )
                )

        for table in re.findall(
            r"\b(tbl_[A-Za-z0-9_]+)\b",
            text,
            re.IGNORECASE,
        ):
            lower = table.lower()

            for subsystem, terms in TABLE_TERMS.items():
                if any(term in lower for term in terms):
                    table_refs[subsystem].add(lower)

    summaries = {}

    for subsystem in STATIC_PATTERNS:
        subsystem_calls = [
            call
            for call in calls
            if call.subsystem == subsystem
        ]

        external_calls = [
            call
            for call in subsystem_calls
            if "/lib/pear/" not in f"/{call.file}"
        ]

        used_methods = sorted(
            {call.method for call in external_calls},
            key=str.lower,
        )

        available_methods = sorted(
            library_methods(root, subsystem),
            key=str.lower,
        )

        capabilities = collections.defaultdict(set)

        for call in external_calls:
            capabilities[
                capability(subsystem, call.method)
            ].add(call.method)

        recommendation, rationale = decision(
            subsystem,
            len(used_methods),
            len(available_methods),
            len(capabilities),
        )

        summaries[subsystem] = {
            "external_call_count": len(external_calls),
            "external_file_count": len(
                {call.file for call in external_calls}
            ),
            "used_methods": used_methods,
            "used_method_count": len(used_methods),
            "available_method_count": len(available_methods),
            "usage_ratio": (
                round(
                    len(used_methods) / len(available_methods),
                    3,
                )
                if available_methods
                else None
            ),
            "capabilities": {
                name: sorted(methods, key=str.lower)
                for name, methods in sorted(capabilities.items())
            },
            "likely_tables": sorted(table_refs[subsystem]),
            "recommendation": recommendation,
            "rationale": rationale,
            "calls": [
                asdict(call)
                for call in external_calls
            ],
        }

    payload = {
        "generated_at": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(),
        "scope": [
            "framework/app",
            "modules",
            "canvases",
        ],
        "limitations": [
            "The audit records exact static calls.",
            "Instance calls are recorded only for known integration variable names.",
            "Dynamic method calls and aliases may require later manual review.",
            "Runtime copies and backups are intentionally excluded.",
        ],
        "files_scanned": scanned,
        "relevant_files_scanned": relevant,
        "relevant_files": sorted(relevant_files),
        "summary": summaries,
    }

    args.json.write_text(
        json.dumps(payload, indent=2) + "\n"
    )

    with args.text.open("w") as handle:
        handle.write(
            "Chisimba bounded authentication and language-stack audit\n"
        )
        handle.write("=" * 59 + "\n\n")
        handle.write(f"Files scanned: {scanned}\n")
        handle.write(f"Relevant files: {relevant}\n\n")

        for subsystem, summary in summaries.items():
            handle.write(f"{subsystem}\n")
            handle.write("-" * len(subsystem) + "\n")
            handle.write(
                f"External calls: {summary['external_call_count']}\n"
            )
            handle.write(
                f"External files: {summary['external_file_count']}\n"
            )
            handle.write(
                f"Used methods: {summary['used_method_count']} of "
                f"{summary['available_method_count']}\n"
            )
            handle.write(
                f"Recommendation: {summary['recommendation']}\n"
            )
            handle.write(f"Rationale: {summary['rationale']}\n")
            handle.write(
                "Methods: "
                + (", ".join(summary["used_methods"]) or "none")
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

            for name, methods in summary["capabilities"].items():
                handle.write(
                    f"  {name}: {', '.join(methods)}\n"
                )

            handle.write("Call sites:\n")

            for call in summary["calls"]:
                handle.write(
                    f"  {call['file']}:{call['line']} "
                    f"{call['style']} {call['method']}()\n"
                )

            handle.write("\n")

    with args.markdown.open("w") as handle:
        handle.write(
            "# Bounded LiveUser and Language-Stack Audit\n\n"
        )
        handle.write(
            f"Files scanned: **{scanned}**  \n"
        )
        handle.write(
            f"Relevant files examined: **{relevant}**\n\n"
        )

        handle.write("## Executive decision table\n\n")
        handle.write(
            "| Subsystem | Calls | Files | Used methods | "
            "Available methods | Recommendation |\n"
        )
        handle.write(
            "|---|---:|---:|---:|---:|---|\n"
        )

        for subsystem, summary in summaries.items():
            handle.write(
                f"| {subsystem} "
                f"| {summary['external_call_count']} "
                f"| {summary['external_file_count']} "
                f"| {summary['used_method_count']} "
                f"| {summary['available_method_count']} "
                f"| {summary['recommendation']} |\n"
            )

        handle.write("\n")

        for subsystem, summary in summaries.items():
            handle.write(f"## {subsystem}\n\n")
            handle.write(
                f"**Recommendation:** "
                f"{summary['recommendation']}\n\n"
            )
            handle.write(
                f"{summary['rationale']}\n\n"
            )
            handle.write(
                "- Used methods: "
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

            for name, methods in summary["capabilities"].items():
                handle.write(
                    f"- **{name}:** "
                    + ", ".join(
                        f"`{method}()`"
                        for method in methods
                    )
                    + "\n"
                )

            handle.write("\n### Call sites\n\n")

            for call in summary["calls"]:
                handle.write(
                    f"- `{call['file']}:{call['line']}` — "
                    f"`{call['method']}()` ({call['style']})\n"
                )

            handle.write("\n")

        handle.write("## Audit limitations\n\n")

        for limitation in payload["limitations"]:
            handle.write(f"- {limitation}\n")

    print(f"Files scanned: {scanned}")
    print(f"Relevant files examined: {relevant}")

    for subsystem, summary in summaries.items():
        print(
            f"{subsystem}: "
            f"{summary['external_call_count']} calls, "
            f"{summary['used_method_count']} methods, "
            f"{summary['recommendation']}"
        )

    print(f"Text report: {args.text}")
    print(f"Markdown report: {args.markdown}")
    print(f"JSON report: {args.json}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
