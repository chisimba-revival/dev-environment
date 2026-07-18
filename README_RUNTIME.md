# Chisimba Revival: PHP 7.4 Development Runtime

This document contains the routine commands for starting, stopping, checking, and rebuilding the Chisimba PHP 7.4 development environment.

## Workspace

```text
/run/media/derek/main/chisimba-revival
```

Run all commands from the workspace root unless stated otherwise.

```bash
cd /run/media/derek/main/chisimba-revival
```

## Start the PHP 7.4 environment

Start both the web and database containers:

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    up -d
```

Open Chisimba in the browser:

```text
http://localhost:8081/ch/
```

## Check container status

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    ps
```

The expected services are `web` and `db`.

## View recent logs

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    logs --tail=100 web
```

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    logs --tail=100 db
```

Follow the web logs continuously:

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    logs -f web
```

Press `Ctrl+C` to stop following logs. This does not stop the container.

## Restart the web container

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    restart web
```

## Stop the environment

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    stop
```

## Start previously stopped containers

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    start
```

Using `up -d` is also safe and is usually the simplest command.

## Rebuild the Chisimba runtime from source

```bash
./dev-environment/scripts/rebuild-php74-runtime.sh
```

This preserves installed state and generated content when a valid installed runtime already exists.

## Rebuild the curated PEAR compatibility pack

Only run this when the PEAR manifest or builder has changed:

```bash
./dev-environment/scripts/build-chisimba-pear-runtime.sh
```

Then rebuild the runtime:

```bash
./dev-environment/scripts/rebuild-php74-runtime.sh
```

## Enter the web container

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    exec -u root web bash
```

Leave with:

```bash
exit
```

## Check PHP version

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    exec -T web \
    php -v
```

## Check XML Serializer dependencies

```bash
docker compose \
    -f dev-environment/compose/php74.yml \
    exec -T web \
    ls -l \
        /var/www/html/ch/lib/pear/XML/Serializer.php \
        /var/www/html/ch/lib/pear/XML/Unserializer.php
```

## Consolidated diagnostics

```bash
cd /run/media/derek/main/chisimba-revival

{
    echo "================ CONTAINERS ======================"
    docker compose \
        -f dev-environment/compose/php74.yml \
        ps

    echo
    echo "================ PHP VERSION ====================="
    docker compose \
        -f dev-environment/compose/php74.yml \
        exec -T web \
        php -v

    echo
    echo "================ WEB LOGS ========================"
    docker compose \
        -f dev-environment/compose/php74.yml \
        logs --tail=150 web

    echo
    echo "================ DATABASE LOGS ==================="
    docker compose \
        -f dev-environment/compose/php74.yml \
        logs --tail=80 db

} > /run/media/derek/main/chisimba-revival/killme.txt 2>&1
```

## Fresh installer testing

A fresh installer test must begin from a completely clean installation state:

- use an empty/new database volume;
- ensure there is no `config/installdone.txt`;
- do not continue from a partially installed schema.

Do not reset the database during normal post-install compatibility testing.

## Important paths

Framework source:

```text
/run/media/derek/main/chisimba-revival/framework/app
```

Generated PHP 7.4 runtime:

```text
/run/media/derek/main/chisimba-revival/dev-environment/runtime/php74-ch
```

Runtime path inside the container:

```text
/var/www/html/ch
```

Compose file:

```text
/run/media/derek/main/chisimba-revival/dev-environment/compose/php74.yml
```

Safe rebuild script:

```text
/run/media/derek/main/chisimba-revival/dev-environment/scripts/rebuild-php74-runtime.sh
```

Curated PEAR builder:

```text
/run/media/derek/main/chisimba-revival/dev-environment/scripts/build-chisimba-pear-runtime.sh
```
