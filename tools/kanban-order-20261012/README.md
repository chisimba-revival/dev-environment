# KengaLearn Kanban ordering release — 12 October 2026

Completed on KengaLearn only. Kanban 0.146; framework `f5ddd8fb4`,
modules `b1d15c6b5`, both on `release/consolidation-20260930`.

Tasks default to oldest creation date first, with stable ID ties for historical
same-second timestamps. Legacy seconds/milliseconds sort values no longer cause
unpredictable ordering. Explicit moves persist atomic negative ranks through
dbTable; newly created tasks append. No database schema changes.

Native drag supports insertion within and between columns, with a shared skin
drop marker. Compact up/down buttons support keyboard/touch. Concurrent stale
moves are rejected rather than overwriting another window's order.

## Validation completed

- Full PDO and MDB2 suites, including 107 installer definitions.
- Kanban ordering controller permissions/CSRF/conflicts/errors; repository
  chronology, insertion, foreign anchors, stale orders, transaction rollback,
  forced storage failure, and rapid creation.
- Existing task creation, contract, subtask edit and recovery checks.
- Local real-browser drag within/between columns, reload persistence, keyboard,
  stale two-tab conflict, Help, and a 390px iframe displaying the real local app.
  Disposable board/tasks and local preview removed afterward.
- Exact production image + staged source against an isolated database clone:
  upgrade and repeat passed; all 171 protected business tables unchanged.
  Initial full menu-row hash failed because catalogue registration regenerates
  internal menu IDs. Final guard verifies every menu field except generated IDs,
  plus complete exact `site_` navigation rows and all four Kanban tables.
- Live catalogue update preserved all Kanban data and navigation semantics.
  Authenticated EcoTraining board rendering verified without moving real tasks.
  Browser console clean; final manifest/image/timer/PHP diagnostic checks passed.

## Release and recovery evidence

Remote operator directory: `/srv/kengalearn/kanban-order-20261012`.
Backup: `/srv/kengalearn/backups/kanban-order-20261012-111747`.
Release: `/srv/kengalearn/releases/release-kanban-order-20261012-111747/ch`.
Previous: `/srv/kengalearn/releases/release-navigation-20261012-085157/ch`.
Image retained: `kengalearn/pdo:20261011`.

Backup contains verified database gzip, compose file, log offsets, upgrade log
and release receipt. It does not create a new upload-file backup; this release
changes no user files. Existing file backups remain in place. A brief web stop
and worker locks protected the database snapshot/catalogue update. Mail timers
remain active. Never restore the database over newer user edits without review.

These are historical, guarded operator scripts, not a generic auto-updater.
`prepare.py` expects private payload files matching `manifest.json` and the
specified original release; rerunning deployment after completion fails drift
checks. Private database copies, configs, logs and screenshot are not committed.
Local diagnostic evidence is under `work/kanban-order-20261012` in the workspace.
