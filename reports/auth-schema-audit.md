# Authentication Schema Audit

## Executive conclusion

Retain the existing user, group and permission schema for the initial PHP 8.2 migration. Replace abandoned authentication middleware behind repository and service interfaces before considering schema redesign.

## Table summary

| Table | Present | Columns | Minimum PHP 8.2 contract |
|---|---:|---:|---|
| `tbl_users` | Yes | 20 | `id`, `userid`, `username`, `isactive`, `puid` |
| `tbl_perms_groups` | Yes | 5 | `id`, `group_id` |
| `tbl_perms_groupusers` | Yes | 4 | `id`, `group_id` |
| `tbl_perms_perm_users` | Yes | 6 | `id` |

## `tbl_users`

The table can be retained. Authentication-specific fields form a small subset; profile and application data should remain in place while a native PHP 8.2 authentication service reads only the identity, credential and account-state fields.

### Columns by responsibility

- **identity:** `emailaddress`, `id`, `logins`, `puid`, `userid`, `username`
- **other user metadata:** `accesslevel`, `cellnumber`, `pass`, `sex`
- **profile:** `country`, `creationdate`, `firstname`, `howcreated`, `staffnumber`, `surname`, `title`, `updated`
- **session and account state:** `isactive`, `last_login`

### Keys and indexes

- `id`
- `userid`
- `puid`

### Source definitions

No source definition located.

## `tbl_perms_groups`

Retain the table. It represents Chisimba's domain model for groups and roles rather than an implementation detail of LiveUser.

### Columns by responsibility

- **group and role definition:** `group_define_name`, `group_id`, `group_type`
- **group metadata:** `id`, `puid`

### Keys and indexes

- `id`
- `group_id`
- `puid`

### Source definitions

No source definition located.

## `tbl_perms_groupusers`

Retain the table. It is a conventional user-to-group relationship that can be accessed through a small membership repository.

### Columns by responsibility

- **relationship key:** `group_id`, `perm_user_id`
- **relationship metadata:** `id`, `puid`

### Keys and indexes

- `id`
- `group_id`
- `puid`

### Source definitions

No source definition located.

## `tbl_perms_perm_users`

Retain the table initially. Encapsulate direct user permissions behind a permission repository so its legacy semantics can be verified against PHP 7.4 before later schema simplification.

### Columns by responsibility

- **relationship key:** `auth_user_id`, `perm_type`, `perm_user_id`
- **relationship metadata:** `auth_container_name`, `id`, `puid`

### Keys and indexes

- `id`
- `perm_user_id`
- `puid`

### Source definitions

No source definition located.

## Recommended PHP 8.2 architecture

### Schema

Retain existing authentication and permission tables initially.

### User Repository

Add a repository that owns identity, profile and account-state queries against tbl_users.

### Authentication Service

Implement password verification, login, logout and sessions without LiveUser.

### Group Repository

Encapsulate tbl_perms_groups and tbl_perms_groupusers.

### Permission Repository

Encapsulate tbl_perms_perm_users and preserve legacy semantics using PHP 7.4 behavioural tests.

### Migration Rule

No schema redesign until PHP 8.2 login, logout, group membership and permission checks match the PHP 7.4 baseline.

## Limitations

- This audit describes schema structure, not every runtime invariant.
- Dynamic SQL and database triggers may require additional review.
- Password hashing behaviour must be verified separately.
- Permission precedence must be tested against the PHP 7.4 baseline.
