# AI chapter-quiz worker production installation

Whole-course quiz generation is deliberately not performed inside a browser
request. The MCQ Tests module creates a durable job in
`tbl_mcq_chapter_quiz_jobs`; this worker processes the queued chapters and saves
each generated preview before continuing. Nginx and PHP request timeouts must
not be increased to make quiz generation work.

## Prerequisites

- Install or update the MCQ Tests module to version 4.174 or later. Confirm that
  `tbl_mcq_chapter_quiz_jobs` exists.
- Configure the shared AI service and confirm that `aiservice::isAvailable()`
  returns true through the normal MCQ Tests interface.
- Keep the PHP application container running under a stable Compose container
  name.
- The account owning the cron entry must be allowed to run `docker exec` against
  that container. Do not place an AI provider key in the crontab; the worker
  reads Chisimba's normal protected configuration inside the container.

## Find the container and worker path

List the running containers:

```sh
docker ps --format '{{.Names}}'
```

For a release assembled from the Chisimba framework and modules repositories,
the usual path is:

```text
/var/www/html/packages/mcqtests/scripts/run_chapter_quiz_worker.php
```

Some development layouts use:

```text
/var/www/html/ch/modules/mcqtests/scripts/run_chapter_quiz_worker.php
```

Verify the chosen path before adding the schedule:

```sh
docker exec YOUR_WEB_CONTAINER test -f \
  /var/www/html/packages/mcqtests/scripts/run_chapter_quiz_worker.php
```

## Cron installation

Edit the crontab belonging to the deployment account:

```sh
crontab -e
```

Add one line, replacing the container name and application paths where needed:

```cron
* * * * * /usr/bin/flock -n /srv/chisimba/ai-worker.lock /bin/bash -o pipefail -c '/usr/bin/docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/mcqtests/scripts/run_chapter_quiz_worker.php 20 2>&1 | /usr/bin/grep -E ^\{.selected. | /usr/bin/tail -n 1' >> /srv/chisimba/logs/ai-worker.log 2>&1
```

Create `/srv/chisimba/logs` first and ensure the deployment account can write to
it. The lock file prevents a second cron invocation from overlapping a worker
that is still waiting for the AI provider. The final argument, `20`, is the
maximum number of chapter steps processed in one run; supported values are
1–50.

The output filter is intentional. A legacy installation can emit many PHP 8.5
compatibility notices during command-line bootstrap. The filter retains the
worker's compact JSON status without allowing those notices to grow the cron log
by hundreds of kilobytes per minute.

List the installed entry with:

```sh
crontab -l
```

Run the worker once manually before relying on cron:

```sh
docker exec YOUR_WEB_CONTAINER php \
  /var/www/html/packages/mcqtests/scripts/run_chapter_quiz_worker.php 20 \
  2>&1 | grep -E '^\{"selected":'
```

An idle, healthy worker reports:

```json
{"selected":0,"completed":0}
```

After the next minute, inspect the scheduled-run log:

```sh
tail /srv/chisimba/logs/ai-worker.log
```

## Systemd alternative

On hosts where the installer can use `sudo`, the supplied systemd timer is the
preferred alternative because it provides service status and journal history:

```sh
sudo ./scripts/install-ai-worker-production.sh \
  --container YOUR_WEB_CONTAINER \
  --worker-path /var/www/html/packages/mcqtests/scripts/run_chapter_quiz_worker.php \
  --interval 10s
```

Install either cron or the systemd timer, not both. Check systemd operation with:

```sh
systemctl status chisimba-ai-worker.timer
journalctl -u chisimba-ai-worker.service
```

## Operational behaviour

- A browser request only creates the durable job and opens its progress page.
- The worker saves completed chapters individually and resumes queued work after
  interruption.
- A run is bounded, and the host lock prevents overlapping runs.
- Generated questions remain previews until the course owner reviews and creates
  the quizzes.
- The normal AI request audit records provider success, duration and token usage;
  prompts and generated content are not stored in that audit table.
- Do not solve a worker failure by extending nginx timeouts. Check the worker
  log, the job status, AI configuration and provider audit instead.

## Removal

For cron, remove only the line containing `run_chapter_quiz_worker.php` using
`crontab -e`. Removing the schedule does not delete queued jobs or generated
previews; reinstalling the worker allows them to continue.
