# Chisimba Public Demonstration Deployment

**Milestone:** 12  
**Baseline tag:** `v0.9.0-php82-public-demo`  
**Public address:** `https://dev.chisimba.com/`  
**Application path:** `https://dev.chisimba.com/ch/`  
**Deployment date:** 20 July 2026  
**Author/Developer:** Derek Keats

## Purpose

This document records the first successful public deployment of the restored
Chisimba framework on PHP 8.2 with the Chisimba Reborn presentation layer.

It is the recovery and replication reference for the public demonstration
baseline.

## Verified result

The deployment was verified with all of the following conditions:

- Chisimba runs under PHP 8.2 in Docker.
- MySQL 5.5.62 runs in a separate Docker container.
- The database passes an authenticated `SELECT 1`.
- The web application returns HTTP 200.
- No PHP fatal-error markers appear in deployment logs.
- Docker publishes the web service only on `127.0.0.1:8082`.
- Apache reverse-proxies the public domain to the localhost-only service.
- Let's Encrypt provides HTTPS for `dev.chisimba.com`.
- Certbot automatic-renewal simulation succeeds.
- HTTP redirects to HTTPS.
- The bare domain redirects to `/ch/`.
- The Chisimba Reborn skin is active on the installed system.

## Architecture

```text
Browser
  |
  | HTTPS :443
  v
Apache 2.4
  |
  | reverse proxy
  v
127.0.0.1:8082
  |
  v
PHP 8.2 Docker web container
  |
  | internal Docker network
  v
MySQL 5.5.62 Docker database container
```

The Docker web port must remain bound to `127.0.0.1`, not `0.0.0.0`.
Apache is the only intended public entry point.

## Repository layout

```text
/run/media/derek/main/chisimba-revival/
├── framework/
├── modules/
├── canvases/
├── dev-environment/
├── shellscripts/
└── chisimba-info/
```

The repositories are the source of truth. The assembled runtime is disposable
and should not be edited manually.

## Server layout

```text
/var/www/dev.chisimba.com/
```

Deployment Compose file:

```text
/var/www/dev.chisimba.com/compose/php82-deployment.yml
```

Production diagnostics:

```text
/var/www/dkeats.com/killme.txt
```

Local application endpoint:

```text
http://127.0.0.1:8082/ch/
```

## Apache and TLS

Enabled site files:

```text
/etc/apache2/sites-available/dev.chisimba.com.conf
/etc/apache2/sites-available/dev.chisimba.com-le-ssl.conf
```

The HTTPS VirtualHost proxies to:

```text
http://127.0.0.1:8082/
```

An exact-root rewrite sends the bare domain to `/ch/`. The rewrite must appear
before the catch-all `ProxyPass /` directive.

Certificate files:

```text
/etc/letsencrypt/live/dev.chisimba.com/fullchain.pem
/etc/letsencrypt/live/dev.chisimba.com/privkey.pem
```

Verification commands:

```bash
sudo apache2ctl configtest
sudo certbot renew --dry-run
curl -I https://dev.chisimba.com/
curl -I https://dev.chisimba.com/ch/
```

## Known warnings

Apache reports stale `DocumentRoot` warnings for:

```text
/var/www/hosting.kengasolutions.com/
/var/www/staging.kengapub.com/
```

These originate in older enabled VirtualHosts and are unrelated to Chisimba.
They should be audited separately.

## Recovery principles

- Treat Git repositories as the source of truth.
- Reassemble the runtime instead of editing it manually.
- Keep Docker port `8082` bound to localhost.
- Back up Apache and Let's Encrypt configuration before changing it.
- Run `apache2ctl configtest` before Apache reloads.
- Use an authenticated SQL query for database health checks.
- Write diagnostics to `killme.txt`.
- Restore from the Milestone 12 tag when a known-good baseline is required.

## Baseline significance

This milestone demonstrates that the restored Chisimba framework, modules,
deployment system, and Chisimba Reborn presentation layer operate together on a
public HTTPS endpoint under PHP 8.2.

Future work should complete the design system, modernise the shell and common
components, and later replace legacy authentication and authorisation
dependencies.
