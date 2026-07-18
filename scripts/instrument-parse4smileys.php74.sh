#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
TARGET="$ROOT/framework/app/core_modules/filters/classes/parse4smileys_class_inc.php"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${TARGET}.before-smiley-pcre-trace-${STAMP}"

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: File not found:"
    echo "  $TARGET"
    exit 1
fi

if grep -q "BEGIN PARSE4SMILEYS PHP74 TRACE" "$TARGET"; then
    echo "parse4smileys tracing is already installed."
    echo "No changes made."
    exit 0
fi

cp -a "$TARGET" "$BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = r'''        return preg_replace_callback(
            $regex,
            function ($matches) {
                return $this->getSmiley($matches[1]);
            },
            $str
        );'''

new = r'''        // BEGIN PARSE4SMILEYS PHP74 TRACE
        $result = preg_replace_callback(
            $regex,
            function ($matches) {
                return $this->getSmiley($matches[1]);
            },
            $str
        );

        $errorCode = preg_last_error();

        if (function_exists('preg_last_error_msg')) {
            $errorMessage = preg_last_error_msg();
        } else {
            $errorMessage = 'preg_last_error_msg() unavailable';
        }

        file_put_contents(
            '/var/www/html/ch/usrfiles/parse4smileys-trace.log',
            '[PARSE4SMILEYS TRACE]'
            . ' input_type=' . gettype($str)
            . ' input_length=' . (is_string($str) ? strlen($str) : -1)
            . ' result_type=' . gettype($result)
            . ' result_length=' . (is_string($result) ? strlen($result) : -1)
            . ' preg_error=' . $errorCode
            . ' preg_message=' . $errorMessage
            . PHP_EOL,
            FILE_APPEND | LOCK_EX
        );

        return $result;
        // END PARSE4SMILEYS PHP74 TRACE'''

if old not in text:
    raise SystemExit(
        "ERROR: Expected preg_replace_callback() block was not found."
    )

path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

echo
echo "Checking PHP syntax..."
php -l "$TARGET"

echo
echo "Instrumentation applied."
echo
echo "Source:"
echo "  $TARGET"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Installed marker:"
grep -n -A35 -B3 \
    "BEGIN PARSE4SMILEYS PHP74 TRACE" \
    "$TARGET"
