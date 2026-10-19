# Module Catalogue patch runner repair — 2026-10-19

Shared framework source: `a3fa6b839` on
`integrate/rest-api-current-runtime-20261018` (published to GitHub).
Module Catalogue version 3.142. Four production source files, pinned in manifest.
All six sites had identical baseline hashes matching the parent source commit.

The tooling derives from the previously verified six-site release workflow.
prepare.py copies each site's current release and applies only the manifest,
lints with its exact PHP image, rehearses against an internal-network disposable
MariaDB clone, runs the real pending-XML PDO regression fixture, updates only
Module Catalogue twice and compares protected business-data fingerprints.
Disposable database containers, copied credentials and rehearsal dumps are removed
on successful completion. No unrelated pending module updates are applied.

deploy.py requires a matching successful rehearsal and unchanged source, acquires
the site's release/worker locks, stops writers, backs up the database and persistent
files, verifies backups, switches to the prepared release, registers/verifies the
catalogue, checks protected-data fingerprints and source hashes, restarts the web
container and checks public home/sign-in/reset pages. Mail timers are restored.
A failure after the switch stops for diagnosis rather than blindly restoring data.

Each remote site directory contains prepared.json and deployed.json receipts;
the associated protected-table snapshots contain only counts and hashes, no rows.
Backups remain private on the appropriate host. Source/test contract:
framework docs/dependencies/module-patch-runner-20261019.md.

This synchronises the catalogue repair across the six sites. Their installed
module sets and unrelated pending releases remain individually managed.

## Completed rollout

All six deployments completed on 2026-10-19. Each site registered Module Catalogue
3.142 and passed home, sign-in and password-reset HTTP checks. Source hashes
match the shared manifest; web containers and configured mail timers are running.
Protected table fingerprints matched before/after. Final checks of appended
runtime logs found no fatal/uncaught/database errors.

| Site | Release stamp (UTC) | Protected tables |
| --- | --- | ---: |
| chisimba.com | 20261019-134522 | 121 |
| kengalearn.com | 20261019-134526 | 171 |
| learnthebirds.com | 20261019-134811 | 109 |
| kengasolutions.com | 20261019-134941 | 218 |
| heritagetreazures.com | 20261019-135032 | 218 |
| kengapub.com | 20261019-135114 | 222 |

Non-secret receipts in `receipts/` record exact release and private backup paths,
image IDs, source/backup hashes and final service checks. `verify.py` performs
read-only post-release verification. Fingerprints exclude catalogue, language,
configuration, permissions and other registration bookkeeping as specified in
`prepare.py`; editable site navigation is checked separately.
