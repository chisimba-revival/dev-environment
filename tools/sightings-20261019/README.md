# Sightings with private images — 19 October 2026

Bounded Chisimba.com release, derived from the verified patch-runner release tools.
Framework `19deec227`; modules `8d12fc290`. Android `e6b1610` includes the final
immediate-offline composer correction. The source is shared; deployment targets
only the existing Chisimba.com app test site.

Versions: messaging 2.008, REST 1.008, File Manager 1.116, Context 2.067.
The manifest pins 18 runtime files. The rehearsal checks each live baseline,
creates an isolated database clone with no external network and private tmpfs
storage, performs normal registration twice, verifies InnoDB and module versions,
runs the adapted real PDO/private-image fixture, and compares protected data and
site navigation. Copied configuration/dump and the disposable clone are removed.
The media fixture cannot run through the production operator.

Deployment takes the release lock, stops the web writer, makes and validates
full database/files backups, switches the release, registers/verifies the bounded
module set, checks protected-data fingerprints and hashes, recreates the web
container and checks public home/login/reset responses. Read-only verify.py checks
source, running service and appended runtime errors. Private images require the
existing writable SECUREFODLER outside the web root; it was checked as www-data.

The mobile app uses the existing API and native sign-in. IndexedDB holds smaller
photos and captions atomically per server/account/context. Input bytes/pixels,
output dimensions/bytes and decode attempts are bounded; EXIF orientation is
normalised and metadata removed. The server independently validates/re-encodes.
Stable submission receipts cover both image digest and caption. Access is
rechecked for image bytes, history and duplicate receipts, even for public courses.
No notifications or live synthetic posts are sent by deployment.

Local validation includes normal HTTP login/upload, duplicate/conflict, malformed
image, anonymous and revoked-member access, real PDO rollback, metadata stripping,
private storage, deletion outbox/rollback and bounded orphan maintenance. The
synthetic browser adapter checks offline/reload/reconnect, orientation, revoked
history and phone-width layout/Help. Android debug build passes. Native phone
photo-picker/upload acceptance is left to the user after the in-place update.

Course deletion records file removals transactionally and drains only after commit.
A failed cleanup stays queued. Interrupted pre-commit uploads can leave private,
unreferenced files; messaging/tools/cleanup-images.php offers a bounded dry run
and explicit --apply cleanup after 24 hours. This release creates no scheduled job.

Preserved: unrelated paused-module moves, Android IDE files, development Compose
changes, saved phone sessions and user drafts. Source test accounts/groups and
synthetic server content were removed after local verification.

## Completed rollout

Release: `/srv/chisimba-com/releases/release-sightings-20261019-143926/ch`.
Backup: `/srv/chisimba-com/backups/sightings-20261019-143926`.
All 121 protected table fingerprints matched; source hashes and public routes
passed. Final runtime-log check found zero new fatal/database errors or
deprecations. Both sightings/image API endpoints reject anonymous requests (401).
The signed-in browser shows Sightings in Getting started with Chisimba, using
the server’s Course terminology and the existing two-panel layout.

Samsung SM-S908E updated in place at 16:40:59 SAST; installer returned Success.
Exact APK/source hashes are recorded in receipts/android.json. Saved app data
was retained; no live photo was posted on the user’s behalf. The first real-phone
photo selection and upload remain the user acceptance check.
