# Live Mux verification — 20 October 2026

All six required configuration values are populated on www.chisimba.com. The
private signing key parses successfully, and the configured API token receives
HTTP 200 from the Mux Video assets endpoint. No secrets were printed or copied
into this record.

Uploaded a generated 12-second 640x360 test pattern using the authenticated
library and direct browser upload. Chisimba video ID:
`ce8a9aaf76f715d8dad8e30d0ad4cea4`. The asset became ready from authenticated Mux
callbacks before any manual provider-status refresh. Signed playback visibly
renders the test pattern in the browser.

A generated English WebVTT file was submitted through the library. Mux fetched
it from Chisimba, processed the text track, and the caption visibly renders over
the test pattern. Eight verified callback records were present after processing.
The sample remains in the site library for user inspection, unattached to lessons.
No existing course content was changed.

This check does not establish live lesson progress/resume, stage-gate completion,
15-minute token renewal, or hosted deletion. Those retain the prior offline and
PDO test coverage and need separate live course acceptance.

Live testing exposed PHP 8.5's deprecated curl_close no-op. Modules commit
7c2935718 replaces it with object release using unset. Provider/progress tests
and PHP syntax checks pass. The bounded deployment script preserves the previous
release, checks exact before/after source, and makes no data or schema changes.
