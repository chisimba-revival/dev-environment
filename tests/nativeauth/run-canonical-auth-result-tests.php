<?php
$root = dirname(__FILE__) . '/../../../';
$auth = $root
    . 'framework/app/core_modules/security/classes/nativeauth/';

require_once $auth . 'canonicalauthenticationresult.php';
require_once $auth . 'legacyauthenticationresultadapter.php';
require_once $auth . 'nativeauthenticationresultadapter.php';

$tests = 0;
$failures = array();

function checkCanonical($condition, $message)
{
    global $tests, $failures;
    $tests++;
    if (!$condition) {
        $failures[] = $message;
        echo 'FAIL: ' . $message . PHP_EOL;
        return;
    }
    echo 'PASS: ' . $message . PHP_EOL;
}

$legacyRecord = array(
    'username' => 'example',
    'userid' => 'user-123',
    'title' => 'Dr',
    'firstname' => 'Example',
    'surname' => 'User',
    'creationdate' => '2026-01-01',
    'emailaddress' => 'example@example.invalid',
    'logins' => '7',
    'isactive' => '1',
    'accesslevel' => '1',
    'pass' => 'must-never-be-copied',
);

$legacyAdapter = new LegacyAuthenticationResultAdapter();
$legacy = $legacyAdapter->fromDatabaseRecord(
    $legacyRecord,
    'liveuser_database',
    array('source' => 'test')
);

checkCanonical($legacy->isSuccess(), 'active legacy record produces success');
checkCanonical(
    $legacy->getUserId() === 'user-123',
    'legacy user ID is preserved'
);
checkCanonical(
    $legacy->getUsername() === 'example',
    'legacy username is preserved'
);
checkCanonical(
    !array_key_exists('pass', $legacy->getIdentity()),
    'password field is excluded from canonical identity'
);

$legacyRoundTrip = $legacy->toLegacyUserRecord();
checkCanonical(
    $legacyRoundTrip['firstname'] === 'Example',
    'canonical result reconstructs legacy first name'
);
checkCanonical(
    $legacyRoundTrip['isactive'] === '1',
    'canonical result reconstructs legacy active flag'
);
checkCanonical(
    !array_key_exists('pass', $legacyRoundTrip),
    'legacy session record contains no password field'
);

$inactiveRecord = $legacyRecord;
$inactiveRecord['isactive'] = '0';
$inactive = $legacyAdapter->fromDatabaseRecord($inactiveRecord);
checkCanonical($inactive->isInactive(), 'inactive legacy record is explicit');
checkCanonical(
    !$inactive->isSuccess(),
    'inactive result is not successful'
);

$nativeUser = array(
    'user_id' => 'user-123',
    'username' => 'example',
    'title' => 'Dr',
    'first_name' => 'Example',
    'surname' => 'User',
    'creation_date' => '2026-01-01',
    'email_address' => 'example@example.invalid',
    'login_count' => '7',
    'is_active' => true,
    'access_level' => '1',
    'password_hash' => 'must-never-be-copied',
);

$nativeAdapter = new NativeAuthenticationResultAdapter();
$native = $nativeAdapter->fromUserRecord(
    $nativeUser,
    array('Site Admin'),
    array('administrator'),
    array('view', 'edit'),
    array('source' => 'test')
);

checkCanonical($native->isSuccess(), 'active native record produces success');
checkCanonical(
    $native->getGroups() === array('Site Admin'),
    'native groups are preserved'
);
checkCanonical(
    $native->getPermissions() === array('view', 'edit'),
    'native permissions are preserved'
);
checkCanonical(
    !array_key_exists('password_hash', $native->getIdentity()),
    'native password hash is excluded'
);

$legacyComparable = $legacy->toSnapshotArray();
$nativeComparable = $native->toSnapshotArray();

unset(
    $legacyComparable['provider'],
    $legacyComparable['groups'],
    $legacyComparable['roles'],
    $legacyComparable['permissions']
);
unset(
    $nativeComparable['provider'],
    $nativeComparable['groups'],
    $nativeComparable['roles'],
    $nativeComparable['permissions']
);

checkCanonical(
    $legacyComparable === $nativeComparable,
    'legacy and native core identity snapshots are equivalent'
);

$failure = CanonicalAuthenticationResult::failure(
    'native_database',
    'invalid_credentials'
);
checkCanonical(!$failure->isSuccess(), 'failure result is not successful');
checkCanonical(
    $failure->getReason() === 'invalid_credentials',
    'failure reason is preserved'
);

$guarded = false;
try {
    $failure->toLegacyUserRecord();
} catch (LogicException $exception) {
    $guarded = true;
}
checkCanonical(
    $guarded,
    'failed result cannot establish a legacy session record'
);

echo PHP_EOL;
echo 'Tests: ' . $tests . PHP_EOL;
echo 'Failures: ' . count($failures) . PHP_EOL;

if ($failures !== array()) {
    exit(1);
}

echo 'CANONICAL AUTHENTICATION RESULT TESTS PASSED' . PHP_EOL;
