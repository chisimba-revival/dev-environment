# Disposable browser installer test

Use a new database and a fresh copy of `framework/app`, never an installed
runtime's configuration, uploads or database. The framework bundle includes the
remaining compatibility libraries; do not use a machine-wide PEAR installation.
New installations require PHP 8.2+ with `pdo_mysql` and the other extensions
checked by the installer. PHP 8.5.11 / MariaDB 10.11.18 were used on 2026-10-11.

## Isolated setup

From the workspace containing `framework`, `modules`, and `dev-environment`:

1. Choose a new empty directory outside Git (for example
   `dev-environment/runtime/installer-test/ch`) and copy `framework/app/.` there.
   Do not copy an installed site's state. Ensure `config/installdone.txt`,
   `config/config.xml` and `config/dbdetails_inc.php` do not exist.
2. Create a uniquely named **internal** Docker network. Start MariaDB on that
   network with alias `db`, `/var/lib/mysql` on tmpfs, a test-only root password,
   and no published database port. Do not share any database volume.
3. With a short-lived helper container, give `www-data` ownership of the copied
   application root. Then start a web container using the existing PDO-capable
   local image, mount the copy at `/var/www/html/ch`, and mount `modules` at
   `/var/www/html/ch/packages:ro`. Optionally mount the candidate source installer
   at `/var/www/html/ch/installer:ro` while developing it. Do not recursively
   chown through source mounts.
4. Internal Docker networks may not publish host ports. Obtain the new web
   container's IP with `docker inspect`, then run a loopback-only relay:
   `socat TCP-LISTEN:8086,bind=127.0.0.1,reuseaddr,fork TCP:CONTAINER_IP:80`.
   This allows local browser access without giving the containers outbound access.
5. Open `http://127.0.0.1:8086/ch/installer/`. Use fixture-only site details and
   an `example.invalid` email address. Enter host `db`, the test credentials and
   a new database name. Follow the configuration, schema and first-registration
   steps; sign in with the initial fixture account. Do not send mail or enable
   external workers.

Verify native PDO composition with
`framework/tests/installer/installed_runtime_smoke.php`, executed inside the new
web container with `CHISIMBA_INSTALLER_FIXTURE=1` and its application root argument.
The script reads only the explicitly selected installed fixture.

Check PHP logs across installation, first registration, login, catalogue and user
administration. Verify missing bundled dependencies block the requirements step,
then restore them. The CLI requirements test also covers missing PDO MySQL with `php -n`.
A failed registration can leave partial tables/module registrations; reset **only
the disposable database** before retesting to avoid a misleading partial success.

## Test instance from 2026-10-11

- URL: `http://127.0.0.1:8086/ch/`
- Containers: `chisimba-installer-test-web`, `chisimba-installer-test-db`
- Network: `chisimba-installer-test` (internal)
- Database: `installer_fresh`, entirely synthetic and on tmpfs
- Application copy: workspace `work/installer-fresh-20261011/ch`
- Relay: local `socat`, bound only to 127.0.0.1:8086
- No live-site credentials, database, uploads or production access were used.

When finished reviewing, stop the relay and remove those two named containers and
that named network. Removing the disposable database container discards its tmpfs
data. The ordinary `chisimba-php85-*` containers and their volumes are unrelated.
The generated application copy and diagnostic logs are outside source control.
