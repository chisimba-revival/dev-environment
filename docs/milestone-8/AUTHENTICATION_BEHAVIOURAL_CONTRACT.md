# Chisimba Authentication Behavioural Contract

## Status

Draft specification for the PHP 8.2 native authentication replacement.

The PHP 7.4 environment remains the behavioural reference. Nothing in this
document authorises switching the engine to native authentication until the
comparison tests pass.

## Existing schema retained

Initial implementation retains:

- `tbl_users`
- `tbl_perms_groups`
- `tbl_perms_groupusers`
- `tbl_perms_perm_users`

No schema redesign is permitted during the first replacement phase.

## Identity questions still requiring evidence

The relationship between these values must be documented:

- `tbl_users.id`
- `tbl_users.userid`
- `tbl_users.username`
- `tbl_users.puid`
- `tbl_perms_groupusers.perm_user_id`
- `tbl_perms_perm_users.perm_user_id`
- `tbl_perms_perm_users.auth_user_id`
- `tbl_perms_perm_users.auth_container_name`

## Required authentication behaviours

### Initialisation

- Start or resume an authentication session.
- Restore the current identity when a valid session exists.
- Return an explicit failure when session restoration fails.
- Never silently authenticate a user.

### Login

Tests must establish:

- whether login accepts `username`, `userid`, or both;
- whether matching is case-sensitive;
- how duplicate or ambiguous identifiers are handled;
- how inactive users are handled;
- how an empty password is handled;
- how unknown users are handled;
- which stored password formats are currently accepted;
- whether successful login increments `logins`;
- whether successful login updates `last_login`;
- which identity values are stored in the session.

### Logout

- Remove authenticated state.
- Regenerate or destroy the session identifier.
- A subsequent request must report the user as logged out.
- Logout must be safe when no user is logged in.

### Session security

The PHP 8.2 implementation must:

- use PHP's normal session APIs;
- regenerate the session ID after successful login;
- avoid placing passwords or hashes in session data;
- reject malformed identity data;
- fail closed on session errors.

## Required authorisation behaviours

### Group membership

Tests must establish:

- how `perm_user_id` maps to `tbl_users`;
- how direct group membership is resolved;
- whether nested groups exist;
- how `group_type` changes behaviour;
- whether disabled or deleted users retain group access.

### Direct permissions

Tests must establish:

- the meaning of `perm_type`;
- the meaning of `auth_user_id`;
- the meaning of `auth_container_name`;
- precedence between direct permissions and group permissions;
- whether explicit denial exists;
- behaviour when no permission row exists.

## Replacement rule

The PHP 8.2 engine may switch to native authentication only when all critical
tests in `AUTHENTICATION_COMPARISON_MATRIX.md` pass against the PHP 7.4
baseline.

## Rollback rule

The engine integration must use a configuration flag. Until native
authentication is accepted, the default must remain the legacy path in the
PHP 7.4 baseline and the experimental path in PHP 8.2 must remain reversible.
