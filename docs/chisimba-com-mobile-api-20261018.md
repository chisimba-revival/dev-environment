# Chisimba.com mobile API — 18 October 2026

Authorised by Derek for the SimpleBlog mobile prototype. Canonical app site
address: **https://www.chisimba.com** (no `/ch`, no development port).
The apex host redirects to www with HTTP 301; API clients must use www directly
so POSTs are not redirected or changed to GET. Ordinary desktop website:
https://www.chisimba.com/ . USB forwarding is not needed for this server.
Use a Chisimba.com account; local development credentials are separate.

## Release

The tested shared framework API integration at `4a02aad40` was deployed as a
52-path runtime delta over the existing `6f3acbca2` release. Every affected live
file matched its baseline or target hash before deployment, and every installed
path matched the final manifest. Application modules were untouched. The source
branch remains `integrate/rest-api-current-runtime-20261018`; this deployment
does not merge the pending upstream PR or establish Prince's field-service E2E.

Release: `/srv/chisimba-com/releases/release-restapi-20261018-113752/ch`.
Previous release: `/srv/chisimba-com/releases/release-shared-20261017-134642/ch`.
Verified database dump, configuration archive and original Compose definition:
`/srv/chisimba-com/backups/restapi-20261018-113752/` (private).
Current source remains selected through `/srv/chisimba-com/app/current`.

Normal Module Catalogue registration and the shared guarded REST schema upgrade
were run. New API tables are additive. Existing site data, upload mounts,
configuration, database container and other hosted sites were preserved.

The existing web container now mounts an Apache API rewrite configuration,
private key directory `/srv/chisimba-com/shared/restapi` and secret environment
file `/srv/chisimba-com/shared/secrets/restapi.env`. Neither secret contents nor
private key bytes are stored in this repository. Key directory is 0700, key
0600, owned by www-data. Preserve these across future releases.
Redis 7.4 runs on the site's Compose network with AOF storage and no published
port. There is no field-service deployment or integration on this site.

## Verification

- Repeated local installed SimpleBlog HTTP/security suite passed before rollout.
- All changed assembled PHP files passed lint on the production PHP image.
- Website and web login return 200 over normally verified public HTTPS.
- API login and public JWKS return 200; JWKS contains no private RSA fields.
- Synthetic account: login succeeds, anonymous and unprivileged posting fail,
  granted personal publishing creates a private draft, anonymous readers cannot
  view it, and removing permission immediately prevents posting.
- Synthetic account, group, token rows and private post removed after testing.
- Web/database containers healthy; source hashes and private key mode verified.

The first apex-host test exposed its 301 redirect; corrected the client test
address to www and repeated the entire journey successfully. No public test post
was published. Scripts and source hash manifest are in
`tools/restapi-chisimba-20261018/`. The deployment script refuses a second run;
inspect the release record before any recovery or new release.

If code recovery is required, retain the new private keys and secrets, restore
the previous source symlink and backed-up Compose file, and recreate only web
with the production environment file. Additive API tables can remain. Never
restore the database dump blindly over subsequent user data.

## Next phone check

Sign out of the local server in Chisimba Test. Enter `https://www.chisimba.com`,
sign in using that site's account, start a **new draft**, and send a private
post. Previously attempted local drafts remain bound to their original server
and account. Then try offline writing and reconnect over Wi-Fi/mobile data.
Automatic sync, idempotent retries, branding discovery and persistent secure
login remain future work.
