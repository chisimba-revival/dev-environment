# Communications worker production installation

See the [complete worker installation checklist](workers.md) for all queues,
including the separate [registration cleanup worker](registration-cleanup-worker-production.md).

Registration and password recovery queue email. A worker must process that queue
regularly, including on sites where public registration is disabled. The login
page must expose the canonical `registration-service/forgotpassword` route.
Configure Communications transport, sender and provider credential explicitly;
working contact-form SMTP alone does not configure queued account mail. The
`null` transport is for tests and does not deliver a real reset email.
For a Docker-based production host using systemd, install the supplied system
timer after the framework and modules have been deployed:

```sh
sudo ./scripts/install-communications-worker-production.sh \
  --container chisimba-web \
  --interval 1min \
  --batch-size 20
```

Use the actual PHP container name from `docker ps`. The worker path defaults to
`/var/www/html/ch/core_modules/communications/scripts/run_outbox_worker.php`;
override it with `--worker-path` if the application has a different container
layout. Run `--help` for all options.

The installer creates a root-owned configuration in `/etc/chisimba`, installs a
host-level systemd service and timer, enables the timer at boot, and immediately
runs one delivery cycle. No SendGrid key is copied: the worker reads the normal
Chisimba settings inside the running application container.

Check operation with:

```sh
systemctl status chisimba-communications-worker.timer
journalctl -u chisimba-communications-worker.service
```

To remove the scheduling integration:

```sh
sudo ./scripts/uninstall-communications-worker-production.sh
```

Re-run the installer after changing the container name, interval, batch size, or
container layout. It is safe to use from an automated deployment script.


## Separate sites sharing a host

Each independent site database needs its own schedule, container target and lock.
Do not repoint another site's existing timer to a new container. Before enabling
real delivery, review the queued backlog and verify the configured sender and
provider. An empty successful batch checks worker operation; it is not proof of
provider acceptance or inbox delivery. Do not send unsolicited test messages.

Heritage Treazures uses `heritage-mail.service` and `heritage-mail.timer`, with
container `heritagetreazures-chisimba-web-1`, application root `/var/www/html/ch`,
a one-minute interval, batch limit 20 and `/run/lock/heritage-mail.lock`. Its
site-specific deployment templates and setup notes are retained in the WordPress
conversion operations handover. Use `journalctl -u heritage-mail.service` to
inspect execution; keep mail credentials in the site's protected configuration.
