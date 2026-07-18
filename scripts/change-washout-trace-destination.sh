#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
TARGET="$ROOT/framework/app/core_modules/utilities/classes/washout_class_inc.php"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${TARGET}.before-usrfiles-trace-${STAMP}"

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: Washout source file not found:"
    echo "  $TARGET"
    exit 1
fi

if grep -q "usrfiles/washout-trace.log" "$TARGET"; then
    echo "Washout already writes its trace to usrfiles/washout-trace.log."
    echo "No changes made."
    exit 0
fi

if ! grep -q "BEGIN WASHOUT PHP74 TRACE" "$TARGET"; then
    echo "ERROR: Temporary Washout instrumentation was not found."
    exit 1
fi

cp -a "$TARGET" "$BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """            error_log(
                '[WASHOUT TRACE] stage=' . $stage
                . ' type=' . $type
                . ' length=' . $length
                . ' sample=' . $sample
            );
"""

new = """            file_put_contents(
                '/var/www/html/ch/usrfiles/washout-trace.log',
                '[WASHOUT TRACE] stage=' . $stage
                . ' type=' . $type
                . ' length=' . $length
                . ' sample=' . $sample
                . PHP_EOL,
                FILE_APPEND | LOCK_EX
            );
"""

if old not in text:
    raise SystemExit(
        "ERROR: The expected error_log() tracing block was not found."
    )

updated = text.replace(old, new, 1)
path.write_text(updated, encoding="utf-8")
PY

echo
echo "Checking PHP syntax..."
php -l "$TARGET"

echo
echo "Trace destination updated successfully."
echo
echo "Source:"
echo "  $TARGET"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Installed trace destination:"
grep -n -A10 -B3 \
    "usrfiles/washout-trace.log" \
    "$TARGET"
