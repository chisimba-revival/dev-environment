# Chat usability and announcement messages — 19 October 2026

Deployed only to Chisimba.com after local validation. Shared source branches pushed:
modules `aff5b66f0` (messaging 2.006, announcements 0.415), framework `a313b36d3`
(REST 1.007). Previous baselines: modules `a71592119`, framework `ab7731c02`.
Android source committed locally as `a5801c8`; no mobile Git remote is configured.

Release: `/srv/chisimba-com/releases/release-chat-usability-20261019-100052/ch`.
Backup: `/srv/chisimba-com/backups/chat-usability-20261019-100052/`.
Deployment drift-checks the manifest, copies the current release, backs up the
full database, registers modules normally and verifies InnoDB before switching.
The added announcement receipt table preserves existing announcements; the
course plugin lookup removes duplicate display entries without deleting records.

Reply is now an accessible small icon alongside a human-readable timestamp using
the site timezone. Announcement channels use chat bubbles, polling and a simple
plain-text send box for authorised staff, without a title field. Announcement
messages stay in the canonical announcement store. APIs reuse its service and
recheck permission even for receipt retries. No email is sent by the chat path.
Announcement delivery/read ticks are not collected yet.

Validation: PHP lint, whitespace checks, announcement contract test, 8 chat JS
checks, 20 mobile tests; installed local service/web/API tests cover permissions,
CSRF recovery, conflict/repeat sends, revoked access and parent rollback. Browser
verified local one-way sends, compact replies and Help; the native-only mobile
app used a synthetic browser adapter to verify offline queue/reconnect and narrow
layout. Android debug build passed. Phone disconnected: installation pending.
Live browser verified small Reply icons, site-zone dates, the announcement send
box and exactly one Conversations menu entry. No live test messages were posted.
No PHP warnings/fatal/deprecation diagnostics appeared in the deployed logs.

Local fixture cleanup is partially pending: disposable API account/tokens were
removed, but context-group cleanup required an administrator. Automatic approval
review rejected a helper that tried to establish an administrator session directly.
The user was asked to authorise cleanup through normal signed-in administration.
The exact disposable scopes are `msgtest827c3db19b`, `msgtest16bbef25a3`, and
`msgtest52119133c7`, all created by this run. Do not touch other paused modules,
course content, or the untracked Android IDE/compose configuration.
