# Shared REST API on the existing local PHP 8.5 installation

The existing site at https://chisimba.test:8445/ch/ now runs the shared API
integration branch from `../work/rest-api-review-20261018`. The release checkout
and the application-module checkout remain on their previous branches. The
existing database volume, installation configuration and uploaded files are retained.

Start from this repository with:

```sh
./scripts/start-php85-restapi.sh
```

This combines `compose/php85.yml` with `compose/php85-restapi.yml`; it also
restarts nginx so a recreated web container does not leave a stale upstream IP.
Using the base compose file alone switches the source mounts back to the release
checkout. It does not undo the additive REST API schema or remove the database.
Do not remove database volumes when switching configurations.

The API base is `https://chisimba.test:8445/ch/api/v1/`. Use that canonical host,
not localhost: the installation redirects other hosts. Public key discovery is
`/ch/.well-known/jwks.json` and `/ch/api/v1/auth/jwks`.

Private runtime material is outside the web root and all source repositories:

- `../private-storage/php85/restapi/`: owner-only directory (0700), containing
  `jwks_private.pem` (0600), mounted at `/var/data/restapi` for the web service.
- `../private-storage/php85/restapi.env`: owner-only installation secrets.
- `../private-storage/php85/backups/before-restapi-20261018.sql`: database backup
  taken before registration and schema changes. Treat as private data.

Preserve these keys across restarts. Redis is local to the compose network, has
no published port, and persists its denylist in the `restapi_redis` volume.
It is not connected to Prince's field service. No field-service end-to-end
behaviour is claimed by these checks.

REST API registration used Module Catalogue services and its guarded schema
upgrade. Installed HTTPS checks passed: login evidence and session cookie,
password login, bearer-only identity, anonymous and cookie-only API refusal,
permission denial, refresh rotation/replay-family revocation, permission grants,
real PNG upload, live permission removal and inactive-account rejection.
The synthetic accounts, permission groups, token rows and images were removed.
The ordinary home page still returns HTTP 200.

The local harness is in `tests/restapi-local/`; it uses only synthetic
accounts, retains credentials in a private temporary container file and does not
print passwords or tokens. Run it with `tests/restapi-local/run.sh` after starting
the API overlay; its exit trap cleans up the fixture. The local development certificate is accepted only
for these local checks. Production certificate validation must remain enabled.

The tests found missing REST registration metadata and PHP 8.5 warnings in the
shared upload path; corrections are in the API integration worktree. The initial text-only SimpleBlog endpoint is available at
`POST /ch/api/v1/simpleblog/posts`; its contract is in the REST API README.
Run `tests/restapi-local/run.sh blog` for its installed HTTP checks.
The mobile client and duplicate-safe offline submission remain subsequent work. No production site changed.
