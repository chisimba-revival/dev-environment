# LearnTheBirds PDO and webinar release — 11 October 2026

These are dated, site-specific operators for the expressly authorised
LearnTheBirds update. They are evidence, not a reusable unattended deployment
service. Other sites are outside this release. Review current state, obtain
appropriate authorisation and repeat source audits and rehearsals before reuse.

## Release content

`commits.json` identifies the pushed framework and modules source commits.
`manifest.json` records 679 overlay paths with SHA-256 hashes; null denotes a
committed deletion. The overlay includes the earlier native PDO, configuration,
translation and installer work plus webinar 0.025 and Audience 0.017.
Unchanged assembled dependencies and site-specific files are retained.

Webinar management shows confirmed registrations and a configurable limit,
defaulting to 170. Current pending confirmations reserve a place for 24 hours.
Transactional event locking protects the last place and confirmation checks the
current limit. Existing confirmed registrations survive a reduced limit.

The admin dashboard has separate controls and pending/queued/sent/failed/cancelled
progress for subscriber and attendee reminders. The authorised site default
enables webinar-day subscriber email at 08:00 SAST. Attendee morning reminders
are also at 08:00 SAST, with a final reminder 90 minutes before the event.
Registered subscribers intentionally receive both morning messages: only the
attendee message includes the private joining link. Existing Monday attendee
reminders and the weekly subscriber newsletter remain separate. Saving settings
does not itself send mail, and newly enabled schedules do not catch up old sends.

## Safety sequence

1. Audit live code against Git history, including every overlay path. Stop for
   unknown or newer changes. Supply the audited `learnthebirds-hashes.json` and
   `payload/` alongside the operators; these are not committed here.
2. `build-image.py` derives the candidate with pdo_mysql from the exact running
   image, retaining its PHP version and existing extensions.
3. `prepare.py` compiles the overlay with that image, copies a consistent live
   database to an internal-only Docker network, updates the catalogue twice and
   verifies native runtime components. Hashes of 109 protected business-data
   tables must remain identical. The clone never mounts live upload folders.
4. `production-image-tests.py` runs synthetic dual-driver capacity/reminder tests
   and Audience/count tests in a separate disposable database. Supply framework
   `tests/`, module `webinar-tests/` and `audience-tests/` from the source commits.
5. Record log offsets with `log-window.py before`. `deploy.py` checks the exact
   rehearsal manifest, source and image identities; stops the mail timer and
   waits for its existing batch lock; enables maintenance when available; and
   stops web writers. It verifies compressed database and persistent-file
   backups before changing code, configuration and image together.
6. Catalogue upgrade, strict PDO checks, protected-table hashes and all overlay
   hashes pass before reopening. Only the target web container is recreated.
   The regular mail timer restarts after HTTP checks. No test email is sent.
7. Verify public and authenticated browser workflows, the dashboard worker
   heartbeat, and `log-window.py check`. Inspect container logs as well.

The operator refreshes the sysconfig object's parameter cache before checking
the reminder activation write. The first activation timestamp is preserved on
repeat runs. The current container's Compose environment-file label is used.

## Validation

- Full PDO contracts, concurrency and rollback tests, engine composition and
  all 107 installer schema definitions passed.
- MDB2 compatibility contracts passed; checked bindings now provide explicit
  types to avoid a PHP 8.5 null-array-key warning.
- Capacity races, expired reservations, duplicate registration, cap changes,
  transactional outbox failure, ownership and permission tests passed on both
  drivers, including the production PHP 8.5.4 candidate image.
- Real outbox fixtures verified both morning messages and joining-link privacy,
  schedule deduplication, disabling queued sends, stale saves and SAST times.
- Audience newsletter/consent integration and Communications regressions passed
  under strict PHP warning handling. No live recipients were used.
- Local browser checks verified last-place rejection, saved cap changes,
  management counts, reminder controls, Help/Escape and narrow-screen layout.

Private clone configuration, installation keys, dumps, logs and backups remain
on the host under `/srv/ltb-webinar-20261011/` and the site's backup directory.
Never commit them. Deployment failure stops for diagnosis and never restores
a database automatically. Recovery must coordinate the retained exact image,
previous code, original configuration/Compose and database catalogue state.

## Deployed result

The release is `/srv/learnthebirds.com/releases/release-pdo-20261011-142654/ch`.
Verified backups are at `/srv/learnthebirds.com/backups/pdo-20261011-142654`.
The previous release is `release-consolidation-20261009-061847/ch`; the retained
old image ID begins `d664aacd1175`, and the new PDO image begins `dc956d7e3ee0`.
All 679 overlay hashes and 109 protected-table fingerprints passed on live.

Maintenance was disabled and HTTP login, home and password-recovery checks
passed. Authenticated browser checks showed 34 confirmed seabird registrations
out of 170, both 08:00 morning schedules and the 17:30 attendee schedule for the
19:00 event. The subscriber estimate was 1,674 at verification time.

The timer's immediate restart attempt skipped because the deployment still held
the mail lock (flock exit 1). Its next regular run at 16:29:40 SAST succeeded,
scheduled no due campaigns and sent no messages. The initial Apache restart
logged one MaxRequestWorkers capacity notice; inspected PHP logs showed no new
warning/error lines. This release does not claim a general load-performance
benchmark or guarantee inbox delivery; the dashboard's Sent count means mail
transport acceptance. At 20 messages per worker batch, the full subscriber send
takes substantially longer than the attendee send, so 08:00 is its queue start.
