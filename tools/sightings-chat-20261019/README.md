# Sightings conversations — 19 October 2026

Extends the existing Chisimba.com sightings release: optional images, text-only
messages, quoted replies, and the shared browser chat composer. Existing photo
receipts remain compatible. Text-only records use zero image dimensions and the
SHA-256 digest of empty bytes. Reply references use the existing channel-scoped
reply table, validated against sightings in the same channel. No schema changes.

Framework 399414f91, modules 5f89f0c38, mobile f3b5304.
Messaging 2.009 and REST 1.009; other registered versions unchanged.
Seven runtime files are pinned in the manifest. Deployment is bounded to
Chisimba.com and preserves all unrelated paused module moves.

Validation: nine mobile test files, actual local API login/upload/text replies,
duplicate/conflict, invalid targets and revoked access; disposable PDO image and
reply tests including transaction rollback and course cleanup. Synthetic browser
checks text sending, quoted offline reply, reload/reconnect without duplication,
compact quote/reply controls and Help/Escape. Native phone acceptance remains for
the user. Browser uploads remain mobile-only; the browser can send text/quoted
replies and view photos.

The isolated live-data clone passed registration twice, source lint, the extended
PDO fixture and fingerprints for 123 protected tables. All test accounts and
courses in local API testing were removed. Deployment uses the established
backup, shared release lock, stop-on-failure and source verification procedure.

A first deployment preflight stopped on missing commits.json before stopping
writers or changing the current release. The exact committed source metadata was
then supplied and the deployment retried. No data rollback was needed.

Completed: Chisimba.com release
/srv/chisimba-com/releases/release-sightings-chat-20261019-145607/ch.
Backup: /srv/chisimba-com/backups/sightings-chat-20261019-145607.
Source and all 123 protected tables verified; zero new fatal errors/deprecations.
Signed-in live browser displays the existing photo, text composer and functioning
quoted-reply preview. No live test message was posted. Samsung SM-S908E install
returned Success with app data preserved; receipt records the exact APK hash.
