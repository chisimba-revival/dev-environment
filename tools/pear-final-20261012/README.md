# Final PEAR runtime release — 12 October 2026

Dated operators for the authorised six-site release, adapted from the earlier
PEAR rollout. These are execution records, not a generic unattended deployer.
Reuse requires fresh drift checks, target/worker review and isolated rehearsal.

The 299-entry common manifest covers the remaining source changes since the
previous PEAR release, including the already-deployed Kanban fix. Effective
manifests include only modules present on a site. No new dormant module is enabled.
The release removes the entire `lib/pear` runtime alongside native-only source.
All six sites must already have PDO MySQL and PDO configuration.

Before staging, each differing deployed file was matched to a known version in
Git history. No unknown edits were found. Payloads come from the committed source
listed in commits.json. Private per-site hash inventories are required separately.

Preparation copies the existing release, overlays the manifest, lints in the exact
production image and restores a database snapshot in an internal-only disposable
network. It performs normal catalogue updates twice and verifies native
configuration, translation, authentication/MFA and module discovery. No external
email can leave the rehearsal. Protected business rows and editable site links
are compared before/after. Existing metadata exclusions remain explicit in
prepare.py; full backups include those tables too.

Deployment rechecks source/image/stage identity, coordinates the site's existing
worker locks/timers, stops only web, verifies database and persistent-file backups,
retains the prior release and switches code. Catalogue updates and protected-data
checks run before reopening web. It never restores a live database automatically.
Final verification checks manifest hashes, absent PEAR directories, PHP log deltas
and resumed mail timers. Public HTTP and browser checks supplement native service
checks. Do not commit copied configurations, database dumps, credentials or private
hash/log inventories to this repository.

KengaLearn coordinates its mail worker through the existing readable flock, with
its timer left active; the other relevant site mail timers stop and restart around
the switch. No diagnostic or test email is sent.

## Completed production rollout

All six sites were deployed and verified on 12 October 2026, beginning with
Chisimba.com. Each now runs without an application `lib/pear` directory.
The deployed framework source is `e082c178e`, modules `02498125c`; release tooling
and the empty dependency pack were based on dev-environment `9179440`.

| Site | Release stamp (UTC) | Protected tables checked | Result |
|---|---|---:|---|
| Chisimba.com | 20261012-123301 | 107 | Online, verified |
| KengaLearn | 20261012-123421 | 171 | Online, verified |
| Learn the Birds | 20261012-123535 | 109 | Online, verified |
| KengaPub | 20261012-123740 | 222 | Online, verified |
| KengaSolutions | 20261012-123838 | 218 | Online, verified |
| Heritage Treazures | 20261012-123936 | 218 | Online, verified |

All final manifests matched, PEAR paths were absent, and the checked post-release
PHP log deltas contained zero new diagnostics. Mail timers were active on all four
sites with configured mail timers. Protected business rows and editable site
navigation remained unchanged across each switch. Previous releases and verified
database/persistent-file backups remain available on each server.

Browser checks covered every site: sign-in pages/session status, KengaLearn's
authenticated Kanban boards, and Learn the Birds' webinar management and reminder
dashboard. No test email was sent and no real board or webinar was edited. The
LTB dashboard retained its reminder schedule and reported a resumed worker run.

Historical test oracles, dormant-module references and recoverable old releases
are intentionally distinct from the deployed runtime. Retiring those records is
not required for PEAR-free operation; dormant modules still require modernisation
and testing before activation.
