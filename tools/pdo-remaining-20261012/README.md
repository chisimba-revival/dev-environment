# Remaining production PDO switches — 12 October 2026

Derek authorised KengaPub, KengaSolutions and Heritage Treazures to switch to PDO
following their completed PEAR cleanup rollout. These dated operators record that
specific operation; they are not a general deployment command. Reuse needs a fresh
audit, rehearsal and review of the intended target and worker configuration.

## Scope

Application code, database contents, schema, credentials, uploads and existing
release symlinks remain unchanged. The PHP image gains `pdo_mysql`; the only
application configuration change is `DATABASE_ABSTRACTION` from MDB2 to PDO.
The web service's Compose image changes to `chisimba/pdo-remaining:20261012`.
The database service is never recreated. Existing extensions, including mysqli,
remain available. No PEAR directories are removed by these operators.

The image was built from the exact running parent image
`sha256:fae7188e142b799d73a08768d9f1a9da95aec12106ec126d3e2921ca9c5b0386`
with `RUN docker-php-ext-install -j2 pdo_mysql`. All three parents were identical.
The original immutable image and previous Compose/configuration are retained.

## Evidence and sequence

1. `prepare.py` snapshots current source/configuration hashes and stages an
   unchanged code copy. It verifies the parent image and extension preservation.
   Each database is restored into an isolated internal Docker network with tmpfs
   data. Only this disposable configuration selects PDO; uploads and sessions are
   disposable. Two strict runtime checks verify actual PDO composition, native
   configuration, translation, authentication, MFA and catalogue access.
   Every existing table is fingerprinted before and after, including navigation
   and other catalogue metadata; there are no table exclusions for this switch.
2. `contracts.py` runs the full PDO contract, engine-composition and installer
   suites on synthetic data, separately from the database copies. It covers
   binding, value contracts, transactions, rollback, permissions, navigation,
   concurrency, module repositories and schema/catalogue behaviour. Framework
   tests come from `23b64a39d`. KengaSolutions' first run exposed a missing test
   fixture: Shop is not installed there. For sites without Shop, the runner mounts
   the committed `shop/` from modules `e8d2dfd2c` under `fixture-modules/shop`, in a separate disposable module tree,
   mounted read-only inside the test container. An initial nested read-only mount
   was rejected by Docker; the separate tree resolved that harness issue. It does not install Shop on those sites.
3. `deploy.py` requires successful rehearsal and contract receipts. It rechecks
   source, config and image identities, stops configured mail timers, drains any
   running service and holds its lock. After stopping only web, it creates and
   verifies complete database and persistent-file backups. It changes the two
   configuration selections, requires strict native PDO verification, and checks
   all table fingerprints remain identical before recreating only web.
4. Public HTTP and browser checks follow. `final-verify.py` checks the actual
   running image/backend, unchanged source and unrelated configuration, PHP log
   deltas and active mail timers. There are no test emails, orders or payments.

`operator.php` is the already rehearsed strict verifier from the preceding PEAR
rollout with an added mandatory PDO assertion. Only its `verify` mode is invoked
here; no catalogue upgrade or maintenance-setting mutation is needed.

Private source/configuration hashes, database dumps, staged trees, receipts,
fixture payloads and logs stay under `/srv/pdo-remaining-20261012` on the shared
host and are not committed. Supply `tests/` and the optional Shop fixture from
those commits before running the contract suite. Backups reside under each site
root's `backups/pdo-STAMP`. An exception stops for diagnosis; do not blindly restore
a database over subsequent user writes. Configuration/image rollback must be
coordinated with stopping web and workers, retaining all current user data.
