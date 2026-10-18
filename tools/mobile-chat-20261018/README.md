# Chisimba.com mobile chat release — 18 October 2026

Authorised to finish mobile chat, deploy it, update the phone and post a student
question for Derek to answer. Baselines: modules4021cd481, framework69b027de0.
Released source: modules3a5dcdd16, framework379e83de4. The manifest contains only
messaging, the announcement scope filter, REST adapter and shared chat skin.
Retired executable chat files are removed from the new release; originals remain
in the prior release and source archive. Existing module moves were untouched.

The first pre-switch attempt stopped because Notifications was not registered.
The previous release remained active. The registration script now installs the
existing Notifications dependency normally, followed by Announcements, Messaging
and REST API. No notifications are sent by this setup.

Live release: `/srv/chisimba-com/releases/release-mobile-chat-20261018-140017/ch`.
Backup: `/srv/chisimba-com/backups/mobile-chat-20261018-140017/`.
Previous release: `release-mobile-categories-20261018-122847`.
Normal fresh registration succeeded. Source hash checks, copied-release PHP lint,
database backup, atomic link switch and container recreation were performed.
No other sites changed. Payload is generated from the recorded source revisions
and is kept in the host staging directory; secrets are not part of the bundle.

Local API checks passed for authorised context list, send, exact duplicate,
changed-body conflict, unsupported media, history/names, foreign context, future
read and revoked bearer reads/retries. Mobile state tests passed for restart,
account/server/context separation and matching receipt requirements. Existing
mobile suites pass. Local fixtures were cleaned.

`start-course.php` uses Derek's canonical identity to start the existing private
gettingstarted conversation and enable its navigation entry. `post-question.py`
uses the private local test account file, signs in over HTTPS, posts exactly one
deterministically identified question through the ordinary web form, and checks
the same message through the phone API. It prints no credentials. The question
is deliberately retained for Derek's phone reply. Live anonymous history is401,
recent PHP diagnostics and REST server errors are0. Browser shows the student
question in the correct current course. Android debug build/install succeeded;
actual phone reply/offline rehearsal is pending with Derek.
