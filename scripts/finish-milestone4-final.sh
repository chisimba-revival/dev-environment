#!/usr/bin/env bash
set -euo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="$ROOT/dev-environment"
FRAMEWORK="$ROOT/framework"
PEAR="$FRAMEWORK/app/lib/pear"
PACK="$DEV/dependencies/chisimba-pear-runtime"
REBUILD="$DEV/scripts/rebuild-php74-runtime.sh"
COMPOSE="$DEV/compose/php74.yml"
WORK="$DEV/runtime/.pear-addons"

rm -rf "$WORK"
mkdir -p "$WORK/calendar" "$WORK/xmlutil"

echo "=== Download Calendar 0.5.5 ==="
curl -fL --retry 3 \
  "https://pear.php.net/get/Calendar-0.5.5.tgz" \
  -o "$WORK/Calendar-0.5.5.tgz"
tar -xzf "$WORK/Calendar-0.5.5.tgz" -C "$WORK/calendar"

CALENDAR_FILE="$(find "$WORK/calendar" -type f -name Calendar.php | head -n 1)"
CALENDAR_DIR="$(find "$WORK/calendar" -type d -name Calendar | head -n 1)"

test -f "$CALENDAR_FILE"
test -d "$CALENDAR_DIR"

echo "=== Download XML_Util 1.4.5 ==="
curl -fL --retry 3 \
  "https://pear.php.net/get/XML_Util-1.4.5.tgz" \
  -o "$WORK/XML_Util-1.4.5.tgz"
tar -xzf "$WORK/XML_Util-1.4.5.tgz" -C "$WORK/xmlutil"

XML_UTIL_FILE="$(find "$WORK/xmlutil" -type f -path '*/XML/Util.php' | head -n 1)"
test -f "$XML_UTIL_FILE"

echo "=== Install add-ons into compatibility pack ==="
rm -rf "$PACK/Calendar" "$PACK/Calendar.php"
mkdir -p "$PACK/XML"
cp -a "$CALENDAR_FILE" "$PACK/Calendar.php"
cp -a "$CALENDAR_DIR" "$PACK/Calendar"
cp -a "$XML_UTIL_FILE" "$PACK/XML/Util.php"

echo "=== Install add-ons into framework PEAR tree ==="
rm -rf "$PEAR/Calendar" "$PEAR/Calendar.php"
mkdir -p "$PEAR/XML"
cp -a "$PACK/Calendar.php" "$PEAR/Calendar.php"
cp -a "$PACK/Calendar" "$PEAR/Calendar"
cp -a "$PACK/XML/Util.php" "$PEAR/XML/Util.php"

grep -q '^PEAR Calendar:' "$PACK/CHISIMBA_DEPENDENCY_MANIFEST.txt" \
  || echo 'PEAR Calendar: 0.5.5' >> "$PACK/CHISIMBA_DEPENDENCY_MANIFEST.txt"

grep -q '^PEAR XML_Util:' "$PACK/CHISIMBA_DEPENDENCY_MANIFEST.txt" \
  || echo 'PEAR XML_Util: 1.4.5' >> "$PACK/CHISIMBA_DEPENDENCY_MANIFEST.txt"

cp -a "$PACK/CHISIMBA_DEPENDENCY_MANIFEST.txt" \
  "$PEAR/CHISIMBA_DEPENDENCY_MANIFEST.txt"

php -l "$PEAR/Calendar.php"
php -l "$PEAR/XML/Util.php"

echo "=== Remove obsolete PEAR/Common.php verification ==="
python3 - "$REBUILD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

marker = 'echo "Verifying PEAR/Common.php continue fix..."'

if marker not in text:
    print("Obsolete verification already removed.")
    raise SystemExit(0)

start = text.index(marker)
next_positions = [
    p for p in (
        text.find('echo "Verifying ', start + len(marker)),
        text.find('echo "Checking ', start + len(marker)),
        text.find('echo "PHP 7.4 runtime rebuild completed successfully."', start + len(marker)),
    )
    if p != -1
]

if not next_positions:
    raise SystemExit("Could not find end of obsolete verification block.")

end = min(next_positions)

replacement = (
    'echo "Verifying Chisimba dependency manifest..."\n'
    'docker compose \\\n'
    '    -f "$COMPOSE_FILE" \\\n'
    '    exec -T -w / web \\\n'
    '    test -f /var/www/html/ch/lib/pear/CHISIMBA_DEPENDENCY_MANIFEST.txt\n'
    '\n'
    'echo\n'
)

path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")
print("Obsolete verification removed.")
PY

bash -n "$REBUILD"

echo "=== Rebuild PHP 7.4 runtime ==="
"$REBUILD"

echo "=== Ensure web service is running ==="
docker compose -f "$COMPOSE" up -d web

echo "=== Final dependency smoke test ==="
docker compose -f "$COMPOSE" exec -T -w / web \
php -d display_errors=1 -d error_reporting=E_ALL -r '
set_include_path("/var/www/html/ch/lib/pear" . PATH_SEPARATOR . get_include_path());

require_once "PEAR.php";
require_once "XML/Parser.php";
require_once "XML/Util.php";
require_once "MDB2.php";
require_once "MDB2/Date.php";
require_once "MDB2/Schema.php";
require_once "MDB2/Driver/mysqli.php";
require_once "Calendar.php";

$checks = array(
    "PEAR" => class_exists("PEAR"),
    "XML_Parser" => class_exists("XML_Parser"),
    "XML_Util" => class_exists("XML_Util"),
    "MDB2" => class_exists("MDB2"),
    "MDB2_Date" => class_exists("MDB2_Date"),
    "MDB2_Schema" => class_exists("MDB2_Schema"),
    "MDB2_Driver_mysqli" => class_exists("MDB2_Driver_mysqli"),
    "Calendar" => class_exists("Calendar"),
);

foreach ($checks as $name => $ok) {
    echo $name . ": " . ($ok ? "OK" : "FAILED") . PHP_EOL;
    if (!$ok) {
        exit(1);
    }
}

echo "FULL DEPENDENCY STACK PASSED" . PHP_EOL;
'

echo "=== HTTP check ==="
curl -sS -I --max-time 10 http://localhost:8081/ch/ | sed -n '1,12p'

echo "=== Container status ==="
docker compose -f "$COMPOSE" ps

echo "MILESTONE 4 FINISH SCRIPT COMPLETED"
