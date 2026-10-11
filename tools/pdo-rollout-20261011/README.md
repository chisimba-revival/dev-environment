# PDO rollout evidence — 11 October 2026

These are the reviewed operators used for the authorised chisimba.com then
KengaLearn rollout. They are a dated release record, not a general unattended
deployer. Do not reuse them for other sites or run a deployment without a fresh
authorisation, source audit, backups, rehearsal and review of the current state.

The application source commits are in `commits.json`; `manifest.json` contains
668 overlay entries with SHA-256 hashes (null means a committed deletion).
Payload files come from those framework/modules commits; private data is never
part of this repository. The same overlay is applied to both audited releases.
Source outside this overlay and assembled dependency libraries are preserved.

## Sequence and boundaries

1. Audit source hashes against Git history; stop on unknown/newer drift. Supply
   each site's `<site>-hashes.json` and the checked `payload/` beside these files.
2. `build-image.py SITE` adds pdo_mysql to the exact running image. It does not
   replace the live container or another site's image tag.
3. `prepare.py SITE` stages the overlay, compiles with the candidate image,
   restores a consistent database copy in an internal-only Docker network and
   runs strict catalogue/runtime checks. Its disposable upload directories never
   mount live files. Catalogue updates run twice; business hashes must match.
   Block declaration values are checked against each registration file separately
   because catalogue updates regenerate their metadata IDs. Unregistered modules
   are enabled only as explicit dependencies of an updated registered module.
4. `contracts.py IMAGE SITE` uses `tests/database/` copied from the framework
   commit and a separate disposable schema. Both production images passed the
   native PDO, concurrency, rollback and 107-definition installer suite.
5. `log-window.py SITE before` records log offsets. `deploy.py SITE` verifies
   rehearsal/source/image identities, stops web writers, backs up database and
   persistent files, switches configuration/code/image together, applies the
   rehearsed updates while web remains stopped, verifies protected data and
   reopens the site. Only the target web container is recreated. KengaLearn's
   AI/worksheet locks are held; no worker is triggered by these operators.
6. Check public and authenticated browser workflows, then run the log-window
   checker and inspect any findings. HTTP 200 alone is not acceptance.

Chisimba.com did not have System Management installed: its deployment therefore
used a stopped application container rather than enabling a new maintenance
module. KengaLearn used its existing maintenance flag and stopped container.

Private `<site>/` rehearsal outputs and backups stay on the corresponding host.
They include copied installation keys and database dumps and must never be
committed. A failure stops for diagnosis; it does not overwrite a live database.
Retain previous code, exact image ID, original Compose/configuration and verified
backups. Recovery must coordinate these and consider any catalogue changes.

See the framework's `docs/database-migration/production-rollout-20261011.md` for
release paths, verification results, limits and the later-site rollout gate.
