#!/usr/bin/env bash

set -Eeuo pipefail

BASE_URL="${CHISIMBA_SMOKE_BASE_URL:-https://chisimba.test:8443}"
USERNAME="${CHISIMBA_SMOKE_USERNAME:-}"
PASSWORD="${CHISIMBA_SMOKE_PASSWORD:-}"
ROUTES="${CHISIMBA_SMOKE_ROUTES:-module=toolbar module=groupadmin module=useradmin}"
CURL_TLS=()

if [[ "${CHISIMBA_SMOKE_INSECURE_TLS:-0}" == "1" ]]; then
    CURL_TLS=(-k)
fi

if [[ -z "${USERNAME}" || -z "${PASSWORD}" ]]; then
    echo "ERROR: Set CHISIMBA_SMOKE_USERNAME and CHISIMBA_SMOKE_PASSWORD." >&2
    exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
cookie_jar="${work_dir}/cookies.txt"
response="${work_dir}/response.html"
headers="${work_dir}/headers.txt"
transfer="${work_dir}/transfer.txt"
failures=0

pass()
{
    echo "PASS: $*"
}

fail()
{
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

request()
{
    local method="$1"
    local url="$2"
    shift 2

    curl "${CURL_TLS[@]}" --silent --show-error \
        --location --max-redirs 8 \
        --cookie "${cookie_jar}" --cookie-jar "${cookie_jar}" \
        --dump-header "${headers}" --output "${response}" \
        --write-out '%{http_code}\t%{url_effective}\n' \
        > "${transfer}" \
        --request "${method}" "$@" "${url}"
}

status_code()
{
    awk 'toupper($1) ~ /^HTTP\// { code=$2 } END { print code }' "${headers}"
}

effective_url()
{
    cut -f2- "${transfer}"
}

html_value()
{
    local name="$1"
    CHISIMBA_INPUT_NAME="${name}" perl -0777 -ne '
        my $name = $ENV{"CHISIMBA_INPUT_NAME"};
        if (/<input\b(?=[^>]*\bname=["\x27]\Q$name\E["\x27])(?=[^>]*\bvalue=["\x27]([^"\x27]*)["\x27])[^>]*>/is) {
            print $1;
        }
    ' "${response}"
}

contains_input()
{
    local name="$1"
    grep -Eqi "<input[^>]+name=[\"']${name}[\"']" "${response}"
}

login_url="${BASE_URL%/}/index.php?module=security&action=showlogin"
security_url="${BASE_URL%/}/index.php?module=security"

request GET "${login_url}"
if [[ "$(status_code)" =~ ^2 ]]; then
    pass "native login page is reachable"
else
    fail "native login page returned HTTP $(status_code)"
fi

if contains_input native_auth_begin; then
    pass "login form exposes the canonical CSRF field"
else
    fail "login form lacks native_auth_begin"
fi

login_token="$(html_value native_auth_begin)"
if [[ -n "${login_token}" ]]; then
    pass "login CSRF token is non-empty"
else
    fail "login CSRF token could not be extracted"
fi

request POST "${security_url}" \
    --data-urlencode "action=login" \
    --data-urlencode "native_auth_begin=${login_token}" \
    --data-urlencode "username=${USERNAME}" \
    --data-urlencode "password=${PASSWORD}__chisimba_smoke_wrong__"
if contains_input native_auth_begin && ! contains_input native_auth_logout; then
    pass "incorrect password does not create an authenticated session"
else
    fail "incorrect-password request did not return the anonymous login boundary"
fi

# The failed-login transaction consumes its single-use CSRF token. Fetch a
# fresh login form before starting the independent valid-login transaction.
request GET "${login_url}"
if [[ "$(status_code)" =~ ^2 ]] && contains_input native_auth_begin; then
    pass "fresh login form is available after the failed-login probe"
else
    fail "fresh login form could not be obtained after the failed-login probe"
fi

login_token="$(html_value native_auth_begin)"
if [[ -n "${login_token}" ]]; then
    pass "fresh valid-login CSRF token is non-empty"
else
    fail "fresh valid-login CSRF token could not be extracted"
fi

request POST "${security_url}" \
    --data-urlencode "action=login" \
    --data-urlencode "native_auth_begin=${login_token}" \
    --data-urlencode "username=${USERNAME}" \
    --data-urlencode "password=${PASSWORD}"

if [[ "$(status_code)" =~ ^[23] ]] && ! contains_input native_auth_begin; then
    pass "valid credentials leave the anonymous login boundary"
else
    fail "valid credentials did not leave the anonymous login boundary (MFA may be enabled)"
    echo "EVIDENCE: valid-login response HTTP $(status_code); effective URL: $(effective_url)" >&2
    if contains_input native_auth_begin; then
        echo "EVIDENCE: valid-login response returned the anonymous login form" >&2
    fi
fi

request GET "${security_url}?action=authenticated"
if [[ "$(status_code)" =~ ^[23] ]] && ! contains_input native_auth_begin; then
    pass "authenticated landing route does not return the anonymous login boundary"
else
    fail "authenticated landing route returned the anonymous login boundary"
fi

for route in ${ROUTES}; do
    request GET "${BASE_URL%/}/index.php?${route}"
    if [[ "$(status_code)" =~ ^[23] ]] && ! contains_input native_auth_begin; then
        pass "authenticated route is reachable: ${route}"
    else
        fail "authenticated route failed or returned login: ${route}"
    fi
done

request GET "${security_url}?action=logout"
if [[ "$(status_code)" =~ ^[23] ]]; then
    pass "GET logout request is handled without a server error"
else
    fail "GET logout request failed with HTTP $(status_code)"
fi

# Prove GET logout did not mutate authentication state. The logout action
# itself is not required to render the native logout form.
request GET "${BASE_URL%/}/index.php?module=toolbar"
if [[ "$(status_code)" =~ ^[23] ]] && ! contains_input native_auth_begin; then
    pass "GET logout is rejected without destroying the session"
else
    fail "GET logout destroyed the authenticated session"
fi

# Fetch a page that is proven to render the native logout form. The canonical
# form carries both the action discriminator and its single-use CSRF token.
request GET "${login_url}"
logout_action="$(html_value action)"
logout_token="$(html_value native_auth_logout)"
if [[ "${logout_action}" == "logout" && -n "${logout_token}" ]]; then
    pass "native logout form exposes action=logout and a non-empty CSRF token"
else
    fail "native logout form or CSRF token could not be extracted"
fi

request POST "${security_url}" \
    --data-urlencode "action=${logout_action:-logout}" \
    --data-urlencode "native_auth_logout=${logout_token}"
if contains_input native_auth_begin && ! contains_input native_auth_logout; then
    pass "POST/CSRF logout returns to the anonymous login boundary"
else
    fail "POST/CSRF logout did not destroy the authenticated session"
fi

request GET "${security_url}?action=authenticated"
if contains_input native_auth_begin; then
    pass "logged-out session cannot reopen the authenticated landing"
else
    fail "authenticated state survived logout"
fi

if (( failures > 0 )); then
    echo "RESULT: FAIL (${failures} failure(s))" >&2
    exit 1
fi

echo "RESULT: PASS"
