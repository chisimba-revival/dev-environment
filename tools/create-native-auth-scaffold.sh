#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
FRAMEWORK="$ROOT/framework/app"
SECURITY="$FRAMEWORK/core_modules/security"

CONTRACTS="$SECURITY/classes/contracts"
NATIVE="$SECURITY/classes/nativeauth"
DOCS="$ROOT/dev-environment/docs/milestone-8"

OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

section "Create Milestone 8 native-authentication scaffold"

mkdir -p \
    "$CONTRACTS" \
    "$NATIVE" \
    "$DOCS"

section "Authentication service contract"

cat > "$CONTRACTS/authenticationserviceinterface_class_inc.php" <<'PHP'
<?php

/**
 * Authentication service contract for Chisimba.
 *
 * This interface describes the small authentication surface required by
 * the framework. It intentionally contains no LiveUser implementation
 * details.
 *
 * The initial PHP 8.2 implementation must preserve the externally visible
 * behaviour of the frozen PHP 7.4 system.
 */
interface AuthenticationServiceInterface
{
    /**
     * Initialise authentication and restore any existing session.
     *
     * @return bool TRUE when initialisation succeeds
     */
    public function init();

    /**
     * Authenticate a user using a local identifier and password.
     *
     * The identifier may initially map to the legacy username or userid
     * fields. The precise lookup rule must be captured from PHP 7.4 tests.
     *
     * @param string $identifier
     * @param string $password
     * @return bool
     */
    public function login($identifier, $password);

    /**
     * End the authenticated session.
     *
     * @return bool
     */
    public function logout();

    /**
     * Determine whether the current request has an authenticated user.
     *
     * @return bool
     */
    public function isLoggedIn();

    /**
     * Return the current authenticated Chisimba user identifier.
     *
     * The final identifier type must be chosen after mapping the legacy
     * id, userid, puid and auth_user_id relationships.
     *
     * @return mixed|null
     */
    public function getCurrentUserId();

    /**
     * Return errors from the most recent authentication operation.
     *
     * @return array
     */
    public function getErrors();
}
PHP

section "User repository contract"

cat > "$CONTRACTS/userrepositoryinterface_class_inc.php" <<'PHP'
<?php

/**
 * Repository contract for Chisimba user records.
 *
 * The existing tbl_users schema remains authoritative during the initial
 * PHP 8.2 migration.
 */
interface UserRepositoryInterface
{
    /**
     * Find a user by the Chisimba id field.
     *
     * @param mixed $id
     * @return array|null
     */
    public function findById($id);

    /**
     * Find a user by the legacy userid field.
     *
     * @param string $userId
     * @return array|null
     */
    public function findByUserId($userId);

    /**
     * Find a user by username.
     *
     * @param string $username
     * @return array|null
     */
    public function findByUsername($username);

    /**
     * Find a user by the numeric primary key.
     *
     * @param int $puid
     * @return array|null
     */
    public function findByPuid($puid);

    /**
     * Determine whether the account is active.
     *
     * @param array $user
     * @return bool
     */
    public function isActive(array $user);

    /**
     * Record a successful login.
     *
     * This must preserve the legacy meanings of logins and last_login.
     *
     * @param array $user
     * @return bool
     */
    public function recordSuccessfulLogin(array $user);
}
PHP

section "Group repository contract"

cat > "$CONTRACTS/grouprepositoryinterface_class_inc.php" <<'PHP'
<?php

/**
 * Repository contract for Chisimba groups and memberships.
 */
interface GroupRepositoryInterface
{
    /**
     * Return groups associated with a permission-user identifier.
     *
     * @param mixed $permissionUserId
     * @return array
     */
    public function findGroupsForPermissionUser($permissionUserId);

    /**
     * Determine whether a permission user belongs to a group.
     *
     * @param mixed $permissionUserId
     * @param mixed $groupId
     * @return bool
     */
    public function isMember($permissionUserId, $groupId);

    /**
     * Return a group definition.
     *
     * @param mixed $groupId
     * @return array|null
     */
    public function findGroup($groupId);
}
PHP

section "Permission repository contract"

cat > "$CONTRACTS/permissionrepositoryinterface_class_inc.php" <<'PHP'
<?php

/**
 * Repository contract for direct and derived Chisimba permissions.
 *
 * Permission precedence is deliberately not specified here. It must first
 * be measured against the PHP 7.4 behavioural baseline.
 */
interface PermissionRepositoryInterface
{
    /**
     * Return direct permission rows for a permission user.
     *
     * @param mixed $permissionUserId
     * @return array
     */
    public function findDirectPermissions($permissionUserId);

    /**
     * Determine whether a user has a named permission.
     *
     * The exact mapping between permission names, perm_type values, groups
     * and areas must be implemented only after baseline tests exist.
     *
     * @param mixed $permissionUserId
     * @param mixed $permission
     * @param mixed|null $context
     * @return bool
     */
    public function hasPermission(
        $permissionUserId,
        $permission,
        $context = null
    );
}
PHP

section "Session service contract"

cat > "$CONTRACTS/authsessioninterface_class_inc.php" <<'PHP'
<?php

/**
 * Session operations required by native Chisimba authentication.
 */
interface AuthSessionInterface
{
    /**
     * Start or resume the authentication session.
     *
     * @return bool
     */
    public function start();

    /**
     * Establish an authenticated session.
     *
     * Implementations must regenerate the session identifier before storing
     * authenticated state.
     *
     * @param array $identity
     * @return bool
     */
    public function establish(array $identity);

    /**
     * Return the stored authenticated identity.
     *
     * @return array|null
     */
    public function getIdentity();

    /**
     * Destroy authentication state and invalidate the session.
     *
     * @return bool
     */
    public function destroy();
}
PHP

section "Password verifier contract"

cat > "$CONTRACTS/passwordverifierinterface_class_inc.php" <<'PHP'
<?php

/**
 * Password verification contract.
 *
 * No implementation is provided until the actual tbl_users.pass formats
 * have been safely inventoried.
 */
interface PasswordVerifierInterface
{
    /**
     * Verify a supplied password against a stored legacy value.
     *
     * @param string $password
     * @param string $storedValue
     * @param array  $user
     * @return bool
     */
    public function verify(
        $password,
        $storedValue,
        array $user = array()
    );

    /**
     * Determine whether the stored value should be upgraded.
     *
     * @param string $storedValue
     * @return bool
     */
    public function needsRehash($storedValue);

    /**
     * Generate a modern password hash.
     *
     * @param string $password
     * @return string
     */
    public function hash($password);
}
PHP

section "Non-active native authentication service skeleton"

cat > "$NATIVE/nativeauthenticationservice_class_inc.php" <<'PHP'
<?php

/**
 * Native PHP authentication service for Chisimba.
 *
 * IMPORTANT:
 * This class is scaffold-only and is not wired into the engine.
 * Its methods deliberately fail closed until repositories, password
 * verification and session behaviour have been implemented and tested.
 */
class NativeAuthenticationService implements AuthenticationServiceInterface
{
    /**
     * @var UserRepositoryInterface|null
     */
    protected $userRepository = null;

    /**
     * @var GroupRepositoryInterface|null
     */
    protected $groupRepository = null;

    /**
     * @var PermissionRepositoryInterface|null
     */
    protected $permissionRepository = null;

    /**
     * @var PasswordVerifierInterface|null
     */
    protected $passwordVerifier = null;

    /**
     * @var AuthSessionInterface|null
     */
    protected $session = null;

    /**
     * @var array
     */
    protected $errors = array();

    /**
     * Constructor.
     *
     * @param UserRepositoryInterface       $userRepository
     * @param GroupRepositoryInterface      $groupRepository
     * @param PermissionRepositoryInterface $permissionRepository
     * @param PasswordVerifierInterface     $passwordVerifier
     * @param AuthSessionInterface          $session
     */
    public function __construct(
        UserRepositoryInterface $userRepository,
        GroupRepositoryInterface $groupRepository,
        PermissionRepositoryInterface $permissionRepository,
        PasswordVerifierInterface $passwordVerifier,
        AuthSessionInterface $session
    ) {
        $this->userRepository = $userRepository;
        $this->groupRepository = $groupRepository;
        $this->permissionRepository = $permissionRepository;
        $this->passwordVerifier = $passwordVerifier;
        $this->session = $session;
    }

    /**
     * {@inheritdoc}
     */
    public function init()
    {
        $this->errors = array();

        return $this->session->start();
    }

    /**
     * {@inheritdoc}
     */
    public function login($identifier, $password)
    {
        $this->errors = array(
            'Native authentication is not enabled yet.',
        );

        /*
         * Fail closed until all of the following are verified:
         *
         * 1. identifier lookup precedence;
         * 2. stored password formats;
         * 3. inactive-account behaviour;
         * 4. session identity format;
         * 5. successful-login updates.
         */
        return false;
    }

    /**
     * {@inheritdoc}
     */
    public function logout()
    {
        $this->errors = array();

        return $this->session->destroy();
    }

    /**
     * {@inheritdoc}
     */
    public function isLoggedIn()
    {
        return is_array($this->session->getIdentity());
    }

    /**
     * {@inheritdoc}
     */
    public function getCurrentUserId()
    {
        $identity = $this->session->getIdentity();

        if (!is_array($identity)) {
            return null;
        }

        if (array_key_exists('userid', $identity)) {
            return $identity['userid'];
        }

        if (array_key_exists('id', $identity)) {
            return $identity['id'];
        }

        return null;
    }

    /**
     * {@inheritdoc}
     */
    public function getErrors()
    {
        return $this->errors;
    }
}
PHP

section "Behavioural contract document"

cat > "$DOCS/AUTHENTICATION_BEHAVIOURAL_CONTRACT.md" <<'MARKDOWN'
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
MARKDOWN

section "Comparison test matrix"

cat > "$DOCS/AUTHENTICATION_COMPARISON_MATRIX.md" <<'MARKDOWN'
# PHP 7.4 versus PHP 8.2 Authentication Comparison Matrix

| ID | Behaviour | PHP 7.4 expected result | PHP 8.2 result | Status |
|---|---|---|---|---|
| AUTH-001 | Known active user, correct password | To measure | Not implemented | Pending |
| AUTH-002 | Known active user, wrong password | To measure | Not implemented | Pending |
| AUTH-003 | Unknown username | To measure | Not implemented | Pending |
| AUTH-004 | Empty username | To measure | Not implemented | Pending |
| AUTH-005 | Empty password | To measure | Not implemented | Pending |
| AUTH-006 | Inactive user | To measure | Not implemented | Pending |
| AUTH-007 | Username case variation | To measure | Not implemented | Pending |
| AUTH-008 | Userid used as login identifier | To measure | Not implemented | Pending |
| AUTH-009 | Successful login updates logins | To measure | Not implemented | Pending |
| AUTH-010 | Successful login updates last_login | To measure | Not implemented | Pending |
| AUTH-011 | Session survives next request | To measure | Not implemented | Pending |
| AUTH-012 | Session ID changes after login | To measure | Not implemented | Pending |
| AUTH-013 | Logout clears authentication | To measure | Not implemented | Pending |
| AUTH-014 | Logout while already logged out | To measure | Not implemented | Pending |
| AUTH-015 | Group membership lookup | To measure | Not implemented | Pending |
| AUTH-016 | User with no groups | To measure | Not implemented | Pending |
| AUTH-017 | Direct permission granted | To measure | Not implemented | Pending |
| AUTH-018 | Direct permission absent | To measure | Not implemented | Pending |
| AUTH-019 | Group-derived permission granted | To measure | Not implemented | Pending |
| AUTH-020 | Direct/group precedence | To measure | Not implemented | Pending |

## Acceptance gate

The following must pass before browser activation:

- AUTH-001 through AUTH-014;
- AUTH-015 through AUTH-020 for administrator and ordinary-user fixtures;
- no PHP warning, notice, or fatal generated by the new service;
- no plaintext password written to a log, session, report, or fixture;
- rollback to the previous engine path confirmed.
MARKDOWN

section "Feature-flag integration plan"

cat > "$DOCS/NATIVE_AUTH_FEATURE_FLAG.md" <<'MARKDOWN'
# Native Authentication Feature Flag

## Proposed configuration

A future engine integration should read a configuration value such as:

```text
auth_provider = legacy_liveuser
