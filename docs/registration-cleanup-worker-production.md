# Registration cleanup worker: production installation

Part of the [complete worker setup](workers.md). This is a separate daily worker,
not part of the mail or AI worker. It needs no external bot service or paid API.

## Prerequisites and policy

Deploy Abuse Protection 0.2+, Registration Service 1.022+, My Administration 0.108+
and the coordinated Chisimba Reborn skin. Apply normal Module Catalogue updates
to register configuration and language items. This feature adds no schema change.
Use the running application's database and protected installation configuration.

Administrators can open **My Administration → Registration protection**, including
**Help with this page** and **Change registration settings**. Defaults are:

- `REGISTRATION_PENDING_DAYS=7`: confirmation period for **new** requests. Existing
  deadlines are unchanged.
- `REGISTRATION_RETENTION_DAYS=30`: additional days after dismissal/expiry before
  redacting the pending record's names, username, contact and identity details.
- `REGISTRATION_AUTO_CLEANUP=0`: disabled until explicitly enabled.

Expiry/dismissal immediately clear the saved password and prevent verification.
Verified requests, linked accounts, selected payment products and canonical
username/email matches are protected. Cleanup never deletes user accounts,
payments, enrolments or learning records. Opaque references, timestamps and
minimal account-event audit records remain. Email and legal-acceptance records
follow their own retention policies. Names are review hints, never cleanup rules.

## Preview first

Replace the container name and application root with the verified deployment:

```sh
docker exec YOUR_WEB_CONTAINER test -f /var/www/html/packages/registration-service/scripts/run_registration_cleanup.php
docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/registration-service/scripts/run_registration_cleanup.php --preview
```

Omitting the argument also previews. Example idle output:

```json
{"expire":0,"redact":0,"protected":0,"scanned":0,"limit":200}
```

Preview changes no records. `expire` and `redact` count eligible actions among the
bounded candidates. `protected` counts held requests; it is not a deletion list.
Use the administrator page for personal details; CLI output contains counts only.

Review policy and preview, install **one** schedule below, then set
`REGISTRATION_AUTO_CLEANUP=1` through Registration Service settings. Run the apply
command once and inspect its result:

```sh
docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/registration-service/scripts/run_registration_cleanup.php --apply
```

A healthy idle apply reports:

```json
{"enabled":true,"expired":0,"redacted":0,"protected":0,"failed":0}
```

`{"enabled":false}` means the setting is off; it does not prove scheduling works.
The worker processes up to 200 candidates per run, then purges expired shared
abuse events. Use preview to monitor a backlog and shorten the interval if needed.
Repeated protected candidates need administrator review. Failed batches return a
nonzero status; successful earlier transitions remain committed and retries are
safe. Audit events identify expiry, dismissal and redaction separately.

## Option A: cron

Use the deployment account's `crontab -e`. That account needs Docker permission
and write access to `/srv/chisimba` and `/srv/chisimba/logs`; create these directories
with appropriate ownership before scheduling. Adapt paths rather than granting
broad write permissions. Example daily entry:

```cron
20 2 * * * /usr/bin/flock -n /srv/chisimba/registration-cleanup.lock /usr/bin/docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/registration-service/scripts/run_registration_cleanup.php --apply >> /srv/chisimba/logs/registration-cleanup.log 2>&1
```

Cron uses the **host timezone**. On a UTC host this runs at 02:20 UTC / 04:20
Africa/Johannesburg. Choose your intended local time deliberately. This example
is a user crontab; `/etc/cron.d` files require a username after the time fields,
a trailing newline and root ownership with mode 0644.

Verify `crontab -l`, the cron daemon and a fresh scheduled log entry. Include the
log in normal log rotation. Remove/comment this specific entry to unschedule it.

## Option B: systemd

Instead of cron, save `/etc/systemd/system/chisimba-registration-cleanup.service`:

```ini
[Unit]
Description=Expire and redact abandoned Chisimba registration requests
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -n /run/chisimba-registration-cleanup.lock /usr/bin/docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/registration-service/scripts/run_registration_cleanup.php --apply
```

Save `/etc/systemd/system/chisimba-registration-cleanup.timer`:

```ini
[Unit]
Description=Run Chisimba registration cleanup daily

[Timer]
OnCalendar=*-*-* 02:20:00 UTC
Persistent=true
Unit=chisimba-registration-cleanup.service

[Install]
WantedBy=timers.target
```

Replace the container/path placeholders in the service. Install both root-owned
files with mode 0644, then:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now chisimba-registration-cleanup.timer
systemctl list-timers chisimba-registration-cleanup.timer
journalctl -u chisimba-registration-cleanup.service
```

`Persistent=true` can trigger a missed run after downtime. Once policy is enabled,
that catch-up can expire/redact requests immediately. To stop future runs:

```sh
sudo systemctl disable --now chisimba-registration-cleanup.timer
```

Also disable `REGISTRATION_AUTO_CLEANUP`. Do not install both cron and this timer.

## Verification and troubleshooting

- Check the PHP script exists **inside** the actual container and the container
  is running. Do not point a live schedule at a rehearsal database or old release.
- Verify both the setting and a fresh scheduled-run log/journal entry. The web
  page's enabled message describes policy; it is not a scheduler heartbeat.
- Run preview again after an apply and compare the counts. A reduced backlog and
  corresponding account-event audit records establish that work occurred.
- If `failed` is nonzero, retain diagnostics and check application/database access,
  module updates and audit-service availability before retrying. Do not bypass
  the protection checks or modify canonical account tables directly.
- To pause during deployment/restore, disable the schedule and policy and check
  for an already running invocation. Stopping scheduling cannot restore redacted
  details or cleared passwords; recovery would need the appropriate backup.
- The signup controls work independently of the cleanup schedule. Configure
  `REGISTRATION_TRUSTED_PROXIES` only with the actual trusted reverse proxy
  addresses/networks. Recheck it if a proxy container address changes.

## KengaLearn deployment reference

Verified 21 September 2026: `/etc/cron.d/chisimba-registration-cleanup` runs at
02:20 UTC daily against `kengalearn-production-web-1`, using the application path
`/var/www/html/packages/registration-service/scripts/run_registration_cleanup.php`.
It uses `/run/chisimba-registration-cleanup.lock` and logs to
`/var/log/chisimba-registration-cleanup.log`. The policy is enabled. This is a
site-specific example, not a default container name for new installations.
