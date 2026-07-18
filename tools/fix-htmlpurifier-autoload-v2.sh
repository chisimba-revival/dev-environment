#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
LOG="$ROOT/killme.txt"

exec >"$LOG" 2>&1

python3 - <<'PY'
from pathlib import Path
import re

files = [
    Path("/run/media/derek/main/chisimba-revival/framework/app/lib/HTMLPurifier.autoload.php"),
    Path("/run/media/derek/main/chisimba-revival/dev-environment/runtime/php82-ch/lib/HTMLPurifier.autoload.php"),
]

for path in files:
    text = path.read_text()

    # Remove our added registration block
    text = re.sub(
        r"\n+if\s*\(\s*function_exists\('spl_autoload_register'\).*?spl_autoload_register\('HTMLPurifier_autoload'\);\s*\}\s*$",
        "",
        text,
        flags=re.S,
    )

    # Remove the obsolete PHP5 fallback entirely
    text = re.sub(
        r"elseif\s*\(!function_exists\('__autoload'\)\)\s*\{.*?\n\}",
        "",
        text,
        flags=re.S,
    )

    path.write_text(text)
    print("UPDATED", path)
PY

echo
echo "PHP syntax check"

php -l \
/run/media/derek/main/chisimba-revival/framework/app/lib/HTMLPurifier.autoload.php

docker compose \
-f /run/media/derek/main/chisimba-revival/dev-environment/compose/php82.yml \
exec -T web \
php -l /var/www/html/ch/lib/HTMLPurifier.autoload.php
