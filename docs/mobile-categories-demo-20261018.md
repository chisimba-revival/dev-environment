# Mobile Simple Blog demo and categories — 18 October 2026

The Android notebook presentation now puts offline writing first, with site/sign-in settings in a native disclosure. The demo remains the existing text-only Simple Blog workflow. No CPD, logbook, media or automatic synchronisation functionality was added.

Framework `69b027de0` adds authenticated `GET /api/v1/simpleblog/categories` and optional category IDs on the existing text-post endpoint. The vocabulary is always the caller's personal blog; authentication and personal-publishing permission are required. SimpleBlog `4021cd481`, version 0.078, assigns categories through the shared classification service in the post transaction, including plain-text callers. Invalid, unknown, other-scope and wrong-kind IDs leave no post behind. REST API version is 1.003. Prince's existing endpoints remain unchanged.

The app caches choices per server/account and saves the selected category with a draft. Choosing a category binds the draft to that identity/server. Cached choices can be used offline; the server revalidates on submission. Category creation remains in the normal website editor. Derek requested Notes, Observations and Reflections; these were created in his personal Chisimba.com blog through the existing editor, without creating or publishing a post.

## Checks

- PHP syntax, text input and SimpleBlog publishing tests passed.
- Installed local and public API tests exercised anonymous/unprivileged/revoked denial, exact routes/methods, own vocabulary selection, ignored owner spoofing, foreign/tag/unknown/malformed category rejection, successful private assignment and transaction rollback with no extra posts. All synthetic accounts, posts, categories and grants were removed.
- Existing local text-only HTTP checks passed unchanged, including markup escaping, media rejection, private/public visibility and revoked permissions.
- Mobile model suites passed, including account/server cache isolation, saved category binding and invalid lists.
- Browser preview verified draft persistence after reload, 390px layout, keyboard connection disclosure and contextual Help/Escape focus return. It cannot perform Android-native secure sign-in; the preview says so.
- Android debug build passed. APK was updated in place on Samsung S22 Ultra, preserving app data. Final live airplane-mode/category/send rehearsal with Derek remains to be done; this is not claimed as an automated device workflow test.
- Final sampled production PHP diagnostic count: zero.

## Chisimba.com release

Only Chisimba.com was updated. The eight-file delta was checked against framework `fe55c81b4` and modules `4f72adae9` before deployment. Normal Module Catalogue registration updated both module versions; no schema change was introduced.

- Current release: `/srv/chisimba-com/releases/release-mobile-categories-20261018-122847/ch`.
- Previous: `/srv/chisimba-com/releases/release-simpleblog-delete-20261018-121037/ch`.
- Database/compose backup and release record: `/srv/chisimba-com/backups/mobile-categories-20261018-122847/`.
- Status: `online-verified`.
- Deployment and disposable verification tools: `tools/mobile-categories-20261018/`.

The retained source release supports rollback; additive module-version registration does not require a database restore. The shared release lock, exact source hashes and backup checks apply. Other sites, keys, service configuration and unrelated module moves were unchanged.

The app README contains a short rehearsal script: connect/load categories before the meeting; airplane mode with Wi-Fi off; write and reopen; reconnect and manually send a private draft; show it in web management. Use synthetic, non-sensitive text and rehearse before presenting.
