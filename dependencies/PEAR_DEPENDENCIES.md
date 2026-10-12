# Chisimba PEAR Dependency Register

This file is the human-readable bill of materials for the curated Chisimba
PEAR runtime.

The machine-readable source of truth is:

`pear-packages.tsv`

The dependency builder must obtain these packages from their recorded upstream
sources. Files must not be copied from an old assembled runtime.

## Current dependency set

| Package | Version or commit | Status | Purpose |
|---|---:|---|---|
| PEAR | 1.10.18 | Current | PEAR core runtime |
| MDB2 | commit `96380f6` | Pinned compatibility fork | Optional legacy database backend; all six managed sites now use native PDO |
| MDB2_Schema | commit `e9cc352` | Pinned | Optional MDB2 schema backend; native PDO installer does not use it |
| XML_Parser | 1.3.8 | Current compatible release | Required by MDB2_Schema |
| XML_Util | 1.4.5 | Current compatible release | Required by PEAR and Chisimba XML code |
| XML_RPC | 1.5.5 | Legacy-compatible | Preserves XML_RPC classes and file paths used throughout Chisimba |

| XML_Serializer | 0.21.0 | Legacy-compatible | Retained MDB2 schema parser |

## Retired on 12 October 2026

RDF, MDB (the predecessor of MDB2), and Validate were removed from framework
source after tracing their only application consumer to paused FOAF. The
curated builder does not supply them. FOAF must be modernised before reactivation.
Both unused bundled OpenID MDB2Store adapters were also removed; Chisimba
selects FileStore explicitly. This does not retire the OpenID feature.

PEAR DB remains temporarily for two old installer DSN-parser callers. XML-RPC
remains for legacy RPC callers. The optional MDB2 backend and its XML dependency
chain remain until separately retired. The manifest covers curated packages, not
all historical files still present in framework/app/lib/pear.

## Required XML_RPC interface

Chisimba currently requires these files:

- `XML/RPC.php`
- `XML/RPC/Server.php`
- `XML/RPC/Dump.php`

It also uses these classes:

- `XML_RPC_Value`
- `XML_RPC_Message`
- `XML_RPC_Client`
- `XML_RPC_Response`
- `XML_RPC_Server`

XML_RPC2 is not a drop-in replacement for this API.

## Dependency policy

1. Use the latest compatible release of the same API where possible.
2. Use a maintained fork when the original package cannot support the target PHP version.
3. Record every pinned commit and downloaded package.
4. Never populate the curated tree from an old assembled runtime.
5. Run syntax and class-load checks after building.
6. Record obsolete or unmaintained dependencies in `PEAR_OLDER_LIST.md`.
7. Add newly discovered dependencies to the manifest before adding them to the runtime.

## Completeness

This register describes the dependencies currently incorporated into the
manifest-driven builder. When another required PEAR package is discovered, it
must be added to both `pear-packages.tsv` and this document before the runtime
is rebuilt.
