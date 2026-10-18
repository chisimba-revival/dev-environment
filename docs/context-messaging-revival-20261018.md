# Context messaging revival — source audit and implementation brief

18 October 2026. Agreed direction: context discussion, one-way administrator and context announcements, followed by sightings with compressed photographs. Independent of logbooks; no scheduled demonstration or deadline.

## Which module?

`MODULES_PAUSED/im__PAUSED` is `im` 0.196: a Jabber/XMPP gateway, with contact presence, counsellor assignment, broadcasts and external integrations. Its message schema has no context/channel access boundary. Its controller exempts a long-running message handler from login. Do not start the listener or restore historical connection settings. The paused directory remains untouched.

`modules/messaging` 1.124 is the intended context-aware chat: registration describes context rooms, private rooms, moderation, bans and direct messages queued for absent users. Derek confirmed the distinction. Preserve its purpose and inspect installed data before designing migration; it is not ready to enable unchanged.

Baseline: modules `4021cd481`, runtime/API framework `work/rest-api-review-20261018` at `69b027de0`. Unrelated paused-module moves were preserved. No activation, schema migration or deployment occurred.

## Findings and reuse boundaries

| Evidence | Finding | Required direction |
| --- | --- | --- |
| messaging/controller.php: enterroom, sendchat, deleteroom | Session-selected room and cached moderation; handlers lack the modern per-operation permission/POST/CSRF boundary | Resolve persisted room scope and recheck permissions on every operation; never expose legacy handlers through REST |
| messaging/classes/dbmessaging_class_inc.php: getChatRoom, getChatMessages | Interpolated query fragments | Prepared dbTable operations behind a repository |
| Same class: isModerator | Current-context lecturer check rather than explicit persisted-room context | Use canonical membership/role services with the exact room context |
| Same class: addChatMessage, addImMessage | Ordering uses count plus one | Atomic server ordering and database-enforced client submission IDs |
| messaging/resources/messaging.js and chat display | Prototype Ajax.Updater/Autocompleter and frame-oriented UI | Complete native HTML/CSS/JS caller replacement using shared skin primitives |
| announcements | Existing site/context audiences and notification publisher | Keep announcements owned here; compose their views into communications rather than duplicate storage |
| notifications | Recipient feed, unread state, cursor pagination and unique event idempotency keys | Reuse alerts; distinguish notification state from channel read position and message delivery |
| notifications/classes/notificationservice_class_inc.php: feed | Projects stored recipient/event data without owning-source access revalidation within this service | Revalidate private source access before exposing summaries/counts to mobile; test revoked membership |
| discussion | Existing forum threads, subscriptions, attachments and notifications | Reuse services/links where appropriate; preserve forum identity and history |
| Framework files/imageresize | Aspect-preserving resize and raster decoding; invalid inputs may generate fallback graphics | Extend/reuse shared processing, but fallback thumbnails are not successful upload validation |
| Framework filemanager and tools/file-storage/README.md | Scoped originals and protected derivatives | Apply owning-message access to every photo and thumbnail; public course materials do not make course conversations public |

These are source findings, not a full penetration test. Legacy network handlers were not executed.

## First implementation

Modernise `messaging` as the conversation owner with policy, service and dbTable repository boundaries shared by web and the existing REST API. Do not introduce separate authentication or another API. Keep new services distinct from retained legacy data until migration is tested. Inventory room types, counts, orphans and encodings first; preserve IDs/history where safely mapped. Direct messages are not automatically part of the initial slice.

- Context discussion: current members read/post; authorised context staff moderate.
- Context announcements: authorised staff publish; members read; replies disabled server-side.
- Administrator announcements: authorised administrators publish; existing audience policy determines readers; replies disabled. Do not equate a site with a single organisation without checking its configuration.
- Sightings: context members post a photo and caption, after reliable text delivery exists.

Persisted scope determines permissions, not the browser's current context or supplied owner. Check membership, bans and role changes for history, send, reply, moderation, counts, search, notifications and attachments. Context conversations remain private to members even where course content is public.

The first complete slice must provide bounded, cursor-paginated history; atomic message ordering; plain-text bodies; and a durable client submission ID scoped to account/channel. Same ID and payload returns the original receipt; changed payload is a conflict. Recheck access before returning a receipt. Test concurrent duplicates and lost replies. Notification publication needs a reliable outbox/transaction boundary so a notification failure cannot make an already committed message look unsent. Reuse notification idempotency, without confusing it with submission idempotency.

Per-account/channel read position is monotonic and separate from presence. Both web and mobile call the same service. Web uses canonical POST/CSRF; mobile uses the shared authenticated REST boundary. Include registered language/systext, contextual Help, semantic native controls, keyboard/focus behaviour and narrow-screen tests.

## Offline behaviour

Partition cached history, drafts and outgoing queues by server/account/channel. Changing account must not expose another account's cached conversations. Show draft, queued, sending, confirmed and needs-attention states. A connection is not confirmation of receipt. Retry with the same submission ID only after the server contract exists; the current Simple Blog uncertain-send mechanism is not a messaging retry protocol.

Preserve drafts through restart and token expiry. Incrementally fetch history. On confirmed access revocation, block sending and remove inaccessible cached history under an explicit cache policy; provide a recovery path for unsent personal text. Offline devices cannot discover revocation until they reconnect. Define sign-out and retention behaviour before shared-device use.

Bounded incremental HTTP polling while a view is active is sufficient initially. Push, typing indicators and presence come later. Quiet-channel preferences must not destroy durable announcements.

## Sightings images

Shrink on the phone before upload to save mobile data, using a reusable image-preparation component. Proposed starting parameters, to validate against real photographs: preserve aspect ratio, do not upscale, longest edge at most 2048 pixels, JPEG quality around 80, an explicit byte ceiling and bounded reduction attempts. These are provisional settings, not a delivered quality guarantee.

Correct orientation before re-encoding. Strip embedded metadata including automatic GPS from the shared copy; leave the original phone photo untouched. Show a preview and caption. If location becomes part of sightings, make it an explicit field with its own visibility rules. Test rotated portraits, panoramas, transparency, corrupt images, extreme pixel counts and device formats such as HEIC; unsupported inputs should fail clearly without losing the draft.

The server independently checks actual media type, byte size and decoded pixel budget, and safely re-encodes through the shared processing boundary. Client compression does not replace server validation. Store files privately through filemanager with owning-message access for originals and thumbnails. Uploads and message attachment need durable IDs, interrupted-upload recovery and cleanup of abandoned temporary files. Later logbook callers should reuse this component.

## Sequence and verification

1. Read-only installed-data inventory; fresh-install/migration fixtures; shared text policy/store/service. Test outsider, member, revoked, banned, staff and admin cases.
2. Complete local web context conversation and one-way announcement views, including Help and accessibility.
3. Shared REST routes and mobile history/outbox. Test concurrent posts, repeat submissions, lost receipts, restart, reconnect and cross-account isolation.
4. Sightings using reusable image preparation and protected attachments; measure size/quality and test interrupted upload.
5. Local verification before authorised rollout. No legacy activation is part of this audit.

Checks run in the existing local PHP 8.5 container: notifications service behavioural suite passed (12 checks); announcements revival contract passed. These establish a baseline for those existing suites only. New messaging workflows, offline delivery and image preparation are not implemented or runtime-tested yet.

## Local implementation completed later on 18 October

Messaging 2.000 now supplies the first native web conversation workflow and
one-way announcement views, with announcements 0.414 adding an optional scope
filter. See `modules/messaging/README.md` for the implementation, checks and
remaining mobile/image work. Local inventory found messaging unregistered and
legacy messaging tables absent. Normal fresh installation and repeat registration
preserved new records. Legacy source is archived as non-executable text; no legacy
database records were removed. No production deployment or push was performed.

Policy, real PDO rollback, concurrent retry, HTTP security, history/read position,
announcement scope/audience/date, syntax and announcement contract checks passed.
Browser checks covered desktop, 390px and Help/focus return. The shared narrow
canvas has a small outer horizontal overflow, recorded for follow-up. Mobile
offline messaging, notification delivery, moderation UI and sightings remain
unimplemented. Disposable test context/messages/account were cleaned after checks.
