#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
TARGETED="$ROOT/dev-environment/tools/php-moderniser/modernise-targeted-constructor.py"
SOURCE_ROOT="$ROOT/framework/app/lib/pear"
RUNTIME_ROOT="$ROOT/dev-environment/runtime/php82-ch/lib/pear"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

section "PHP 8.2 LiveUser dispatcher-chain repair"

[[ -f "$TARGETED" ]] ||
    fail "Missing targeted constructor moderniser: $TARGETED"

LIVEUSER_SOURCE="$SOURCE_ROOT/LiveUser.php"
LIVEUSER_RUNTIME="$RUNTIME_ROOT/LiveUser.php"

DISPATCHER_SOURCE="$SOURCE_ROOT/Event/Dispatcher.php"
DISPATCHER_RUNTIME="$RUNTIME_ROOT/Event/Dispatcher.php"

for FILE in \
    "$LIVEUSER_SOURCE" \
    "$LIVEUSER_RUNTIME" \
    "$DISPATCHER_SOURCE" \
    "$DISPATCHER_RUNTIME"
do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

section "Apply exact constructor wrappers"

python3 "$TARGETED" \
    --apply \
    "$LIVEUSER_SOURCE" \
    LiveUser

python3 "$TARGETED" \
    --apply \
    "$LIVEUSER_RUNTIME" \
    LiveUser

/*
 * Event_Dispatcher may also rely on its PHP 4 constructor. The targeted
 * moderniser is idempotent, so this is safe when already corrected.
 */
python3 "$TARGETED" \
    --apply \
    "$DISPATCHER_SOURCE" \
    Event_Dispatcher

python3 "$TARGETED" \
    --apply \
    "$DISPATCHER_RUNTIME" \
    Event_Dispatcher

section "Copy corrected files into the running container"

CID="$(
    docker compose \
        -f "$COMPOSE" \
        ps -q web
)"

[[ -n "$CID" ]] ||
    fail "PHP 8.2 web container is not running."

docker cp \
    "$LIVEUSER_RUNTIME" \
    "$CID:/var/www/html/ch/lib/pear/LiveUser.php"

docker cp \
    "$DISPATCHER_RUNTIME" \
    "$CID:/var/www/html/ch/lib/pear/Event/Dispatcher.php"

section "Inspect actual container declarations"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    grep -n -A18 -B6 \
    -E 'function[[:space:]]+(__construct|LiveUser)[[:space:]]*\(' \
    /var/www/html/ch/lib/pear/LiveUser.php

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    grep -n -A18 -B6 \
    -E 'function[[:space:]]+(__construct|Event_Dispatcher)[[:space:]]*\(' \
    /var/www/html/ch/lib/pear/Event/Dispatcher.php

section "PHP 8.2 lint"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/LiveUser.php

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Event/Dispatcher.php

section "Direct Event_Dispatcher test"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear <<'PHP'
<?php

require_once 'Event/Dispatcher.php';

$dispatcher = Event_Dispatcher::getInstance();

echo 'Event_Dispatcher::getInstance(): ',
    is_object($dispatcher)
        ? get_class($dispatcher)
        : gettype($dispatcher),
    PHP_EOL;

if (!is_object($dispatcher)) {
    exit(1);
}
PHP

section "Direct LiveUser constructor test"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear <<'PHP'
<?php

require_once 'LiveUser.php';

$debug = false;
$liveUser = new LiveUser($debug);

echo '__construct present: ',
    method_exists($liveUser, '__construct') ? 'yes' : 'no',
    PHP_EOL;

echo 'Error stack: ',
    is_object($liveUser->stack)
        ? get_class($liveUser->stack)
        : 'NULL',
    PHP_EOL;

echo 'Dispatcher: ',
    is_object($liveUser->dispatcher)
        ? get_class($liveUser->dispatcher)
        : 'NULL',
    PHP_EOL;

if (!is_object($liveUser->dispatcher)) {
    exit(1);
}
PHP

section "Request Chisimba"

curl \
    --silent \
    --show-error \
    --location \
    --max-time 45 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

section "Recent web log"

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=140 web
