#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
LOG="${ROOT}/killme.txt"

SOURCE="${ROOT}/framework/app/core_modules/config/classes/altconfig_class_inc.php"
RUNTIME="${ROOT}/dev-environment/runtime/php82-ch/core_modules/config/classes/altconfig_class_inc.php"
CONFIG="${ROOT}/dev-environment/runtime/php82-ch/config/config.xml"
COMPOSE="${ROOT}/dev-environment/compose/php82.yml"

exec >"${LOG}" 2>&1

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

echo "============================================================"
echo "PHP 8.2: Preserve config.xml document root"
echo "============================================================"

python3 - "${SOURCE}" "${RUNTIME}" "${CONFIG}" <<'PY'
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

source_files = [Path(sys.argv[1]), Path(sys.argv[2])]
live_config = Path(sys.argv[3])

marker = "PHP 8 compatibility: normalize legacy PEAR XML output"

helper = r'''
    /**
     * PHP 8 compatibility: normalize legacy PEAR XML output.
     *
     * The legacy PEAR Config writer emits adjacent top-level elements.
     * Modern XML parsers require one document root.
     */
    private function _writeConfigAndNormalize()
    {
        $arguments = func_get_args();

        $result = call_user_func_array(
            array($this->_objPearConfig, 'writeConfig'),
            $arguments
        );

        $configFile = $this->_path . 'config.xml';

        if (
            isset($arguments[0])
            && is_string($arguments[0])
            && basename($arguments[0]) !== 'config.xml'
        ) {
            return $result;
        }

        $this->_normalizeConfigXml($configFile);

        return $result;
    }

    /**
     * Ensure a PEAR-generated configuration file has one XML root element.
     */
    private function _normalizeConfigXml($configFile)
    {
        if (!is_file($configFile)) {
            return false;
        }

        $configXml = @file_get_contents($configFile);

        if ($configXml === false || trim($configXml) === '') {
            return false;
        }

        libxml_use_internal_errors(true);
        $validXml = simplexml_load_string($configXml);
        libxml_clear_errors();

        if ($validXml !== false) {
            return true;
        }

        $configBody = preg_replace(
            '/^\s*<\?xml[^>]*\?>\s*/i',
            '',
            $configXml
        );

        $configXml = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n"
            . "<Settings>\n"
            . trim($configBody)
            . "\n</Settings>\n";

        return @file_put_contents($configFile, $configXml) !== false;
    }

'''

for path in source_files:
    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    text = path.read_text()

    if marker not in text:
        # Route all PEAR Config writes in altconfig through one normalizer.
        updated, replacements = re.subn(
            r'\$this->_objPearConfig->writeConfig\s*\(',
            '$this->_writeConfigAndNormalize(',
            text,
        )

        if replacements == 0:
            raise SystemExit(
                f"No PEAR Config writeConfig() calls found in {path}"
            )

        insertion_point = re.search(
            r'^[ \t]*(?:public[ \t]+)?function[ \t]+writeConfig\s*\(',
            updated,
            re.MULTILINE | re.IGNORECASE,
        )

        if insertion_point is None:
            raise SystemExit(
                f"Could not find altconfig::writeConfig() in {path}"
            )

        updated = (
            updated[:insertion_point.start()]
            + helper
            + updated[insertion_point.start():]
        )

        backup = path.with_name(
            path.name + ".before-php82-xml-normalizer"
        )

        if not backup.exists():
            backup.write_text(text)

        path.write_text(updated)

        print(
            f"UPDATED ({replacements} write calls): {path}"
        )
    else:
        print(f"ALREADY PATCHED: {path}")


def repair_config(path: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"Missing live config: {path}")

    text = path.read_text()

    try:
        ET.fromstring(text)
        print(f"CONFIG ALREADY VALID: {path}")
        return
    except ET.ParseError:
        pass

    body = re.sub(
        r'^\s*<\?xml[^>]*\?>\s*',
        '',
        text,
        count=1,
        flags=re.IGNORECASE,
    )

    repaired = (
        '<?xml version="1.0" encoding="ISO-8859-1"?>\n'
        '<Settings>\n'
        + body.strip()
        + '\n</Settings>\n'
    )

    ET.fromstring(repaired)

    backup = path.with_name(
        path.name + ".before-php82-root-repair"
    )

    if not backup.exists():
        backup.write_text(text)

    path.write_text(repaired)
    print(f"REPAIRED LIVE CONFIG: {path}")


repair_config(live_config)
PY

echo
echo "===== CENTRAL NORMALIZER ====="

grep -n -A85 -B5 \
    'PHP 8 compatibility: normalize legacy PEAR XML output' \
    "${SOURCE}"

echo
echo "===== REMAINING DIRECT PEAR WRITES ====="

if grep -n \
    '\$this->_objPearConfig->writeConfig' \
    "${SOURCE}" "${RUNTIME}"
then
    fail "Direct PEAR Config writes remain outside the helper."
fi

echo "All altconfig writes now pass through the normalizer."

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -l \
    /var/www/html/ch/core_modules/config/classes/altconfig_class_inc.php

echo
echo "===== LIVE CONFIG.XML ====="

nl -ba "${CONFIG}" | sed -n '1,55p'

echo
echo "===== XML VALIDATION ====="

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -r '
        libxml_use_internal_errors(true);

        $file = "/var/www/html/ch/config/config.xml";
        $xml = simplexml_load_file($file);

        if ($xml === false) {
            echo "INVALID", PHP_EOL;

            foreach (libxml_get_errors() as $error) {
                echo trim($error->message),
                    " at line ",
                    $error->line,
                    ":",
                    $error->column,
                    PHP_EOL;
            }

            exit(1);
        }

        echo "VALID", PHP_EOL;
        echo "Root: ", $xml->getName(), PHP_EOL;
        echo "Children: ", count($xml->children()), PHP_EOL;
    '

echo
echo "===== REQUEST CHISIMBA ====="

curl \
    --silent \
    --show-error \
    --location \
    --max-time 30 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

echo
echo "===== RECENT WEB LOG ====="

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=120 web

echo
echo "============================================================"
echo "Central configuration writer patched."
echo "Reload: http://localhost:8082/ch/"
echo "============================================================"
