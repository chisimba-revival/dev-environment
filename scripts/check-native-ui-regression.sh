#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/run/media/derek/main/chisimba-revival"
UI="${ROOT}/modules/ui"
REPORT="${ROOT}/killme.txt"
fail(){ echo "FAIL: $*" | tee -a "${REPORT}"; exit 1; }

[[ -f "${UI}/classes/uiservice_class_inc.php" ]] || fail "uiservice missing"
[[ ! -f "${UI}/classes/ui_class_inc.php" ]] || fail "duplicate ui service returned"
[[ -f "${UI}/classes/messagebox_class_inc.php" ]] || fail "messagebox missing"
grep -q 'aria-label="Dismiss message"' "${UI}/classes/messagebox_class_inc.php" || fail "dismiss button lacks accessible name"
grep -q 'role="' "${UI}/classes/messagebox_class_inc.php" || fail "messagebox lacks semantic role"

if grep -RIn --exclude='*.before-*' -E 'Ext\.(onReady|Window|MessageBox|Msg|QuickTips)|ext-all(\.js|\.css)' "${UI}"; then
    fail "ExtJS reference detected in ui module"
fi

while IFS= read -r file; do
    php -l "${file}" >/dev/null || fail "PHP syntax failed: ${file}"
done < <(find "${UI}" -type f -name '*.php' ! -name '*.before-*' | sort)

echo "PASS: native UI regression gate" | tee -a "${REPORT}"
