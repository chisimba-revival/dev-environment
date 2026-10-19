# Quoted replies — Chisimba.com, 19 October 2026

Source: modules a71592119 (messaging 2.004); framework ab7731c02 (REST API 1.006
and shared quote styling). Existing branches pushed. Drift-checked baselines are
modules 2e790e905 and framework e41841b18. Deployment creates a copied release,
backs up the database, registers messaging/restapi normally, and switches atomically.
The registered replies table holds references only; existing messages remain intact.
The deployment record under staging/chat-replies-20261019/deployed.json holds paths.

Reply author and excerpt come from the canonical same-channel post, never client
quote text. References and new posts are written in the same transaction. Retry
comparison includes the reply target. Quotes use at most 300 characters plus an
ellipsis and do not recursively include earlier quotes or add nested message indents.
The browser preserves selected quotes on errors and typed text when cancelling.

Validation: changed PHP lint, eight JS regression cases, quoted reply/duplicate and
cross-channel service cases, existing API tests plus optional reply references,
web permissions/CSRF/escaping and quote recovery. Browser tested selection, cancel
with text retained, successful quoted send, contextual Help and 390px overflow.
Disposable local account/conversation/quotes removed and cleanup verified. No live
messages were posted for testing. The installed Android UI is unchanged; its current
API calls remain compatible with the additive reply contract.

Deployed release: `/srv/chisimba-com/releases/release-chat-replies-20261019-092556/ch`.
Backup: `/srv/chisimba-com/backups/chat-replies-20261019-092556/`.
Live browser verified Reply selection shows the original author and excerpt, and
Cancel reply clears the selection. No live test message was submitted.
