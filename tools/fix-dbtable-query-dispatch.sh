#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/classes/core/dbtable_class_inc.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/classes/core/dbtable_class_inc.php"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

section "Modernise dbTable::query() dispatch"

for FILE in "$SOURCE" "$RUNTIME"; do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

marker = "PHP 8 compatibility: distinguish result queries from execution statements"

new_query_method = r'''    /**
     * Method to execute a query against the database.
     *
     * PHP 8 compatibility: distinguish result queries from execution statements.
     *
     * SELECT-like statements return arrays of rows. INSERT, UPDATE, DELETE
     * and DDL statements return the database driver's execution result.
     *
     * @param string $stmt SQL statement
     * @return mixed
     * @deprecated see execute()
     * @access public
     */
    public function query($stmt) {
        $isResultQuery = $this->_isResultQuery($stmt);

        /*
         * Only cache statements that return result sets. Caching INSERT,
         * UPDATE, DELETE or DDL results would be incorrect.
         */
        if ($isResultQuery && $this->objMemcache == TRUE) {
            $cacheKey = md5($this->cachePrefix . $stmt);
            $cache = chisimbacache::getMem()->get($cacheKey);

            if ($cache !== FALSE) {
                return unserialize($cache);
            }

            if ($this->debug == TRUE) {
                log_debug($stmt);
            }

            $ret = $this->_queryAll($stmt);

            if (PEAR::isError($ret)) {
                return FALSE;
            }

            chisimbacache::getMem()->set(
                $cacheKey,
                serialize($ret),
                MEMCACHE_COMPRESSED,
                $this->cacheTTL
            );

            return $ret;
        }

        if ($isResultQuery && $this->objAPC == TRUE) {
            $cacheKey = $this->cachePrefix . $stmt;
            $ret = apc_fetch($cacheKey);

            if ($ret !== FALSE) {
                return $ret;
            }

            if ($this->debug == TRUE) {
                log_debug($stmt);
            }

            $ret = $this->_queryAll($stmt);

            if (PEAR::isError($ret)) {
                return FALSE;
            }

            apc_store($cacheKey, $ret, $this->cacheTTL);

            return $ret;
        }

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
     * Determine whether an SQL statement is expected to return rows.
     *
     * Leading whitespace and SQL comments are ignored.
     *
     * @param string $stmt SQL statement
     * @return bool
     */
    private function _isResultQuery($stmt) {
        $sql = ltrim($stmt);

        /*
         * Remove leading block and single-line comments before inspecting
         * the first SQL keyword.
         */
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
     * Execute an SQL statement that does not return a result set.
     *
     * @param string $stmt SQL statement
     * @return mixed affected-row count, success value or FALSE
     */
    private function _executeStatement($stmt) {
        if ($this->dbLayer === 'MDB2') {
            $ret = $this->_db->exec($stmt);

            if (PEAR::isError($ret)) {
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

method_pattern = re.compile(
    r'''
    ^[ \t]*public[ \t]+function[ \t]+query[ \t]*\(
        [ \t]*\$stmt[ \t]*
    \)[ \t]*\{
    .*?
    ^[ \t]*\}
    (?=
        [ \t\r\n]*
        /\*\*
        [ \t\r\n]*
        \*[ \t]+Method[ \t]+to[ \t]+construct
    )
    ''',
    re.MULTILINE | re.DOTALL | re.VERBOSE,
)

for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text(errors="replace")

    if marker in text:
        print(f"ALREADY PATCHED: {path}")
        continue

    updated, count = method_pattern.subn(
        new_query_method.rstrip(),
        text,
        count=1,
    )

    if count != 1:
        print(f"Could not replace dbTable::query() in {path}")

        for number, line in enumerate(text.splitlines(), start=1):
            if re.search(r'\bfunction\s+query\s*\(', line):
                print(f"{number}: {line}")

        raise SystemExit(1)

    backup = path.with_name(
        path.name + ".before-php82-query-dispatch"
    )

    if not backup.exists():
        backup.write_text(text)

    path.write_text(updated)
    print(f"UPDATED: {path}")
PY

section "Updated query dispatch"

grep -n -A175 -B8 \
    'PHP 8 compatibility: distinguish result queries' \
    "$SOURCE"

section "PHP 8.2 lint"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/classes/core/dbtable_class_inc.php

section "Verify MDB2 exec method"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "MDB2.php";

        echo "MDB2_Driver_Common::exec exists: ",
            method_exists("MDB2_Driver_Common", "exec")
                ? "yes"
                : "no",
            PHP_EOL;

        if (!method_exists("MDB2_Driver_Common", "exec")) {
            exit(1);
        }
    '

section "Database state before request"

docker compose \
    -f "$COMPOSE" \
    exec -T db \
    mysql -uroot -proot -N -e '
        SELECT COUNT(*)
        FROM chisimba.tbl_loggedinusers;
    ' \
    || true

section "Request Chisimba"

curl \
    --silent \
    --show-error \
    --location \
    --max-time 45 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

section "Database state after request"

docker compose \
    -f "$COMPOSE" \
    exec -T db \
    mysql -uroot -proot -N -e '
        SELECT COUNT(*)
        FROM chisimba.tbl_loggedinusers;
    ' \
    || true

section "Recent web log"

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=140 web

section "Database dispatch patch complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
