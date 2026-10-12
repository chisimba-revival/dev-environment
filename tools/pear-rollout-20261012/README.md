# PEAR retirement rollout — 12 October 2026

Dated operators for Derek's authorised six-site release. These are an execution
record, not a general unattended deployment tool. Reuse requires a fresh source
audit, review of mounts/workers/permissions, clone rehearsal and target authorisation.

The release sources are recorded in `commits.json`. The common manifest contains
1,337 source hashes or explicit file deletions. Sites with smaller package trees
receive only modules already present, plus a complete declared dependency when
required. `dependencies.json` supplies Notes for Heritage Treazures' installed
Kanban module. It does not enable arbitrary dormant modules.

`manifest-initial.json` records the initial 1,323-entry overlay. The fourteen
supporting additions were already byte-identical on Chisimba.com, KengaLearn and
Learn the Birds; `attest-extension.py` checks both the initial audit and their
staged/live files before extending the preparation receipt. The older sites were
rehearsed again against the complete manifest. Never treat a changed manifest as
covered by a prior rehearsal without this byte-identical evidence.

## Safety boundaries

- Source hashes were compared with Git history before staging. Unrecognised files
  were fetched read-only and reviewed. Older Contact Form code is superseded by
  the shared version. Legacy canvas rules already exist in the root skin. A
  deployed import helper's explicit media ownership and audio documentation were
  reconciled into source. Site Pages now honours the older `hide_title` preference
  until the next normal save; focused regression tests cover precedence/defaults.
- No database backend, image, credentials or site configuration is changed.
  Chisimba.com, KengaLearn and Learn the Birds remain PDO; KengaPub, KengaSolutions
  and Heritage Treazures retain their verified MDB2 runtime for this rollout.
- `prepare.py` copies code, applies committed files, prunes the explicitly retired
  libraries/web tests/paused modules, and lints the effective bundle in the exact
  production image. It restores a consistent database dump into an internal-only
  Docker network and tmpfs database. Rehearsal containers use disposable uploads
  and cannot send external email. Catalogue updates run twice, then native
  configuration/translation/authentication/catalogue and retirement checks run.
- Existing protected business-table rows are hashed before and after rehearsal
  and live catalogue updates. The inherited metadata exclusion list is explicit
  in `prepare.py`; this is not a claim that every database table is unchanged.
  Full database backups include all tables. New registered dependency tables are
  expected catalogue additions.
- `deploy.py` rechecks live/stage/image identities, coordinates workers, stops
  only the target web container, verifies compressed database and persistent-file
  backups, and retains the previous code. It switches the code path, runs normal
  catalogue updates while stopped, checks protected data and source hashes, and
  recreates only that web container. There is no automatic live database restore.
- Existing release symlinks are switched at the same Compose mount path.
  Config/data mounts stay intact. The operator also guards the ordinary-directory
  case by retaining that directory before switching; the audited sites used
  existing release symlinks.
- KengaLearn's account cannot administer systemd. Its first attempt stopped before
  any live change. The successful operator holds the existing root-owned readable
  `/run/chisimba-communications-worker.lock`, plus AI/worksheet locks; its timer
  stays active and cannot process a batch while that lock is held. Other mail
  timers are stopped after checking their state, running batches are allowed to
  finish, and their locks are held. Timers restart after the site is online.
- Post-release checks cover public routes, browser rendering, authenticated
  administration where an existing session is available, retired paths, manifests,
  PHP log deltas and mail timer state. No diagnostic email is sent.

Private hashes, dumps, copied configuration, user data, payloads and rehearsal
outputs stay outside this repository. Supply audited `<site>-hashes.json`, committed
`payload/` and framework `tests/` separately; never commit host work directories.
`refresh-stage.py` only resets an undeployed disposable candidate after a reviewed
bundle correction. Failures stop for diagnosis and preserve evidence.

Remaining PEAR database/XML compatibility libraries are intentionally retained.
This release does not mean the entire PEAR directory can be deleted.

KengaPub’s first Compose invocation printed missing database-variable interpolation
warnings. Only `web` was recreated with `--no-deps`; the database container was
unchanged. Subsequent invocations explicitly reuse the existing database
container’s values in process memory for interpolation, without logging or
persisting credentials. These were deployment-tool warnings, not PHP warnings.

## Navigation follow-up

The final backup comparison found one customised Contact link lost when
KengaSolutions updated Contact Form. `restore-navigation.php` restored the exact
backup row using dbTable in an idempotent transaction. No other public navigation
rows were missing on the six sites. Framework `e662874d9` fixes the underlying
registration behaviour: normal updates preserve existing site links and seed site
defaults only when none exist; an explicit Restore Defaults remains a reset.
The full PDO and MDB2 suites passed with real database regression coverage.

`navigation-deploy.py` applies the three committed files from
`navigation-manifest.json`, checks the baseline hashes and exact image, creates a
fresh consistent database backup, retains the previous release, then runs an
ordinary Toolbar 1.813 catalogue update while stopped. It asserts every existing
site navigation row is unchanged, recreates only web, checks readiness and resumes
workers. Both the original and follow-up manifests are checked by final-verify.
Payloads are built from Git, never copied into this repository.

After this finding, the archived prepare/deploy operators gained explicit
pre-existing site-navigation fingerprints in addition to the broad business-table
hashes. The initial rollout did not have that supplementary guard; the backup
comparison caught the omission. Subsequent releases must retain that guard.
