# Local PDO prerequisites

The PHP 8.5 image installs both `mysqli` (the existing MDB2 backend) and
`pdo_mysql` (the migration target). Installing the driver does not switch the
application backend. Do not select the old engine PDO branch: the shared adapter
and direct callers still need migration.

Build and test without touching an installed database:

```sh
docker compose -f compose/php85.yml build web
python3 tests/pdo/run-readiness.py
```

The runner creates a randomly named internal Docker network and disposable
MariaDB 10.11.18 container with tmpfs storage, random credentials and no published
ports. It removes those resources on exit. It never reads site credentials or
connects to the existing Chisimba database. An optional first argument selects a
local PHP image to verify. Docker access is required.

The fixture checks actual prepared values, four-byte Unicode, associative/null
results, commit and rollback, visibility from a second connection, compare-and-set
affected counts, duplicate-key SQLSTATE and connection-owned advisory locks. It
also requires mysqli to remain available during migration. This verifies driver
prerequisites; it does not certify the future dbTable/PDO implementation.

For an existing local web container, preserve any needed PHP sessions before
replacement and retain the previous image for rollback. Recreate only `web` with
`up -d --no-deps web`; do not rebuild the assembled application, reset the database,
or remove volumes. Verify HTTPS routing, the installed engine and browser pages.

Decision, 11 October 2026: all migration work and testing stays local and uncommitted
until local acceptance is complete. The first later production rollout is
chisimba.com. Check each target's PHP image and add its appropriate PDO driver
before deploying migrated application code. KengaLearn is not a migration test site.
