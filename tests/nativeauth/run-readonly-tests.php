<?php
$root = dirname(__FILE__) . '/../../../';
$auth = $root
    . 'framework/app/core_modules/security/classes/nativeauth/';

require_once dirname(__FILE__) . '/arraydatabaseadapter.php';
require_once $auth . 'nativeuserrepository.php';
require_once $auth . 'nativepasswordverifier.php';

$tests = 0;
$failures = array();

function check($condition, $message)
{
    global $tests, $failures;
    $tests++;
    if (!$condition) {
        $failures[] = $message;
        echo "FAIL: " . $message . PHP_EOL;
        return;
    }
    echo "PASS: " . $message . PHP_EOL;
}

$modernHash = password_hash('modern-secret', PASSWORD_DEFAULT);
$users = array(
    array(
        'id' => 'row-1',
        'userid' => 'user-1',
        'username' => 'active-md5',
        'pass' => md5('legacy-secret'),
        'isactive' => '1',
        'puid' => '1',
        'emailaddress' => 'one@example.invalid',
        'firstname' => 'Active',
        'surname' => 'User',
        'accesslevel' => 'user',
        'howcreated' => 'local',
        'logins' => '4',
        'last_login' => null,
    ),
    array(
        'id' => 'row-2',
        'userid' => 'user-2',
        'username' => 'inactive-modern',
        'pass' => $modernHash,
        'isactive' => '0',
        'puid' => '2',
        'emailaddress' => 'two@example.invalid',
        'firstname' => 'Inactive',
        'surname' => 'User',
        'accesslevel' => 'user',
        'howcreated' => 'local',
        'logins' => '0',
        'last_login' => null,
    ),
);

$adapter = new ArrayDatabaseAdapter($users);
$repository = new NativeUserRepository($adapter);
$verifier = new NativePasswordVerifier();

$user = $repository->findByUsername('active-md5');
check(is_array($user), 'findByUsername returns a canonical record');
check($user['user_id'] === 'user-1', 'userid is the canonical user identifier');
check($user['password_hash'] === md5('legacy-secret'), 'pass maps to password_hash');
check($user['is_active'] === true, 'active values normalise to boolean true');
check($repository->isUserActive('user-1') === true, 'active user is recognised');
check($repository->isUserActive('user-2') === false, 'inactive user is rejected');
check($repository->findByUsername('missing') === null, 'unknown username returns null');

check(
    $verifier->identifyHashScheme(md5('legacy-secret')) === 'md5',
    'MD5 format is identified'
);
check(
    $verifier->verify('legacy-secret', md5('legacy-secret')),
    'correct MD5 password verifies'
);
check(
    !$verifier->verify('wrong', md5('legacy-secret')),
    'wrong MD5 password fails'
);
check(
    $verifier->identifyHashScheme(sha1('sha-secret')) === 'sha1',
    'SHA-1 format is identified'
);
check(
    $verifier->verify('sha-secret', sha1('sha-secret')),
    'correct SHA-1 password verifies'
);
check(
    $verifier->identifyHashScheme($modernHash) === 'password_hash',
    'password_hash format is identified'
);
check(
    $verifier->verify('modern-secret', $modernHash),
    'correct password_hash password verifies'
);
check(
    !$verifier->verify('wrong', $modernHash),
    'wrong password_hash password fails'
);
check(
    !$verifier->verify('anything', 'plaintext-password'),
    'unknown/plaintext format fails closed'
);
check(
    $verifier->needsRehash(md5('legacy-secret')),
    'legacy MD5 hash is marked for future rehash'
);

$writeGuarded = false;
try {
    $repository->updatePasswordHash('user-1', $modernHash);
} catch (RuntimeException $exception) {
    $writeGuarded = true;
}
check($writeGuarded, 'repository writes are disabled by default');
check(
    count($adapter->getExecutions()) === 0,
    'read-only tests executed no database writes'
);

$newHash = $verifier->createHash('new-secret');
check(
    $verifier->verify('new-secret', $newHash),
    'new password_hash output verifies'
);

echo PHP_EOL;
echo 'Tests: ' . $tests . PHP_EOL;
echo 'Failures: ' . count($failures) . PHP_EOL;

if ($failures !== array()) {
    exit(1);
}

echo 'READ-ONLY NATIVE AUTH TESTS PASSED' . PHP_EOL;
