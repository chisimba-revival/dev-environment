# Bounded LiveUser and Language-Stack Audit

Files scanned: **14104**  
Relevant files examined: **133**

## Executive decision table

| Subsystem | Calls | Files | Used methods | Available methods | Recommendation |
|---|---:|---:|---:|---:|---|
| LiveUser | 7 | 1 | 5 | 40 | replace behind authentication adapter |
| LiveUser_Admin | 4 | 1 | 2 | 14 | replace behind authentication adapter |
| Translation2 | 2 | 1 | 1 | 35 | replace behind adapter |
| I18Nv2 | 4 | 2 | 2 | 15 | replace behind adapter |
| Event_Dispatcher | 2 | 1 | 2 | 21 | replace |

## LiveUser

**Recommendation:** replace behind authentication adapter

The detected Chisimba-facing surface is bounded. Reproduce login, sessions, users, groups and rights using PHP 7.4 as the behavioural reference.

- Used methods: `getErrors()`, `init()`, `isLoggedIn()`, `logout()`, `singleton()`
- Likely tables: `tbl_perms_groups`, `tbl_perms_groupusers`, `tbl_perms_perm_users`, `tbl_users`

### Capabilities

- **authentication:** `logout()`
- **object construction and configuration:** `init()`, `singleton()`
- **other:** `getErrors()`, `isLoggedIn()`

### Call sites

- `framework/app/classes/core/engine_class_inc.php:846` — `singleton()` (static)
- `framework/app/classes/core/engine_class_inc.php:849` — `init()` (instance)
- `framework/app/classes/core/engine_class_inc.php:850` — `getErrors()` (instance)
- `framework/app/classes/core/engine_class_inc.php:873` — `logout()` (instance)
- `framework/app/classes/core/engine_class_inc.php:877` — `logout()` (instance)
- `framework/app/classes/core/engine_class_inc.php:2062` — `isLoggedIn()` (instance)
- `framework/app/classes/core/engine_class_inc.php:2086` — `isLoggedIn()` (instance)

## LiveUser_Admin

**Recommendation:** replace behind authentication adapter

The detected Chisimba-facing surface is bounded. Reproduce login, sessions, users, groups and rights using PHP 7.4 as the behavioural reference.

- Used methods: `factory()`, `init()`
- Likely tables: `tbl_perms_groups`, `tbl_perms_groupusers`, `tbl_perms_perm_users`, `tbl_users`

### Capabilities

- **object construction and configuration:** `factory()`, `init()`

### Call sites

- `framework/app/classes/core/engine_class_inc.php:854` — `factory()` (static)
- `framework/app/classes/core/engine_class_inc.php:894` — `factory()` (static)
- `framework/app/classes/core/engine_class_inc.php:855` — `init()` (instance)
- `framework/app/classes/core/engine_class_inc.php:895` — `init()` (instance)

## Translation2

**Recommendation:** replace behind adapter

The detected external method surface is bounded enough to reimplement without preserving the full abandoned package.

- Used methods: `factory()`
- Likely tables: `tbl_languagelist`

### Capabilities

- **object construction and configuration:** `factory()`

### Call sites

- `framework/app/core_modules/language/classes/languageconfig_class_inc.php:163` — `factory()` (static)
- `framework/app/core_modules/language/classes/languageconfig_class_inc.php:170` — `factory()` (static)

## I18Nv2

**Recommendation:** replace behind adapter

PHP intl can provide the core locale services while an adapter preserves Chisimba-facing method names.

- Used methods: `autoConv()`, `createLocale()`
- Likely tables: `tbl_languagelist`

### Capabilities

- **locale handling:** `createLocale()`
- **other:** `autoConv()`

### Call sites

- `framework/app/core_modules/language/classes/languagecode_class_inc.php:192` — `autoConv()` (static)
- `framework/app/core_modules/language/classes/language_class_inc.php:129` — `createLocale()` (static)
- `framework/app/core_modules/language/classes/language_class_inc.php:353` — `createLocale()` (static)
- `framework/app/core_modules/language/classes/language_class_inc.php:360` — `createLocale()` (static)

## Event_Dispatcher

**Recommendation:** replace

The exposed interface is small and maps naturally to a Chisimba-native event dispatcher.

- Used methods: `addObserver()`, `getInstance()`
- Likely tables: None identified

### Capabilities

- **event dispatch:** `addObserver()`
- **other:** `getInstance()`

### Call sites

- `framework/app/classes/core/engine_class_inc.php:556` — `getInstance()` (static)
- `framework/app/classes/core/engine_class_inc.php:847` — `addObserver()` (instance)

## Audit limitations

- The audit records exact static calls.
- Instance calls are recorded only for known integration variable names.
- Dynamic method calls and aliases may require later manual review.
- Runtime copies and backups are intentionally excluded.
