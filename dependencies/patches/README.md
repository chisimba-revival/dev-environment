# Curated dependency compatibility patches

`xml-parser-php8-callbacks.patch` applies to the pinned XML_Parser 1.3.8 source during `build-chisimba-pear-runtime.sh`, before the staged pack is installed. It removes obsolete XML callback registration, adapts reference-taking legacy start handlers and avoids the no-op PHP 8 parser-free call. Both XML_Parser and XML_Parser_Simple are covered. The PHP 7 resource-free path is retained; PHP 7 has not been runtime-tested in this batch.

Canonical deployable files are under `framework/app/lib/pear/XML/`. Regression test: `framework/tests/dependencies/xml_parser_runtime_test.php`. Test against both normal source and the assembled PHP runtime. Patch application must fail visibly if a later upstream version no longer matches; review rather than silently skipping it.

The companion Config character-data fix is in `framework/app/lib/pear/Config/Container/XML.php`. Config is retained from framework source and is not replaced by the curated XML package extraction.

`mdb2-iterator-php8-signatures.patch` supplies the real Iterator/SeekableIterator return types and makes a database error terminate buffered iteration. This patch requires PHP 8+ (`mixed`), matching the active PHP 8.5 application target; do not apply this pack to a legacy PHP 7 runtime. Tests cover the real MDB2 base class with controlled result fixtures and read-only constant SELECTs through the actual local mysqli driver.

Translation2/Decorator/UTF8.php is retained from framework source rather than replaced by this curated build. Its internal Latin-1 decoder preserves the retired builtin's byte-level substitution behaviour; it does not change the site's character-set policy. All 65,536 two-byte inputs and 5,000 longer deterministic byte sequences are compared against the old builtin while available, alongside frozen Unicode/malformed/Latin-1 fixtures that remain usable once PHP removes that builtin.

Translation2/Container/mdb2.php is also retained from framework source. Its
MDB2::connect result now uses ordinary assignment because the bundled MDB2 method
does not return by reference. Existing caller-supplied database-object reference
handling is unchanged. Verified by local language-bearing HTTP routes and the
real MDB2/mysqli read-only smoke test.

Final baseline compatibility fixes also touch retained HTML/BBCodeParser.php
(guard absent previous tag) and the bundled search Lucene Document/Xlsx.php and
Index/Writer.php (double-to-float cast spelling only). BBCode was copied into the
local runtime; search resources are live-mounted. Cold-start public routes are
clean and strict parser boundary fixtures pass. These are not library upgrades.
