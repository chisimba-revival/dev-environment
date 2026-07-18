#!/usr/bin/env bash
set -euo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
TARGET="$ROOT/framework/app/core_modules/utilities/classes/washout_class_inc.php"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${TARGET}.before-washout-trace-${STAMP}"

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: File not found:"
    echo "  $TARGET"
    exit 1
fi

if grep -q 'BEGIN WASHOUT PHP74 TRACE' "$TARGET"; then
    echo "Washout tracing is already installed."
    exit 0
fi

cp -a "$TARGET" "$BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

function_start = """    public function parseText($txt, $bbcode = TRUE, $excluded=NULL)
    {

"""

trace_setup = """    public function parseText($txt, $bbcode = TRUE, $excluded=NULL)
    {
        // BEGIN WASHOUT PHP74 TRACE
        $washoutTrace = function ($stage, $value) {
            $type = gettype($value);
            $length = is_string($value) ? strlen($value) : -1;
            $sample = is_string($value)
                ? substr(preg_replace('/\\\\s+/', ' ', $value), 0, 120)
                : '';

            error_log(
                '[WASHOUT TRACE] stage=' . $stage
                . ' type=' . $type
                . ' length=' . $length
                . ' sample=' . $sample
            );

            return $value;
        };

        $washoutTrace('input', $txt);
        // END WASHOUT PHP74 TRACE

"""

if function_start not in text:
    raise SystemExit("ERROR: Could not find parseText() opening.")

text = text.replace(function_start, trace_setup, 1)

replacements = [
    (
        """        $txt = preg_replace_callback(
            '/\\\\[(\\\\w+)(\\\\W([^\\\\]\\\\[]*?)|)\\\\](?s:.*?)(\\\\[\\\\/\\\\1\\\\])/Uim',
            function ($matches) {
                return $this->getHTML($matches[0], $matches[1]);
            },
            $txt
        );
""",
        """        $txt = preg_replace_callback(
            '/\\\\[(\\\\w+)(\\\\W([^\\\\]\\\\[]*?)|)\\\\](?s:.*?)(\\\\[\\\\/\\\\1\\\\])/Uim',
            function ($matches) {
                return $this->getHTML($matches[0], $matches[1]);
            },
            $txt
        );
        $washoutTrace('after paired filter regex', $txt);
"""
    ),
    (
        """        $txt = preg_replace_callback(
            '/\\\\[(\\\\w+)(\\\\W([^\\\\]\\\\[]*?)|)\\\\]/i',
            function ($matches) {
                return $this->getHTML($matches[0], $matches[1]);
            },
            $txt
        );
""",
        """        $txt = preg_replace_callback(
            '/\\\\[(\\\\w+)(\\\\W([^\\\\]\\\\[]*?)|)\\\\]/i',
            function ($matches) {
                return $this->getHTML($matches[0], $matches[1]);
            },
            $txt
        );
        $washoutTrace('after single filter regex', $txt);
"""
    ),
    (
        """        $class =  $this->getObject('parse4smileys', 'filters');
        $txt = $class->parse($txt);
""",
        """        $class =  $this->getObject('parse4smileys', 'filters');
        $txt = $class->parse($txt);
        $washoutTrace('after parse4smileys', $txt);
"""
    ),
    (
        """        $class =  $this->getObject('parse4chiki', 'filters');
        $txt = $class->parse($txt);
""",
        """        $class =  $this->getObject('parse4chiki', 'filters');
        $txt = $class->parse($txt);
        $washoutTrace('after parse4chiki', $txt);
"""
    ),
    (
        """        $class =  $this->getObject('parse4format', 'filters');
        $txt = $class->parse($txt);
""",
        """        $class =  $this->getObject('parse4format', 'filters');
        $txt = $class->parse($txt);
        $washoutTrace('after parse4format', $txt);
"""
    ),
    (
        """        $class =  $this->getObject('parse4kngtext', 'filters');
        $txt = $class->parse($txt);
""",
        """        $class =  $this->getObject('parse4kngtext', 'filters');
        $txt = $class->parse($txt);
        $washoutTrace('after parse4kngtext', $txt);
"""
    ),
    (
        """        $class =  $this->getObject('parse4wikipediawords', 'filters');
        $txt = $class->parse($txt);
""",
        """        $class =  $this->getObject('parse4wikipediawords', 'filters');
        $txt = $class->parse($txt);
        $washoutTrace('after parse4wikipediawords', $txt);
"""
    ),
    (
        """        $class =  $this->getObject('parse4blocks', 'filters');
        $txt = $class->parse($txt);
""",
        """        $class =  $this->getObject('parse4blocks', 'filters');
        $txt = $class->parse($txt);
        $washoutTrace('after parse4blocks', $txt);
"""
    ),
    (
        """        $txt = $this->bbcode->parse4bbcode($txt);
        return $txt;
""",
        """        $txt = $this->bbcode->parse4bbcode($txt);
        $washoutTrace('after bbcode', $txt);
        return $txt;
"""
    ),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(
            "ERROR: Expected washout code block was not found:\\n" + old
        )
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
PY

echo
echo "Checking PHP syntax..."
php -l "$TARGET"

echo
echo "Instrumentation applied."
echo "Source:"
echo "  $TARGET"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Trace checkpoints:"
grep -n "washoutTrace" "$TARGET"
