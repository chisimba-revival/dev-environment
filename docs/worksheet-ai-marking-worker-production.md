# Worksheet AI marking worker production installation

AI-assisted Worksheet marking is deliberately performed outside the browser
request. A lecturer queues a durable job in
`tbl_worksheet_ai_marking_jobs`; the worker prepares editable marks and
feedback, and the lecturer remains responsible for reviewing and saving the
final result. Do not increase nginx or PHP timeouts to run this work inline.

## Prerequisites

- Install or update Online Worksheets to version 1.335 or later and confirm
  that `tbl_worksheet_ai_marking_jobs` exists.
- Configure the shared AI module and confirm `aiservice::isAvailable()` is true.
- Keep the PHP application container running under a stable name.
- Run the worker as an account allowed to use `docker exec`. Provider keys stay
  in Chisimba's protected configuration and must not be copied into cron.

The normal packaged worker path is:

```text
/var/www/html/packages/worksheet/scripts/run_ai_marking_worker.php
```

Verify it and run an idle smoke test:

```sh
docker exec YOUR_WEB_CONTAINER test -f /var/www/html/packages/worksheet/scripts/run_ai_marking_worker.php
docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/worksheet/scripts/run_ai_marking_worker.php 5 2>&1 | grep -E '^\{"selected":'
```

An idle worker reports:

```json
{"selected":0,"completed":0}
```

## Cron installation

Create a writable log directory, then add this entry to the deployment
account's crontab. Use a separate lock from the chapter-quiz worker so the two
queues remain independently observable.

```cron
* * * * * /usr/bin/flock -n /srv/chisimba/worksheet-ai-worker.lock /bin/bash -o pipefail -c '/usr/bin/docker exec YOUR_WEB_CONTAINER php /var/www/html/packages/worksheet/scripts/run_ai_marking_worker.php 5 2>&1 | /usr/bin/grep -E ^\{.selected. | /usr/bin/tail -n 1' >> /srv/chisimba/logs/worksheet-ai-worker.log 2>&1
```

The final argument is the maximum jobs processed in one run and must be from 1
to 20. The lock prevents overlapping invocations. The output filter retains the
compact JSON health line without filling the log with legacy PHP compatibility
notices.

## Operational checks

```sh
crontab -l
tail /srv/chisimba/logs/worksheet-ai-worker.log
```

- The browser only enqueues work and displays a refreshable progress card.
- Provider failure leaves the original manual marking workflow available.
- Suggestions never write marks directly. Only the lecturer's **Save marks**
  action persists the reviewed mark and feedback.
- Saved marks delete the transient suggestion job and its generated content.
- Normal AI audit data records provider, duration, token use and success without
  storing the learner response in the audit table.

To remove the worker, delete only the crontab line containing
`run_ai_marking_worker.php`. Queued jobs remain recoverable if the worker is
reinstalled.
