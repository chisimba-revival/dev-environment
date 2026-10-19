# Server chat refinement — Chisimba.com, 19 October 2026

Messaging 2.003 plus shared root-skin chat workspace styles. Registered one new
transactional deliveries table through Module Catalogue; preserved all messages.
Drift-checked baseline: modules 5662e10bb, framework f217071c6.
Initial release: release-server-chat-20261019-085705/ch.
Backup: /srv/chisimba-com/backups/server-chat-20261019-085705/.
Follow-up same-origin request fix: ../server-chat-origin-20261019/.

Final sources pushed to existing branches: modules 2e790e905 on
release/consolidation-20260930; framework 8db5f86f6 on
integrate/rest-api-current-runtime-20261018.

Local validation: PHP lint, policy test, web HTTP permissions/CSRF/scope/revocation,
existing mobile API tests, six chat client cases, monotonic receipt positions,
self-read exclusion, delivery and read ticks. Browser tested in-place send and
incoming fixture replies without reload, draft and scroll preservation, new-message
jump, blue read tick, Help/full guide/Escape and responsive 390px layout. Disposable
records and test account removed; cleanup verified. Live page verified Course label,
sidebar, receipt icons, final client asset and enabled composer with no status error.
No live conversation messages created during release verification.

The legacy catalogue creates non-unique indexes for these definitions. Receipt
persistence now uses the existing channel lock and monotonic updates, with MAX reads
for historical duplicate positions. It does not delete historical receipt data.
