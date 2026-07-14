#!/usr/bin/env bash
set -euo pipefail

CALENDAR_VERSION="0.5.5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

FRAMEWORK_DIR="$WORKSPACE_DIR/framework"
PEAR_ROOT="$FRAMEWORK_DIR/app/lib/pear"
PACK_ROOT="$DEV_ENV_DIR/dependencies/chisimba-pear-runtime"
REBUILD_SCRIPT="$DEV_ENV_DIR/scripts/rebuild-php74-runtime.sh"
COMPOSE_FILE="$DEV_ENV_DIR/compose/php74.yml"
DOWNLOAD_ROOT="$DEV_ENV_DIR/runtime/.calendar-download"

for path in     "$PEAR_ROOT"     "$PACK_ROOT"     "$REBUILD_SCRIPT"     "$COMPOSE_FILE"
do
    if [[ ! -e "$path" ]]; then
        echo "Required path is missing: $path" >&2
        exit 1
    fi
done

echo "============================================================"
echo "Finish Milestone 4 dependency integration"
echo "============================================================"
date
echo

rm -rf "$DOWNLOAD_ROOT"
mkdir -p "$DOWNLOAD_ROOT/extracted"

CALENDAR_ARCHIVE="$DOWNLOAD_ROOT/Calendar-${CALENDAR_VERSION}.tgz"

echo "Downloading PEAR Calendar ${CALENDAR_VERSION}..."
curl -fL     --retry 3     --connect-timeout 20     --max-time 180     "https://pear.php.net/get/Calendar-${CALENDAR_VERSION}.tgz"     -o "$CALENDAR_ARCHIVE"

echo
echo "Calendar archive checksum:"
sha256sum "$CALENDAR_ARCHIVE"

tar -xzf "$CALENDAR_ARCHIVE" -C "$DOWNLOAD_ROOT/extracted"

CALENDAR_SOURCE="$DOWNLOAD_ROOT/extracted/Calendar-${CALENDAR_VERSION}"

if [[ ! -d "$CALENDAR_SOURCE/Calendar" ]]; then
    echo "Downloaded Calendar package does not contain Calendar/." >&2
    exit 1
fi

if [[ ! -f "$CALENDAR_SOURCE/Calendar.php" ]]; then
    echo "Downloaded Calendar package does not contain Calendar.php." >&2
    exit 1
fi

echo
echo "Installing Calendar into canonical compatibility pack..."
rm -rf "$PACK_ROOT/Calendar" "$PACK_ROOT/Calendar.php"
cp -a "$CALENDAR_SOURCE/Calendar" "$PACK_ROOT/"
cp -a "$CALENDAR_SOURCE/Calendar.php" "$PACK_ROOT/"

echo
echo "Installing Calendar into framework PEAR tree..."
rm -rf "$PEAR_ROOT/Calendar" "$PEAR_ROOT/Calendar.php"
cp -a "$PACK_ROOT/Calendar" "$PEAR_ROOT/"
cp -a "$PACK_ROOT/Calendar.php" "$PEAR_ROOT/"

MANIFEST="$PACK_ROOT/CHISIMBA_DEPENDENCY_MANIFEST.txt"
if ! grep -q "^PEAR Calendar:" "$MANIFEST"; then
    printf '\nPEAR Calendar: %s\n' "$CALENDAR_VERSION" >> "$MANIFEST"
fi
cp -a "$MANIFEST" "$PEAR_ROOT/CHISIMBA_DEPENDENCY_MANIFEST.txt"

php -l "$PEAR_ROOT/Calendar.php"

echo
echo "Updating rebuild verification..."

python3 - "$REBUILD_SCRIPT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start_marker = 'echo "Verifying PEAR/Common.php continue fix..."'
replacement_marker = 'echo "Verifying Chisimba dependency manifest..."'

if replacement_marker in text:
    print("Capability-based rebuild verification is already installed.")
    raise SystemExit(0)

start = text.find(start_marker)
if start == -1:
    raise SystemExit(
        "Could not find obsolete PEAR/Common.php verification block."
    )

search_from = start + len(start_marker)
candidates = [
    text.find('echo "Verifying ', search_from),
    text.find('echo "Checking ', search_from),
    text.find('echo "PHP 7.4 runtime rebuild completed successfully."', search_from),
]
candidates = [pos for pos in candidates if pos != -1]

if not candidates:
    raise SystemExit(
        "Could not determine the end of the obsolete verification block."
    )

end = min(candidates)

new_block = '''echo "Verifying Chisimba dependency manifest..."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    test -f /var/www/html/ch/lib/pear/CHISIMBA_DEPENDENCY_MANIFEST.txt

echo
echo "Verifying PEAR/MDB2 capabilities..."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    php -d display_errors=1 -r '\''
        set_include_path(
            "/var/www/html/ch/lib/pear"
            . PATH_SEPARATOR
            . get_include_path()
        );

        require_once "PEAR.php";
        require_once "XML/Parser.php";
        require_once "MDB2.php";
        require_once "MDB2/Date.php";
        require_once "MDB2/Schema.php";
        require_once "MDB2/Driver/mysqli.php";
        require_once "Calendar.php";

        $checks = array(
            "PEAR" => class_exists("PEAR"),
            "XML_Parser" => class_exists("XML_Parser"),
            "MDB2" => class_exists("MDB2"),
            "MDB2_Date" => class_exists("MDB2_Date"),
            "MDB2_Schema" => class_exists("MDB2_Schema"),
            "MDB2_Driver_mysqli" => class_exists("MDB2_Driver_mysqli"),
            "Calendar" => class_exists("Calendar"),
        );

        foreach ($checks as $label => $passed) {
            if (!$passed) {
                fwrite(STDERR, $label . " capability check failed\\n");
                exit(1);
            }
        }

        echo "PEAR/MDB2 capability checks passed.\\n";
    '\''

echo
'''

path.write_text(text[:start] + new_block + text[end:], encoding="utf-8")
print("Replaced obsolete PEAR/Common.php assertion with capability checks.")
PY

bash -n "$REBUILD_SCRIPT"

echo
echo "Rebuilding PHP 7.4 runtime..."
"$REBUILD_SCRIPT"

echo
echo "Running full dependency smoke test..."

docker compose     -f "$COMPOSE_FILE"     exec -T -w / web     php -d display_errors=1 -d error_reporting=E_ALL -r '
        set_include_path(
            "/var/www/html/ch/lib/pear"
            . PATH_SEPARATOR
            . get_include_path()
        );

        require_once "PEAR.php";
        require_once "XML/Parser.php";
        require_once "MDB2.php";
        require_once "MDB2/Date.php";
        require_once "MDB2/Schema.php";
        require_once "MDB2/Driver/mysqli.php";
        require_once "Calendar.php";

        $checks = array(
            "PEAR" => class_exists("PEAR"),
            "XML_Parser" => class_exists("XML_Parser"),
            "MDB2" => class_exists("MDB2"),
            "MDB2_Date" => class_exists("MDB2_Date"),
            "MDB2_Schema" => class_exists("MDB2_Schema"),
            "MDB2_Driver_Common" => class_exists("MDB2_Driver_Common"),
            "MDB2_Driver_mysqli" => class_exists("MDB2_Driver_mysqli"),
            "Calendar" => class_exists("Calendar"),
        );

        foreach ($checks as $label => $passed) {
            echo $label . ": " . ($passed ? "OK" : "FAILED") . PHP_EOL;
            if (!$passed) {
                exit(1);
            }
        }

        $db = new MDB2_Driver_mysqli();
        echo "MDB2 mysqli object: "
            . (is_object($db) ? "OK" : "FAILED")
            . PHP_EOL;

        $schema = new MDB2_Schema();
        echo "MDB2 Schema object: "
            . (is_object($schema) ? "OK" : "FAILED")
            . PHP_EOL;

        echo "MDB2 Date timestamp: "
            . MDB2_Date::mdbNow()
            . PHP_EOL;

        $calendar = new Calendar(2026, 7, 13);
        echo "Calendar object: "
            . (is_object($calendar) ? "OK" : "FAILED")
            . PHP_EOL;

        echo "FULL DEPENDENCY STACK PASSED" . PHP_EOL;
    '

echo
echo "HTTP check:"
curl -sS -I --max-time 10 http://localhost:8081/ch/ | sed -n '1,12p'

echo
echo "Container status:"
docker compose -f "$COMPOSE_FILE" ps

echo
echo "Milestone 4 dependency integration completed."
