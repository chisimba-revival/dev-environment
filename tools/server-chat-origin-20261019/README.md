# Canonical-host follow-up

Final Chisimba.com release: release-server-chat-origin-20261019-085844/ch.
Backup: /srv/chisimba-com/backups/server-chat-origin-20261019-085844/.
Previous: release-server-chat-20261019-085705/ch.
Modules 2e790e905; framework 8db5f86f6. Only the chat controller asset version and
client request URL handling changed. Ajax uses relative path/query on the browser's
authenticated origin even when the site generates links to its canonical host alias.
Six client regressions passed. Live DOM verified conversation.js?v=2.003.1,
empty status and enabled send control. See ../server-chat-20261019/README.md.
