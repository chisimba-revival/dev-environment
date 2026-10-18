# Compact mobile header terminology release

Chisimba.com only, 18 October 2026. Framework f217071c6, REST API 1.005.
Additive `contextLabel` in messaging contexts resolves the shared messaging view's
systext-aware language label. No schema or permissions changes. Mobile consumes
and caches it per account/server. Existing clients remain compatible.

Deployment checked baseline hashes against framework 379e83de4, copied the prior
release, backed up the database and used normal REST API registration before
switching the release. Backup: /srv/chisimba-com/backups/mobile-header-20261018-142841/.
Previous release: release-mobile-chat-20261018-140017/ch.
Current release: release-mobile-header-20261018-142841/ch.

Validation: local PHP lint and configured Class label; authenticated synthetic
student read confirms Course and existing course membership on Chisimba.com.
No conversation messages were created or changed for this validation.
