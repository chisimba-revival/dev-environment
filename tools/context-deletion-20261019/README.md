# Chisimba.com course deletion release — 2026-10-19

Published framework `d05a19ac2` on `integrate/rest-api-current-runtime-20261018`
and modules `9a89992d7` on `release/consolidation-20260930` to GitHub.
User explicitly authorised publication and deployment in this conversation.

Deployed `/srv/chisimba-com/releases/release-context-deletion-20261019-132743/ch`.
Previous release: `/srv/chisimba-com/releases/release-chat-usability-20261019-100052/ch`.
Database/compose backup: `/srv/chisimba-com/backups/context-deletion-20261019-132743/`.

The bundle checks all 17 source hashes against the previous commits before
copying into a new release, lints PHP, backs up the database, uses normal Module
Catalogue registration and verifies InnoDB for every cleanup participant table.
The source symlink changes only after those checks pass; web container recreated.
No destructive production tests, course deletions or test messages were performed.

Validation: all 17 deployed hashes match; public HTTPS 200; running web container;
signed-in browser verified discussion history and the course announcement channel.
PHP log contains legacy blog-block configData dynamic-property deprecations,
not errors from the deletion changes. These are separate maintenance debt.

The deploy script is single-use at the named staging path. Remote deployed.json
and the backup release.json now record `validated`. Database registration preceded
the source switch; source rollback alone does not restore registration metadata.
The database backup is available for a coordinated rollback if required.

The detailed fix/test contract is in framework
`docs/dependencies/context-deletion-20261019.md`. Local regression tests and the
three disposable-scope repairs were completed before this production release.
