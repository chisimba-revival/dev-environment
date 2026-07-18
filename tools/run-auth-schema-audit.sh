#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
TOOLS="$ROOT/dev-environment/tools"
REPORTS="$ROOT/dev-environment/reports"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
PYTHON="$TOOLS/audit-auth-schema.py"
OUT="$ROOT/killme.txt"

DB_SCHEMA_RAW="$REPORTS/auth-schema-database-raw.txt"
SOURCE_SCHEMA_RAW="$REPORTS/auth-schema-source-raw.txt"
TEXT_REPORT="$REPORTS/auth-schema-audit.txt"
MARKDOWN_REPORT="$REPORTS/auth-schema-audit.md"
JSON_REPORT="$REPORTS/auth-schema-audit.json"

mkdir -p "$REPORTS"

cat > "$PYTHON" <<'PY'
#!/usr/bin/env python3

from __future__ import annotations

import argparse
import collections
import datetime
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path


TABLES = (
    "tbl_users",
    "tbl_perms_groups",
    "tbl_perms_groupusers",
    "tbl_perms_perm_users",
)


@dataclass
class Column:
    table: str
    name: str
    data_type: str
    column_type: str
    nullable: bool
    default: str | None
    key: str
    extra: str
    source: str


def classify_column(table: str, name: str) -> str:
    value = name.lower()

    identity_terms = (
        "id",
        "userid",
        "user_id",
        "puid",
        "username",
        "login",
        "email",
    )

    credential_terms = (
        "password",
        "passwd",
        "salt",
        "hash",
        "secret",
        "token",
    )

    session_terms = (
        "session",
        "lastlogin",
        "last_login",
        "login_time",
        "lastactivity",
        "last_activity",
        "active",
        "isactive",
        "status",
    )

    profile_terms = (
        "firstname",
        "first_name",
        "surname",
        "lastname",
        "last_name",
        "title",
        "gender",
        "country",
        "language",
        "birth",
        "phone",
        "mobile",
        "address",
        "description",
        "image",
        "staff",
        "student",
        "created",
        "modified",
        "date",
    )

    permission_terms = (
        "group",
        "role",
        "permission",
        "perm",
        "right",
        "area",
        "context",
    )

    relationship_terms = (
        "parent",
        "child",
        "user",
        "group",
        "permission",
        "perm",
    )

    if any(term == value or value.endswith("_" + term) for term in credential_terms):
        return "credential"

    if any(term in value for term in session_terms):
        return "session and account state"

    if table == "tbl_users":
        if value in identity_terms or any(term in value for term in identity_terms):
            return "identity"

        if any(term in value for term in profile_terms):
            return "profile"

        return "other user metadata"

    if table == "tbl_perms_groups":
        if any(term in value for term in permission_terms):
            return "group and role definition"

        if "name" in value or "description" in value:
            return "group and role definition"

        return "group metadata"

    if table in {"tbl_perms_groupusers", "tbl_perms_perm_users"}:
        if any(term in value for term in relationship_terms):
            return "relationship key"

        return "relationship metadata"

    return "other"


def parse_database_schema(path: Path) -> list[Column]:
    columns: list[Column] = []

    if not path.is_file():
        return columns

    current_table = None

    for raw_line in path.read_text(errors="replace").splitlines():
        line = raw_line.rstrip("\n")

        if line.startswith("### TABLE "):
            current_table = line.removeprefix("### TABLE ").strip()
            continue

        if not current_table or "\t" not in line:
            continue

        parts = line.split("\t")

        if len(parts) < 8:
            continue

        (
            name,
            data_type,
            column_type,
            nullable,
            default,
            key,
            extra,
            _comment,
        ) = parts[:8]

        columns.append(
            Column(
                table=current_table,
                name=name,
                data_type=data_type,
                column_type=column_type,
                nullable=nullable.upper() == "YES",
                default=None if default == "NULL" else default,
                key=key,
                extra=extra,
                source="database",
            )
        )

    return columns


def parse_source_definitions(path: Path) -> dict[str, list[str]]:
    definitions: dict[str, list[str]] = collections.defaultdict(list)

    if not path.is_file():
        return definitions

    text = path.read_text(errors="replace")

    marker = re.compile(
        r"^### FILE (.+)$",
        re.MULTILINE,
    )

    matches = list(marker.finditer(text))

    for index, match in enumerate(matches):
        start = match.end()
        end = (
            matches[index + 1].start()
            if index + 1 < len(matches)
            else len(text)
        )

        filename = match.group(1)
        content = text[start:end]

        for table in TABLES:
            if re.search(rf"\b{re.escape(table)}\b", content, re.IGNORECASE):
                definitions[table].append(filename)

    return definitions


def minimum_contract(table: str, columns: list[Column]) -> list[str]:
    names = {column.name.lower(): column.name for column in columns}

    def existing(*candidates: str) -> list[str]:
        result = []

        for candidate in candidates:
            if candidate.lower() in names:
                result.append(names[candidate.lower()])

        return result

    if table == "tbl_users":
        contract = []

        contract.extend(existing("id", "userid", "user_id"))
        contract.extend(existing("username", "login"))
        contract.extend(existing("password", "passwd"))
        contract.extend(existing("email"))
        contract.extend(existing("active", "isactive", "status"))
        contract.extend(existing("puid"))

        return list(dict.fromkeys(contract))

    if table == "tbl_perms_groups":
        contract = []
        contract.extend(existing("id", "groupid", "group_id"))
        contract.extend(existing("name", "groupname"))
        contract.extend(existing("parentid", "parent_id"))
        return list(dict.fromkeys(contract))

    if table == "tbl_perms_groupusers":
        contract = []
        contract.extend(existing("id"))
        contract.extend(existing("groupid", "group_id"))
        contract.extend(existing("userid", "user_id"))
        return list(dict.fromkeys(contract))

    if table == "tbl_perms_perm_users":
        contract = []
        contract.extend(existing("id"))
        contract.extend(existing("permid", "perm_id", "permissionid"))
        contract.extend(existing("userid", "user_id"))
        contract.extend(existing("value", "allow", "granted"))
        return list(dict.fromkeys(contract))

    return []


def assessment(
    table: str,
    columns: list[Column],
    source_files: list[str],
) -> str:
    if not columns:
        return (
            "The live database table was not found or could not be inspected. "
            "Use source definitions only until a clean installed schema is available."
        )

    categories = collections.Counter(
        classify_column(table, column.name)
        for column in columns
    )

    if table == "tbl_users":
        credential_count = categories.get("credential", 0)
        identity_count = categories.get("identity", 0)

        if credential_count <= 3 and identity_count <= 8:
            return (
                "The table can be retained. Authentication-specific fields form "
                "a small subset; profile and application data should remain in "
                "place while a native PHP 8.2 authentication service reads only "
                "the identity, credential and account-state fields."
            )

        return (
            "Retain the table initially, but introduce a user repository before "
            "replacing authentication because credentials and profile concerns "
            "are heavily mixed."
        )

    if table == "tbl_perms_groups":
        return (
            "Retain the table. It represents Chisimba's domain model for groups "
            "and roles rather than an implementation detail of LiveUser."
        )

    if table == "tbl_perms_groupusers":
        return (
            "Retain the table. It is a conventional user-to-group relationship "
            "that can be accessed through a small membership repository."
        )

    if table == "tbl_perms_perm_users":
        return (
            "Retain the table initially. Encapsulate direct user permissions "
            "behind a permission repository so its legacy semantics can be "
            "verified against PHP 7.4 before later schema simplification."
        )

    return "Review manually."


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument("--db-schema", type=Path, required=True)
    parser.add_argument("--source-schema", type=Path, required=True)
    parser.add_argument("--text", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)

    args = parser.parse_args()

    columns = parse_database_schema(args.db_schema)
    source_definitions = parse_source_definitions(args.source_schema)

    table_columns = {
        table: [
            column
            for column in columns
            if column.table.lower() == table.lower()
        ]
        for table in TABLES
    }

    summaries = {}

    for table in TABLES:
        current_columns = table_columns[table]
        categories = collections.defaultdict(list)

        for column in current_columns:
            categories[
                classify_column(table, column.name)
            ].append(column.name)

        summaries[table] = {
            "exists_in_database": bool(current_columns),
            "column_count": len(current_columns),
            "columns": [asdict(column) for column in current_columns],
            "categories": {
                category: sorted(names)
                for category, names in sorted(categories.items())
            },
            "primary_or_indexed_columns": [
                column.name
                for column in current_columns
                if column.key
            ],
            "auto_increment_columns": [
                column.name
                for column in current_columns
                if "auto_increment" in column.extra.lower()
            ],
            "minimum_php82_contract": minimum_contract(
                table,
                current_columns,
            ),
            "source_definition_files": sorted(
                set(source_definitions.get(table, []))
            ),
            "assessment": assessment(
                table,
                current_columns,
                source_definitions.get(table, []),
            ),
        }

    payload = {
        "generated_at": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(),
        "tables": summaries,
        "recommended_architecture": {
            "schema": "Retain existing authentication and permission tables initially.",
            "user_repository": (
                "Add a repository that owns identity, profile and account-state "
                "queries against tbl_users."
            ),
            "authentication_service": (
                "Implement password verification, login, logout and sessions "
                "without LiveUser."
            ),
            "group_repository": (
                "Encapsulate tbl_perms_groups and tbl_perms_groupusers."
            ),
            "permission_repository": (
                "Encapsulate tbl_perms_perm_users and preserve legacy semantics "
                "using PHP 7.4 behavioural tests."
            ),
            "migration_rule": (
                "No schema redesign until PHP 8.2 login, logout, group membership "
                "and permission checks match the PHP 7.4 baseline."
            ),
        },
        "limitations": [
            "This audit describes schema structure, not every runtime invariant.",
            "Dynamic SQL and database triggers may require additional review.",
            "Password hashing behaviour must be verified separately.",
            "Permission precedence must be tested against the PHP 7.4 baseline.",
        ],
    }

    args.json.write_text(
        json.dumps(payload, indent=2) + "\n"
    )

    with args.text.open("w") as handle:
        handle.write("Chisimba authentication schema audit\n")
        handle.write("=" * 37 + "\n\n")

        for table, summary in summaries.items():
            handle.write(f"{table}\n")
            handle.write("-" * len(table) + "\n")
            handle.write(
                f"Exists in live database: "
                f"{'yes' if summary['exists_in_database'] else 'no'}\n"
            )
            handle.write(
                f"Columns: {summary['column_count']}\n"
            )
            handle.write(
                "Indexed/key columns: "
                + (
                    ", ".join(summary["primary_or_indexed_columns"])
                    or "none detected"
                )
                + "\n"
            )
            handle.write(
                "Minimum PHP 8.2 contract: "
                + (
                    ", ".join(summary["minimum_php82_contract"])
                    or "not determined"
                )
                + "\n"
            )
            handle.write("Categories:\n")

            for category, names in summary["categories"].items():
                handle.write(
                    f"  {category}: {', '.join(names)}\n"
                )

            handle.write(
                "Source definitions:\n"
            )

            for filename in summary["source_definition_files"]:
                handle.write(f"  {filename}\n")

            handle.write(
                f"Assessment: {summary['assessment']}\n\n"
            )

        handle.write("Recommended architecture\n")
        handle.write("------------------------\n")

        for name, value in payload[
            "recommended_architecture"
        ].items():
            handle.write(f"{name}: {value}\n")

    with args.markdown.open("w") as handle:
        handle.write("# Authentication Schema Audit\n\n")

        handle.write("## Executive conclusion\n\n")
        handle.write(
            "Retain the existing user, group and permission schema for the "
            "initial PHP 8.2 migration. Replace abandoned authentication "
            "middleware behind repository and service interfaces before "
            "considering schema redesign.\n\n"
        )

        handle.write("## Table summary\n\n")
        handle.write(
            "| Table | Present | Columns | Minimum PHP 8.2 contract |\n"
        )
        handle.write("|---|---:|---:|---|\n")

        for table, summary in summaries.items():
            contract = ", ".join(
                f"`{name}`"
                for name in summary["minimum_php82_contract"]
            ) or "Not determined"

            handle.write(
                f"| `{table}` "
                f"| {'Yes' if summary['exists_in_database'] else 'No'} "
                f"| {summary['column_count']} "
                f"| {contract} |\n"
            )

        handle.write("\n")

        for table, summary in summaries.items():
            handle.write(f"## `{table}`\n\n")
            handle.write(f"{summary['assessment']}\n\n")

            handle.write("### Columns by responsibility\n\n")

            for category, names in summary["categories"].items():
                handle.write(
                    f"- **{category}:** "
                    + ", ".join(f"`{name}`" for name in names)
                    + "\n"
                )

            handle.write("\n### Keys and indexes\n\n")

            if summary["primary_or_indexed_columns"]:
                for name in summary["primary_or_indexed_columns"]:
                    handle.write(f"- `{name}`\n")
            else:
                handle.write("None detected.\n")

            handle.write("\n### Source definitions\n\n")

            if summary["source_definition_files"]:
                for filename in summary["source_definition_files"]:
                    handle.write(f"- `{filename}`\n")
            else:
                handle.write("No source definition located.\n")

            handle.write("\n")

        handle.write("## Recommended PHP 8.2 architecture\n\n")

        for name, value in payload[
            "recommended_architecture"
        ].items():
            heading = name.replace("_", " ").title()
            handle.write(f"### {heading}\n\n{value}\n\n")

        handle.write("## Limitations\n\n")

        for limitation in payload["limitations"]:
            handle.write(f"- {limitation}\n")

    print("Authentication schema audit complete")

    for table, summary in summaries.items():
        print(
            f"{table}: "
            f"present={'yes' if summary['exists_in_database'] else 'no'}, "
            f"columns={summary['column_count']}, "
            f"contract={','.join(summary['minimum_php82_contract']) or 'unknown'}"
        )

    print(f"Text: {args.text}")
    print(f"Markdown: {args.markdown}")
    print(f"JSON: {args.json}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$PYTHON"

rm -f \
    "$DB_SCHEMA_RAW" \
    "$SOURCE_SCHEMA_RAW" \
    "$TEXT_REPORT" \
    "$MARKDOWN_REPORT" \
    "$JSON_REPORT"

{
    echo "============================================================"
    echo "CHISIMBA AUTHENTICATION SCHEMA AUDIT"
    echo "============================================================"
    echo
    echo "Started: $(date --iso-8601=seconds)"

    echo
    echo "===== LIVE DATABASE TABLE STRUCTURE ====="

    for TABLE in \
        tbl_users \
        tbl_perms_groups \
        tbl_perms_groupusers \
        tbl_perms_perm_users
    do
        echo "### TABLE $TABLE" | tee -a "$DB_SCHEMA_RAW"

        docker compose \
            -f "$COMPOSE" \
            exec -T db \
            mysql \
            -uroot \
            -proot \
            --batch \
            --skip-column-names \
            -e "
                SELECT
                    COLUMN_NAME,
                    DATA_TYPE,
                    COLUMN_TYPE,
                    IS_NULLABLE,
                    COALESCE(COLUMN_DEFAULT, 'NULL'),
                    COLUMN_KEY,
                    EXTRA,
                    COLUMN_COMMENT
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = 'chisimba'
                  AND TABLE_NAME = '${TABLE}'
                ORDER BY ORDINAL_POSITION;
            " \
            >> "$DB_SCHEMA_RAW" 2>&1 || true

        echo >> "$DB_SCHEMA_RAW"
    done

    cat "$DB_SCHEMA_RAW"

    echo
    echo "===== SOURCE DEFINITIONS AND ALTERATIONS ====="

    for SOURCE_ROOT in \
        "$ROOT/framework/app" \
        "$ROOT/modules" \
        "$ROOT/canvases"
    do
        grep -RIl \
            --include='*.php' \
            --include='*.inc' \
            --include='*.sql' \
            --include='*.xml' \
            -E \
            'tbl_users|tbl_perms_groups|tbl_perms_groupusers|tbl_perms_perm_users' \
            "$SOURCE_ROOT" \
            2>/dev/null || true
    done \
    | sort -u \
    | while IFS= read -r FILE; do
        echo "### FILE $FILE" >> "$SOURCE_SCHEMA_RAW"

        grep -n -A30 -B10 \
            -E \
            'CREATE[[:space:]]+TABLE.*(tbl_users|tbl_perms_groups|tbl_perms_groupusers|tbl_perms_perm_users)|ALTER[[:space:]]+TABLE.*(tbl_users|tbl_perms_groups|tbl_perms_groupusers|tbl_perms_perm_users)|<table[^>]*name="?(tbl_users|tbl_perms_groups|tbl_perms_groupusers|tbl_perms_perm_users)' \
            "$FILE" \
            >> "$SOURCE_SCHEMA_RAW" \
            2>&1 || true

        echo >> "$SOURCE_SCHEMA_RAW"
    done

    sed -n '1,500p' "$SOURCE_SCHEMA_RAW"

    echo
    echo "===== GENERATE AUDIT REPORT ====="

    python3 "$PYTHON" \
        --db-schema "$DB_SCHEMA_RAW" \
        --source-schema "$SOURCE_SCHEMA_RAW" \
        --text "$TEXT_REPORT" \
        --markdown "$MARKDOWN_REPORT" \
        --json "$JSON_REPORT"

    echo
    echo "============================================================"
    echo "EXECUTIVE SUMMARY"
    echo "============================================================"
    echo

    cat "$TEXT_REPORT"

    echo
    echo "============================================================"
    echo "AUDIT COMPLETE"
    echo "============================================================"
    echo
    echo "Finished: $(date --iso-8601=seconds)"
    echo
    echo "Reports:"
    echo "  $TEXT_REPORT"
    echo "  $MARKDOWN_REPORT"
    echo "  $JSON_REPORT"
    echo
    echo "No database records or application source files were changed."

} > "$OUT" 2>&1
