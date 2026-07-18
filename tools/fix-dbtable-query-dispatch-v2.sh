#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/classes/core/dbtable_class_inc.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/classes/core/dbtable_class_inc.php"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

replacement = r'''    public function query($stmt) {
        $isResultQuery = $this->_isResultQuery($stmt);

        if ($this->debug == TRUE) {
            log_debug($stmt);
        }

        if ($isResultQuery) {
            $ret = $this->_queryAll($stmt);
        } else {
            $ret = $this->_executeStatement($stmt);
        }

        if (PEAR::isError($ret)) {
            return FALSE;
        }

        return $ret;
    }

    /**
     * Determine whether an SQL statement returns rows.
     *
     * @param string $stmt
     * @return bool
     */
    private function _isResultQuery($stmt) {
        $sql = ltrim($stmt);

        do {
            $previous = $sql;

            $sql = preg_replace(
                '/^\/\*.*?\*\/\s*/s',
                '',
                $sql
            );

            $sql = preg_replace(
                '/^(?:--[^\r\n]*|#[^\r\n]*)[\r\n]+\s*/',
                '',
                $sql
            );
        } while ($sql !== $previous);

        return preg_match(
            '/^(SELECT|SHOW|DESCRIBE|DESC|EXPLAIN|WITH)\b/i',
            $sql
        ) === 1;
    }

    /**
     * Execute SQL that does not return rows.
     *
     * @param string $stmt
     * @return mixed
     */
    private function _executeStatement($stmt) {
        if ($this->dbLayer === 'MDB2') {
            $ret = $this->_db->exec($stmt);

            if (PEAR::isError($ret)) {
                error_log(
                    'MDB2 exec failed: '
                    . $ret->getMessage()
                    . ' | SQL: '
                    . $stmt
                );

                return FALSE;
            }

            return $ret;
        }

        if ($this->dbLayer === 'PDO') {
            try {
                return $this->_db->exec($stmt);
            } catch (PDOException $e) {
                throw new customException($e->getMessage());
            }
        }

        return FALSE;
    }
'''

def locate_method(text: str) -> tuple[int, int]:
    match = re.search(
        r'^[ \t]*public[ \t]+function[ \t]+query[ \t]*'
        r'\([ \t]*\$stmt[ \t]*\)[ \t]*\{',
        text,
        re.MULTILINE,
    )

    if match is None:
        raise RuntimeError("Could not find dbTable::query($stmt)")

    opening = text.find("{", match.start())
    depth = 0
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
                return match.start(), index + 1

    raise RuntimeError("Could not find end of dbTable::query()")


for filename in sys.argv[1:]:
    path = Path(filename)

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    text = path.read_text(errors="replace")

    if (
        "private function _isResultQuery" in text
        and "private function _executeStatement" in text
    ):
        print(f"ALREADY PATCHED: {path}")
        continue

    try:
        start, end = locate_method(text)
    except RuntimeError as error:
        raise SystemExit(f"{path}: {error}")

    backup = path.with_name(
        path.name + ".before-php82-query-dispatch-v2"
    )

    if not backup.exists():
        backup.write_text(text)

    updated = text[:start] + replacement + text[end:]
    path.write_text(updated)

    print(f"UPDATED: {path}")
PY

echo
echo "===== SOURCE QUERY METHOD ====="
nl -ba "$SOURCE" | sed -n '895,1045p'

echo
echo "===== RUNTIME QUERY METHOD ====="
nl -ba "$RUNTIME" | sed -n '895,1045p'

echo
echo "===== CONFIRM OLD DISPATCH IS GONE ====="

if sed -n '895,1045p' "$RUNTIME" \
    | grep -n '\$ret = \$this->_queryAll(\$stmt);'
then
    echo "The SELECT branch above is expected."
fi

if sed -n '895,980p' "$RUNTIME" \
    | grep -q 'public function query' &&
   sed -n '895,980p' "$RUNTIME" \
    | grep -q '_executeStatement'
then
    echo "Runtime query dispatch is present."
else
    echo "ERROR: Runtime query dispatch is absent."
    exit 1
fi

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/classes/core/dbtable_class_inc.php

echo
echo "===== MDB2 EXEC SUPPORT ====="

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "MDB2.php";

        echo "MDB2 exec available: ",
            method_exists("MDB2_Driver_Common", "exec")
                ? "yes"
                : "no",
            PHP_EOL;

        exit(
            method_exists("MDB2_Driver_Common", "exec")
                ? 0
                : 1
        );
    '

echo
echo "===== REQUEST CHISIMBA ====="

curl \
    --silent \
    --show-error \
    --location \
    --max-time 45 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

echo
echo "===== RECENT WEB LOG ====="

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=140 web
