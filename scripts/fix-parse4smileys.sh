#!/usr/bin/env bash
set -euo pipefail

ROOT="/run/media/derek/main/chisimba-revival"

FILE="$ROOT/framework/app/core_modules/filters/classes/parse4smileys_class_inc.php"

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${FILE}.${STAMP}.bak"

cp -a "$FILE" "$BACKUP"

python3 <<'PY'
from pathlib import Path

path = Path("framework/app/core_modules/filters/classes/parse4smileys_class_inc.php")

text = path.read_text()

old = r"""        return preg_replace($regex, "\$this->getSmiley('\\1')", $str);"""

new = r"""        return preg_replace_callback(
            $regex,
            function ($matches) {
                return $this->getSmiley($matches[1]);
            },
            $str
        );"""

if old not in text:
    raise SystemExit("Target text not found.")

text = text.replace(old, new, 1)

text = text.replace("/e';", "';")

path.write_text(text)
PY

php -l "$FILE"

echo
echo "parse4smileys converted successfully."
echo "Backup:"
echo "  $BACKUP"
