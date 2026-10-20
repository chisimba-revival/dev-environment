# Chisimba Video Service

Reusable hosted-video library and playback. Mux is the first connector. CPD is a
course configuration, not a module: ContextContent owns lesson attachments and
combines required viewing with its existing MCQ chapter gates.

## Installation and configuration

Install **Video Service** and update **Context Content** through Module Catalogue.
Both installation hooks must run, including on updates: they create checked unique
constraints. Calling `modulesadmin::installModule()` from a release script alone
does not invoke these hooks; also use the engine's `getPatchObject()` and run its
`postinstall()` method after successful registration. Repeating the hooks is safe.

In the existing **Sysconfig editor**, select `video-service` and enter:

| Parameter | Value |
| --- | --- |
| `VIDEO_PUBLIC_URL` | Canonical public HTTPS application URL ending in `index.php`, without a query string; for example `https://example.org/ch/index.php` |
| `VIDEO_MUX_TOKEN_ID` | Mux Video API access-token ID for the selected environment |
| `VIDEO_MUX_TOKEN_SECRET` | Its token secret, with Video read/write permissions |
| `VIDEO_MUX_SIGNING_KEY_ID` | Playback signing-key ID from the same environment |
| `VIDEO_MUX_SIGNING_PRIVATE_KEY` | Associated private key, base64 as supplied by Mux or PEM |
| `VIDEO_MUX_WEBHOOK_SECRET` | Signing secret of this application's Mux webhook |
| `VIDEO_DEFAULT_CONFIGURATION` | Leave as `mux-default` initially |
| `VIDEO_MUX_ADDITIONAL_PROFILES` | Leave as `{}` initially |

An environment ID or Mux Data environment key is not the Video API token pair.
Keep secrets in server-side Sysconfig, never in course content, source commits,
logs or screenshots. Access to Sysconfig and database backups must be restricted
to trusted administrators, as with existing provider credentials.

Configure a Mux webhook using the same environment and this URL:

```text
https://example.org/ch/index.php?module=video-service&action=webhook&configuration=mux-default
```

Subscribe to video upload and video asset events, including text-track changes.
The URL must be publicly reachable over HTTPS. Local development can verify signed
fixtures without publishing the local server. Do not point production callbacks
at a development environment.

A video retains its provider and configuration name. Credential rotation within
the same Mux environment can update the normal fields. To move **new uploads** to
a different environment, add a named object to `VIDEO_MUX_ADDITIONAL_PROFILES`
and change `VIDEO_DEFAULT_CONFIGURATION` to that name. Preserve old profiles.
Each named profile has `provider: "mux"`, `token_id`, `token_secret`,
`signing_key_id`, `signing_private_key`, and `webhook_secret`. Use its name in its
own webhook URL. Never repoint `mux-default` at a different environment while
existing videos still use it.

## Authoring and playback

From a lesson, use **Manage lesson videos**. The library is scoped to the current
course. Site administrators also have a site library. Course managers can upload,
edit metadata and choose an existing lesson to attach a video. A lesson supports
one managed video attachment alongside its existing content. To replace it,
remove the old attachment first. Detaching does not delete the hosted video.

Upload bytes go directly from the browser to Mux. UpChunk retries transient failures
and offers pause/resume while the page remains open. Upload and processing are
separate states. Refresh processing status after upload. An uncertain authorisation
must be reconciled before creating another attempt; repeating the same authorisation
request cannot create another provider upload. Browser-restart upload resume and
automatic recovery of an upload URL after a lost authorisation response are not
implemented. Such uncertain attempts remain visible for administrator investigation.

Add UTF-8 WebVTT or SRT captions (up to 1 MiB). Caption files are held temporarily
in Chisimba's database for Mux to fetch through a random, expiring capability URL.
They expire after 24 hours and are cleaned by reconciliation. They are not original
video copies or an archive. Caption processing status is shown separately.

Playback uses expiring signed Mux tokens, including thumbnail/storyboard tokens.
Chisimba checks current lesson ownership, course publication, membership, visibility
and preceding stage gates whenever it grants or renews playback. Managers can preview.
Anonymous course playback is deliberately not enabled. Tokens expire after 15 minutes;
revocation stops new grants immediately but cannot revoke an already issued token.

Resume positions and watched intervals are stored by Chisimba user, consumer
reference and Chisimba video ID. Reports every ten seconds merge overlapping ranges;
seeks, duplicate viewing and long gaps do not earn duplicate credit. They are playback
evidence, not proof of attention. Refresh lesson progress after satisfying a requirement
to update the existing chapter-navigation controls.

A required percentage of **0** means optional viewing. A positive value adds a video
requirement to that chapter in a course using gated progression. If an MCQ gate is
also configured, both must pass. Video-only chapter gates are supported. The course
completion service continues to own the overall completion decision. Other consumers
can add a trusted adapter without knowing Mux IDs.

Deletion requires explicit confirmation and is blocked while attachments exist.
Once requested, new playback is blocked. Provider errors leave a retryable pending
deletion. The local tombstone and learning records survive hosted deletion. Late
callbacks cannot resurrect the video. Original files on the author's computer or
external backup are never touched. No R2 or duplicate cloud archive is used.

## Recovery worker

Run this bounded CLI operation every few minutes using the installation's existing
worker scheduler and PHP runtime, as the application user:

```sh
php packages/video-service/scripts/reconcile.php /absolute/chisimba/root
```

It checks at most 50 pending uploads/assets/deletions per invocation and removes
expired caption-transfer records. It emits only counts and returns nonzero when
operations fail. No schedule is installed automatically. Missing credentials do not
trigger paid requests. Monitor failed runs through the site's existing worker process.

Webhook signatures use the raw body and a five-minute timestamp tolerance. Events
are deduplicated under database coordination, with acknowledgement only after the
transaction commits. Current provider metadata resolves out-of-order callbacks.
Provider/configuration matching prevents cross-environment updates. Keep the host
clock synchronised. Set the web server's logging policy to omit capability-token
query strings, including caption-transfer URLs.

## Validation

Offline, no credentials or network:

```sh
php video-service/tests/provider_progress_test.php
php video-service/tests/course_policy_test.php
```

Against an explicitly selected local/disposable installed runtime:

```sh
CHISIMBA_VIDEO_TEST=1 CHISIMBA_TEST_ROOT=/absolute/chisimba/root \
  php packages/video-service/tests/pdo_integration_test.php
```

The integration test inserts synthetic rows and removes them in `finally`. It
covers rollback, idempotent upload authorisation, signed/duplicate callbacks,
revoked access, resume persistence, deletion safeguards and late callbacks.

Before a production release, populate a test Mux environment and verify a short
synthetic upload, processing, signed playback, captions, renewal, stage completion
and deliberate provider deletion. No live Mux upload is part of offline validation.

## Pricing and dependencies

Commercial allowances are not application constants. On 20 October 2026, Mux's
pricing page listed 10 stored videos on the Free plan, 100,000 monthly delivery
minutes, and a $20 monthly pay-as-you-go usage credit. Storage varies with duration,
resolution and storage conditions. Recheck the account and current pricing before
relying on an allowance: <https://www.mux.com/pricing>.

Pinned Mux Player and UpChunk bundles are served locally; see
`resources/vendor/README.md` for versions, upstream provenance and licences.
Provider code uses HTTPS cURL and OpenSSL RS256 signing. Further connectors,
live streaming, DRM, generated-caption workflows and original-video archives are
outside this implementation.

## Local verification record (20 October 2026)

- Installed and re-registered both modules on the local PHP 8.5 runtime, including
  repeatable post-install constraints and long-text schema checks.
- Offline provider/signature/JWT/progress tests and course access/gate tests passed.
- Installed PDO fixtures passed upload deduplication, transaction rollback, duplicate
  callbacks, revoked access, watched intervals, deletion and late-event checks.
- Existing ContextContent schema, rebuild, TikTok, learner-progress and section
  checks passed, as did Module Catalogue dependency/update-hook tests.
- Browser checked the library, missing-configuration state, Help, Escape/focus return,
  and a 390-pixel viewport. No browser console errors were reported.
- No Mux account credentials were available. Real upload, streaming, caption ingest
  and provider deletion remain to be verified after Sysconfig is populated.
