#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"
PEAR="${ROOT}/framework/app/lib/pear"
RUNTIME="${DEV}/runtime/php82-ch"
REBUILD="${DEV}/scripts/rebuild-runtime.sh"
LOG="${ROOT}/killme.txt"

exec > >(tee "${LOG}") 2>&1

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

echo "============================================================"
echo "Ensure PEAR Config PHP 8 constructors"
echo "============================================================"

python3 - <<'PY'
from pathlib import Path

files = [
    (
        Path("/run/media/derek/main/chisimba-revival/framework/app/lib/pear/Config.php"),
        "function Config()",
        """    public function __construct()
    {
        $this->Config();
    }

""",
    ),
    (
        Path("/run/media/derek/main/chisimba-revival/framework/app/lib/pear/Config/Container.php"),
        "function Config_Container($type = 'section', $name = '', $content = '', $attributes = null)",
        """    public function __construct($type = 'section', $name = '', $content = '', $attributes = null)
    {
        $this->Config_Container($type, $name, $content, $attributes);
    }

""",
    ),
    (
        Path("/run/media/derek/main/chisimba-revival/framework/app/lib/pear/Config/Container/PHPArray.php"),
        "function Config_Container_PHPArray($options = array())",
        """    public function __construct($options = array())
    {
        $this->Config_Container_PHPArray($options);
    }

""",
    ),
]

for path, legacy_signature, wrapper in files:
    text = path.read_text()

    if "function __construct" in text:
        print(f"ALREADY PRESENT: {path}")
        continue

    position = text.find(legacy_signature)

    if position == -1:
        raise SystemExit(
            f"Could not find legacy constructor in {path}: "
            f"{legacy_signature}"
        )

    line_start = text.rfind("\n", 0, position) + 1

    backup = path.with_name(path.name + ".before-php82-config-constructor")

    if not backup.exists():
        backup.write_text(text)

    updated = text[:line_start] + wrapper + text[line_start:]
    path.write_text(updated)

    print(f"ADDED: {path}")

PY

echo
echo "===== SOURCE CONSTRUCTORS ====="

for FILE in \
    "${PEAR}/Config.php" \
    "${PEAR}/Config/Container.php" \
    "${PEAR}/Config/Container/PHPArray.php"
do
    echo
    echo "FILE: ${FILE}"

    grep -n -A8 -B3 \
        'function[[:space:]]\+__construct' \
        "${FILE}" \
        || fail "No __construct() found in ${FILE}"

    php -l "${FILE}"
done

echo
echo "===== REBUILD FRESH PHP 8.2 INSTALL ====="

"${REBUILD}" php82 --fresh-db

echo
echo "===== RUNTIME CONSTRUCTORS ====="

for FILE in \
    "lib/pear/Config.php" \
    "lib/pear/Config/Container.php" \
    "lib/pear/Config/Container/PHPArray.php"
do
    echo
    echo "FILE: ${RUNTIME}/${FILE}"

    grep -n -A8 -B3 \
        'function[[:space:]]\+__construct' \
        "${RUNTIME}/${FILE}" \
        || fail "Runtime constructor missing in ${FILE}"
done

echo
echo "===== DIRECT CONSTRUCTOR TEST ====="

docker compose \
    -f "${DEV}/compose/php82.yml" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "Config.php";

        $config = new Config();

        echo "Config class: ", get_class($config), PHP_EOL;
        echo "Container type: ",
            is_object($config->container)
                ? get_class($config->container)
                : gettype($config->container),
            PHP_EOL;

        if (!is_object($config->container)) {
            exit(1);
        }

        $result = $config->parseConfig(
            array("test_key" => "test_value"),
            "phparray"
        );

        echo "parseConfig result: ",
            is_object($result) ? get_class($result) : gettype($result),
            PHP_EOL;
    '

echo
echo "============================================================"
echo "PEAR Config constructor chain is working."
echo "============================================================"
echo
echo "Open a NEW incognito window:"
echo "  http://localhost:8082/ch/"
echo
echo "Start again at installer screen 1."
