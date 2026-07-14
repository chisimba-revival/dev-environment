# Older PEAR Dependencies Retained by Chisimba

This register records dependencies that are retained because Chisimba still
uses their historical API.

These packages are not copied from a legacy runtime. They are downloaded from
their recorded upstream package source and included reproducibly by the
dependency builder.

## XML_RPC

- **Package:** `XML_RPC`
- **Version:** `1.5.5`
- **Status:** Legacy-compatible; unmaintained API
- **Why retained:** Chisimba directly requires the original XML_RPC classes and file layout.
- **Required files:**
  - `XML/RPC.php`
  - `XML/RPC/Server.php`
  - `XML/RPC/Dump.php`
- **Required classes:**
  - `XML_RPC_Value`
  - `XML_RPC_Message`
  - `XML_RPC_Client`
  - `XML_RPC_Response`
  - `XML_RPC_Server`
- **Known Chisimba users:**
  - `core_modules/packages/classes/rpcserver_class_inc.php`
  - `core_modules/api/classes/xmlrpcapi_class_inc.php`
  - XML-RPC clients and filters throughout the framework
- **Current compatibility treatment:** Syntax checking and narrowly scoped PEAR modernisation for PHP 7.4.
- **Future replacement:** Replace the Chisimba XML-RPC layer with a maintained XML-RPC implementation or a modern HTTP/JSON API while preserving required integration behaviour.
- **Removal condition:** Remove only after all Chisimba references to the original XML_RPC API have been migrated and integration-tested.

## Calendar

- **Package:** `Calendar`
- **Version:** `0.5.5`
- **Status:** Legacy-compatible
- **Why retained:** Chisimba code expects the original PEAR Calendar API.
- **Current compatibility treatment:** PHP syntax and runtime class-load testing.
- **Future replacement:** Replace with maintained date and calendar services where practical.
- **Removal condition:** Remove only after all original Calendar API consumers have been migrated and tested.

## Maintenance rule

Every package retained because of an old API must be added here when it is
added to `pear-packages.tsv`.

Each entry must record:

1. Exact package and version.
2. Why Chisimba requires it.
3. Relevant classes and file paths.
4. PHP compatibility treatment.
5. Intended replacement.
6. Conditions required before removal.
