# Communications worker production installation

The registration flow queues email. A worker must process that queue regularly.
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
