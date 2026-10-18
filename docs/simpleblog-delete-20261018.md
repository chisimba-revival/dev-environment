# SimpleBlog deletion visibility — 18 October 2026

Deletion already existed, but its control was hidden in a collapsed section at the bottom of the saved preview. Modules commit `4f72adae9` (SimpleBlog 0.077) exposes Delete post beside Edit in the post lists, editor and saved preview. A dedicated confirmation names the post, identifies its scope, explains permanent deletion and provides Cancel. Shared UI, icons, translated text and contextual help are used.

Existing server-side permission checks, POST-only deletion, CSRF protection and transactional publishing service remain in effect. The confirmation page is also permission protected. No schema changes were required.

## Validation

PHP lint and SimpleBlog publishing tests passed locally. Local and public HTTP checks covered visible links, named confirmation, Cancel, rejected GET deletion, rejected invalid CSRF, permission revocation after confirmation, anonymous draft privacy and successful authorised deletion. Disposable private test data and accounts were cleaned up. Browser checks verified the published list, preview, confirmation, contextual help and keyboard Cancel. At 390px width the action controls fit and remain equal height. Existing user posts were retained. Final production log check found no PHP warning, deprecated, fatal or uncaught diagnostics in the sampled five-minute window.

## Deployment scope and recovery

Only Chisimba.com was deployed. The other five sites remain unchanged.

- Framework: `fe55c81b4` (unchanged).
- Modules delta: `3c5a448c1` to `4f72adae9`; pushed to `release/consolidation-20260930`.
- Current: `/srv/chisimba-com/releases/release-simpleblog-delete-20261018-121037/ch`.
- Previous: `/srv/chisimba-com/releases/release-branding-20261018-115703/ch`.
- Database/source deployment record and compose backup: `/srv/chisimba-com/backups/simpleblog-delete-20261018-121037/`.
- Deployment record status: `online-verified`.

The guarded deployment verifies before/after hashes, retains the previous release, backs up the database, runs normal Module Catalogue registration for SimpleBlog language/version updates, switches the current symlink and recreates only the web service. Source rollback is possible using the retained release; additive registration changes do not require database rollback. The scripts in `tools/simpleblog-delete-20261018/` document this specific deployment and are not a general release runner.
