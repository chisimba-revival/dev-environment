#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
FILE="$WORKSPACE_DIR/framework/app/installer/steps/versioncheck.inc"

if [[ ! -f "$FILE" ]]; then
    echo "Missing file: $FILE" >&2
    exit 1
fi

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """                if (
                    $package_name == 'MDB2_Driver_mysqli'
                    && class_exists('MDB2_Driver_mysqli')
                ) {
                    $this->required_packages[$package_name]['available'] = true;
                    $this->required_packages[$package_name]['message'] =  '<img src="./extra/ok.png" border="0" alt="OK" title="OK"  />';
                    continue;
                }
"""

new = """                if ($package_name == 'MDB2_Driver_mysqli') {
                    @include_once 'MDB2/Driver/mysqli.php';

                    if (class_exists('MDB2_Driver_mysqli')) {
                        $this->required_packages[$package_name]['available'] = true;
                        $this->required_packages[$package_name]['message'] =  '<img src="./extra/ok.png" border="0" alt="OK" title="OK"  />';
                        continue;
                    }
                }
"""

if new in text:
    print("Already applied: registry branch loads bundled mysqli driver")
elif old in text:
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Applied: registry branch loads bundled mysqli driver")
else:
    raise SystemExit(
        "Expected installer bridge block was not found; no changes were made."
    )
PY

echo
echo "Relevant diff:"
git -C "$WORKSPACE_DIR/framework" diff -U8 -- \
    app/installer/steps/versioncheck.inc

echo
echo "Patch completed."
