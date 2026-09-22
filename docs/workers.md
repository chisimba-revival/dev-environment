# Chisimba background workers: installation checklist

Deploying the web application does not install its host schedules. Use this guide
after installing/updating modules through Module Catalogue. Schedule only the
features enabled on your site, and use **one scheduler per queue**.

## Worker inventory

Paths below are relative to the installed application root. `packages` is the
usual application-module directory; verify your installation before using a path.

| Worker | Needed for | PHP entry point | Suggested schedule and batch | Setup |
| --- | --- | --- | --- | --- |
| Communications | Queued email, including registration, recovery and reminders | `core_modules/communications/scripts/run_outbox_worker.php` | Every minute, 20 messages | [Communications](communications-worker-production.md) |
| Registration cleanup | Automatic expiry and retention of unconfirmed registrations | `packages/registration-service/scripts/run_registration_cleanup.php` | Daily, bounded to 200 candidates; `--apply` | [Registration cleanup](registration-cleanup-worker-production.md) |
| Chapter quizzes | Queued whole-course quiz generation | `packages/mcqtests/scripts/run_chapter_quiz_worker.php` | Every minute, 20 steps (1–50) | [Chapter quizzes](ai-chapter-quiz-worker-production.md) |
| Worksheet marking | Queued AI marking suggestions | `packages/worksheet/scripts/run_ai_marking_worker.php` | Every minute, 5 jobs (1–20) | [Worksheet marking](worksheet-ai-marking-worker-production.md) |
| Essay marking | Queued AI marking suggestions | `packages/essay/scripts/run_ai_marking_worker.php` | Every minute, 5 jobs (1–20) | AI options below |
| Discussion marking | Queued AI marking suggestions | `packages/discussion/scripts/run_ai_marking_worker.php` | Every minute, 5 jobs (1–20) | AI options below |

Password recovery requires Communications even when public registration is off.
Contact-form SMTP and queued account-mail settings are separate; configure and
verify both when installing a public publishing site.

The Communications entry point also runs due Live Class reminders when `liveclass`
is installed. Do not create a second reminder schedule for that service.
Registration cleanup is separate from Communications and does not send email.
It has no AI or Cloudflare dependency. AI workers can incur provider charges when
processing queued jobs; a manual invocation is not necessarily an idle test.

## Host backups and restore rehearsals

The separate [automatic backup installation and recovery guide](../../shellscripts/backup-service/README.md)
covers source capture, encrypted cross-server storage, nightly backups, hourly
health alerts, weekly retention/integrity checks and monthly isolated restore
rehearsals. Install and verify all four backup timers on the receiving server;
application worker installers do not enable them. Keep the independent recovery
password safe. The initial implementation protects KengaLearn; other sites need
separate tested configuration and schedules.

## Establish the actual deployment paths

These examples assume a Linux Docker host with cron/systemd and `flock`:

```sh
docker ps --format '{{.Names}}'
docker exec YOUR_WEB_CONTAINER test -f /var/www/html/index.php
docker exec YOUR_WEB_CONTAINER test -f /var/www/html/packages/registration-service/scripts/run_registration_cleanup.php
```

Replace `YOUR_WEB_CONTAINER` and paths throughout the examples. Common application
roots are `/var/www/html` and `/var/www/html/ch`; some installations use `modules`
instead of `packages`. Use the same PHP runtime, database, installation key and
protected configuration as the web application. Workers execute **inside** the
application container, while scheduling and locks live on the host.

Keep the container name stable across releases. The scheduling account must have
Docker permission and write access to its lock/log directory; Docker access is
privileged and belongs only to trusted deployment administrators. Keep secrets
in the application configuration, never in schedules. On a native installation,
replace `docker exec ... php` with the installation's PHP CLI and actual script
path, running as its application account with the same configuration access.

## Install Communications and registration cleanup

Follow their linked guides independently. Communications has a supplied systemd
installer; registration cleanup has a preview-first cron recipe and a systemd
alternative. Do not assume the Communications or AI installer enables cleanup.
Keep `REGISTRATION_AUTO_CLEANUP=0` until the cleanup preview is reviewed and its
schedule is ready. Existing sites must retain their current schedules unless
deliberately migrating them; check both systemd and cron before adding anything.

## Choose one AI scheduling approach

**Combined helper:** the companion `shellscripts/run-chisimba-ai-workers.sh` runs
Worksheet, Essay and chapter-quiz queues sequentially. It requires all three
entry points and has a read-only `check` command. Follow the
[shared AI workers administrator guide](../../chisimba-info/user-guides/Shared_AI_Service_Workers_Administrator_Guide.md).
It does **not** run Discussion marking, Communications or registration cleanup.
Add a separate Discussion schedule if that feature is enabled.

**Individual workers:** use the linked chapter-quiz and Worksheet guides, or the
following deployment-account crontab entries for Essay and Discussion. Install
only the entries for enabled modules, after verifying their scripts and queue
schema. Configure the shared AI service first. Create `/srv/chisimba/logs` and
ensure it and `/srv/chisimba` are writable by the scheduling account:

```cron
* * * * * /usr/bin/flock -n /srv/chisimba/essay-ai-worker.lock /usr/bin/docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/essay/scripts/run_ai_marking_worker.php 5 >> /srv/chisimba/logs/essay-ai-worker.log 2>&1
* * * * * /usr/bin/flock -n /srv/chisimba/discussion-ai-worker.lock /usr/bin/docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/discussion/scripts/run_ai_marking_worker.php 5 >> /srv/chisimba/logs/discussion-ai-worker.log 2>&1
```

These are user-crontab lines (`crontab -e`), with no username field. Files in
`/etc/cron.d` instead need a scheduling username after the five time fields.
Each queue gets its own lock. Do not run the combined helper and individual
schedules for the same queues. The older `chisimba-ai-worker.timer` is a
**chapter-quiz-only** timer, despite its general name.

## Verify the complete installation

1. Check each selected PHP entry point exists and its module update completed.
2. Inventory active schedules: `crontab -l`, the relevant `/etc/cron.d` entries,
   and `systemctl list-timers --all`. User systemd timers may also exist.
3. Preview registration cleanup before enabling it. For email/AI, first check
   queue contents: running those workers can send real mail or use paid AI.
4. Run the selected worker under the same account and command used by its
   scheduler, when the queued work is intended to run. Inspect exit status and
   the JSON summary, including `failed`; a successful process exit alone does
   not establish that every job succeeded.
5. Verify a subsequent **scheduled** run in its log/journal. An idle summary
   with zero selected/completed jobs is healthy. A configuration switch alone
   does not prove that a scheduler is running.
6. Confirm the relevant UI: My Administration's mail monitor, Registration
   protection's preview, and progress/suggestions in enabled AI features.

Use `journalctl -u SERVICE_NAME` for systemd workers and the configured files for
cron workers. Retain failure diagnostics and rotate logs with the host's usual
policy; do not copy provider credentials, answers or generated feedback into
operational reports. Registration cleanup logs contain counts, not personal data.

## Updates, stopping and recovery

After each deployment, recheck container names, paths, module versions and
scheduled-run logs. Pause relevant schedules during database restore or a release
switch. Remove/comment only the relevant cron entry, or stop/disable that worker's
timer, to stop future runs; this does not necessarily stop an already running job.
Avoid overlapping invocations or deleting a held lock file.

For registration cleanup, also set `REGISTRATION_AUTO_CLEANUP=0`. Stopping the
worker does not undo expiry or redaction. For email and AI, retain queued records
while diagnosing failures; do not delete queues as a substitute for recovery.
Use backed-up data and the owning service's recovery procedure when required.
