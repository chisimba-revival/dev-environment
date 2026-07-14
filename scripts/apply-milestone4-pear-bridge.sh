#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
FRAMEWORK_DIR="$WORKSPACE_DIR/framework"

VERSIONCHECK="$FRAMEWORK_DIR/app/installer/steps/versioncheck.inc"
PACKAGEFILE_V1="$FRAMEWORK_DIR/app/lib/pear/PEAR/PackageFile/v1.php"
GENERATOR_V1="$FRAMEWORK_DIR/app/lib/pear/PEAR/PackageFile/Generator/v1.php"

for file in "$VERSIONCHECK" "$PACKAGEFILE_V1" "$GENERATOR_V1"; do
    if [[ ! -f "$file" ]]; then
        echo "Required file is missing: $file" >&2
        exit 1
    fi
done

python3 - "$VERSIONCHECK" "$PACKAGEFILE_V1" "$GENERATOR_V1" <<'PY'
from pathlib import Path
import sys

versioncheck = Path(sys.argv[1])
packagefile_v1 = Path(sys.argv[2])
generator_v1 = Path(sys.argv[3])

def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)

    if count == 0:
        if new in text:
            print(f"Already applied: {label}")
            return
        raise SystemExit(
            f"Expected source block was not found for {label}: {path}"
        )

    if count != 1:
        raise SystemExit(
            f"Expected exactly one source block for {label}, found {count}: {path}"
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Applied: {label}")

old_mysqli_check = """            if ($allowed_db['MDB2_Driver_mysqli']==TRUE) {
               @include('MDB2_Driver_mysqli');
            \tif (!class_exists('MDB2_Driver_mysqli')) {
            \t\t$this->errors[] = '<span class="errors">Could not find PEAR::MDB2_Driver_mysqli </span>';

                \t$this->required_packages['MDB2_Driver_mysqli']['message'] =  '<img src="./extra/failed.png" border="0" alt="Failed" title="Failed"  />';

            \t}else{
            \t\t$this->required_packages['MDB2_Driver_mysqli']['message'] =  '<img src="./extra/ok.png" border="0" alt="OK" title="OK"  />';\t
            \t}
            }
"""

new_mysqli_check = """            if ($allowed_db['MDB2_Driver_mysqli']==TRUE) {
                @include_once 'MDB2/Driver/mysqli.php';

                if (!class_exists('MDB2_Driver_mysqli')) {
                    $this->errors[] = '<span class="errors">Could not find bundled PEAR::MDB2_Driver_mysqli </span>';

                    $this->required_packages['MDB2_Driver_mysqli']['message'] =  '<img src="./extra/failed.png" border="0" alt="Failed" title="Failed"  />';
                    $this->success = false;
                } else {
                    $this->required_packages['MDB2_Driver_mysqli']['available'] = true;
                    $this->required_packages['MDB2_Driver_mysqli']['message'] =  '<img src="./extra/ok.png" border="0" alt="OK" title="OK"  />';
                }
            }
"""

replace_once(
    versioncheck,
    old_mysqli_check,
    new_mysqli_check,
    "load bundled MDB2 mysqli driver"
)

old_registry_lookup = """            foreach ($this->required_packages as $package_name => $required_version) {

                $package_info = $pear_registry->packageInfo($package_name);

                if (empty($package_info)) {
"""

new_registry_lookup = """            foreach ($this->required_packages as $package_name => $required_version) {

                /*
                 * Chisimba ships its curated MDB2 mysqli driver with the
                 * application. The historical installer also expected a
                 * system PEAR registry entry, which is not required when the
                 * bundled driver is present and loadable.
                 */
                if (
                    $package_name == 'MDB2_Driver_mysqli'
                    && class_exists('MDB2_Driver_mysqli')
                ) {
                    $this->required_packages[$package_name]['available'] = true;
                    $this->required_packages[$package_name]['message'] =  '<img src="./extra/ok.png" border="0" alt="OK" title="OK"  />';
                    continue;
                }

                $package_info = $pear_registry->packageInfo($package_name);

                if (empty($package_info)) {
"""

replace_once(
    versioncheck,
    old_registry_lookup,
    new_registry_lookup,
    "accept bundled mysqli driver without registry metadata"
)

old_continue = """                case T_WHITESPACE :
                    continue;
"""
new_continue = """                case T_WHITESPACE :
                    continue 2;
"""
replace_once(
    packagefile_v1,
    old_continue,
    new_continue,
    "PackageFile/v1 continue 2"
)

old_min = """            if (count($min)) {
                // get the highest minimum
                $min = array_pop($a = array_flip($min));
            } else {
"""
new_min = """            if (count($min)) {
                // get the highest minimum
                $a = array_flip($min);
                $min = array_pop($a);
            } else {
"""
replace_once(
    generator_v1,
    old_min,
    new_min,
    "Generator/v1 highest minimum reference fix"
)

old_max = """            if (count($max)) {
                // get the lowest maximum
                $max = array_shift($a = array_flip($max));
            } else {
"""
new_max = """            if (count($max)) {
                // get the lowest maximum
                $a = array_flip($max);
                $max = array_shift($a);
            } else {
"""
replace_once(
    generator_v1,
    old_max,
    new_max,
    "Generator/v1 lowest maximum reference fix"
)
PY

echo
echo "Changed files:"
git -C "$FRAMEWORK_DIR" status --short -- \
    app/installer/steps/versioncheck.inc \
    app/lib/pear/PEAR/PackageFile/v1.php \
    app/lib/pear/PEAR/PackageFile/Generator/v1.php

echo
echo "Diff summary:"
git -C "$FRAMEWORK_DIR" diff --stat -- \
    app/installer/steps/versioncheck.inc \
    app/lib/pear/PEAR/PackageFile/v1.php \
    app/lib/pear/PEAR/PackageFile/Generator/v1.php

echo
echo "Milestone 4 PEAR bridge patch applied successfully."
