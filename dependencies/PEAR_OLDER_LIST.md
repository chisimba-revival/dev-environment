# Historical PEAR dependencies

As of the 12 October 2026 source cleanup, XML_RPC 1.5.5 and Calendar 0.5.5 are
retired and must not be reintroduced by the dependency builder. XML_RPC callers
were retired; Calendar had already been replaced in the earlier cleanup.

The remaining compatibility stack is the optional MDB2 backend, MDB2_Schema,
XML_Parser, XML_Util and XML_Serializer, plus the PEAR base/error class. Exact
pins live in `pear-packages.tsv`. All managed sites use native PDO, but the
framework still supports and tests MDB2. Remove its fallback and schema paths
with explicit unsupported-backend diagnostics and PDO-only acceptance tests before
removing that dependency chain. Also trace independent XML helper consumers.

Paused modules require a full compatibility review before reactivation. Old
references in paused code do not justify restoring retired shared libraries.
