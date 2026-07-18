<?php
$root = dirname(__FILE__) . '/../../../';
$auth = $root
    . 'framework/app/core_modules/security/classes/nativeauth/';

require_once $auth . 'liveuserbehaviourrecorder.php';
require_once $auth . 'liveuserbehaviourcapturebridge.php';

$tests = 0;
$failures = array();

function checkRecorder($condition, $message)
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

$state = array(
    'authentication' => array(
        'authenticated' => true,
        'method' => 'LiveUser',
    ),
    'identity' => array(
        'user_id' => 'user-1',
        'username' => 'test.user',
        'password_hash' => 'must-not-appear',
        'email' => 'test@example.invalid',
    ),
    'groups' => array('Learners', 'Site Admin'),
    'roles' => array('administrator'),
    'permissions' => array('edit', 'view'),
    'session' => array(
        'session_id' => 'secret-session-id',
        'language' => 'en',
        'nested' => array(
            'csrf_token' => 'secret-token',
            'safe' => 'visible',
        ),
    ),
    'context' => array('context_code' => 'test-context'),
    'language' => array('code' => 'en'),
    'liveuser' => array(
        'class' => 'LiveUser',
        'authId' => 'user-1',
    ),
    'database_queries' => array(
        array(
            'sql' => 'SELECT * FROM tbl_users WHERE username = ?',
            'parameters' => array('test.user'),
        ),
    ),
);

$recorder = new LiveUserBehaviourRecorder();
$snapshot = $recorder->createSnapshot(
    $state,
    array('source' => 'unit-test')
);

checkRecorder(
    $snapshot['identity']['password_hash'] === '[REDACTED]',
    'password hash is redacted'
);
checkRecorder(
    $snapshot['session']['session_id'] === '[REDACTED]',
    'session ID is redacted'
);
checkRecorder(
    $snapshot['session']['nested']['csrf_token'] === '[REDACTED]',
    'nested CSRF token is redacted'
);
checkRecorder(
    $snapshot['session']['nested']['safe'] === 'visible',
    'non-secret nested values remain visible'
);
checkRecorder(
    $snapshot['authentication']['authenticated'] === true,
    'authentication result is retained'
);
checkRecorder(
    $snapshot['identity']['username'] === 'test.user',
    'username is retained for comparison'
);
checkRecorder(
    LiveUserBehaviourCaptureBridge::isEnabled() === false,
    'capture bridge is disabled by default'
);

$directory = sys_get_temp_dir()
    . '/chisimba-auth-recorder-test-'
    . getmypid();
$target = $directory . '/snapshot.json';

$recorder->writeSnapshot($snapshot, $target);

checkRecorder(is_file($target), 'snapshot file is written');
checkRecorder(
    substr(sprintf('%o', fileperms($target)), -3) === '600',
    'snapshot file permissions are 0600'
);

$written = json_decode(file_get_contents($target), true);
checkRecorder(is_array($written), 'written snapshot contains valid JSON');
checkRecorder(
    $written['identity']['password_hash'] === '[REDACTED]',
    'written JSON remains redacted'
);

unlink($target);
rmdir($directory);

echo PHP_EOL;
echo 'Tests: ' . $tests . PHP_EOL;
echo 'Failures: ' . count($failures) . PHP_EOL;

if ($failures !== array()) {
    exit(1);
}

echo 'LIVEUSER RECORDER TESTS PASSED' . PHP_EOL;
