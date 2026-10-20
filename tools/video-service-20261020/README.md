# Chisimba.com Video Service release — 20 October 2026

Bounded deployment of modules commit `ae7de8abb`: Video Service 0.001 and
ContextContent 2.106. CPD remains a course configuration. No provider credentials,
real media uploads, new enrolments, test courses or external archives are created.
The canonical application URL is `https://www.chisimba.com/index.php`.

The manifest contains the 37 files from the implementation commit. All existing
changed ContextContent files matched their pre-change Git hashes; new files were
absent. Audited the remaining ContextContent source and framework services.
Existing framework differences are retained without modification; the exact
server image/source is used for the database rehearsal. No framework release or
unrelated paused-module removals are included.

`prepare.py chisimba` copies the existing release, overlays the manifest, checks
PHP syntax, and rehearses registration twice and provider/PDO fixtures against an
isolated live-data clone on an internal Docker network. All 123 existing protected
tables and editable navigation rows remained unchanged. No provider network calls
are made by the fixtures. Clone credentials and database dumps remain server-only
and are removed after successful preparation.

`logging_policy.prepare` stages a path-only Apache access-log format for this
site's frontend and backend. Query strings and referrers are excluded so caption
capability tokens do not appear in access logs. Existing routing is preserved.
The backend policy is syntax-checked in the exact application image.

`deploy.py chisimba` requires the prepared manifest, checks source drift again,
acquires the shared release lock, stops the application, verifies database and
persistent-file backups, installs the logging policy, switches the release and
registers the two modules including their guarded postinstall hooks. It sets
VIDEO_PUBLIC_URL only if blank. It preserves all secret parameters. It verifies
protected data and source hashes before recreating the application container.
On failure it stops for diagnosis; it never silently restores an older database.
Previous code, data backups, Compose and logging configuration are retained.

`verify.py chisimba` verifies the deployed manifest, protected-data fingerprints,
logging policy and new runtime diagnostics. Non-secret deployment receipts are
saved under `receipts/` after completion.

Mux account configuration and actual upload, playback, captions and deletion
acceptance remain pending. Use the same Mux environment for API tokens, playback
signing keys and the webhook:

```
https://www.chisimba.com/index.php?module=video-service&action=webhook&configuration=mux-default
```

The reconciliation CLI is available; a scheduled worker is not installed by this
release. Sysconfig redesign remains separate work.

## Completed deployment

Live release: `/srv/chisimba-com/releases/release-video-service-20261020-072327/ch`.
Backups: `/srv/chisimba-com/backups/video-service-20261020-072327`.
All 123 protected data tables retained their fingerprints. Source checks passed;
zero new fatal errors or deprecations. The unsigned webhook returns HTTP 401 and
an invalid caption capability returns HTTP 404. Both Apache access logs omit the
synthetic query token. Authenticated browser checks passed for the library, Help
and the eight Sysconfig settings. Credentials remain blank.
