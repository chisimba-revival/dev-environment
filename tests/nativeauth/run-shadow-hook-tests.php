<?php
$root = dirname(__FILE__) . '/../../../';
$auth = $root
    . 'framework/app/core_modules/security/classes/nativeauth/';

require_once $auth . 'canonicalauthenticationresult.php';
require_once $auth . 'legacyauthenticationresultadapter.php';
require_once $auth . 'liveuserbehaviourrecorder.php';

$tests = 0;
$failures = array();

function shadowCheck($condition, $message)
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

shadowCheck(
    !defined('CHISIMBA_NATIVE_AUTH_SHADOW'),
    'shadow constant is undefined by default'
);

$record = array(
    'username' => 'example',
    'userid' => 'user-1',
    'title' => 'Dr',
    'firstname' => 'Example',
    'surname' => 'User',
    'creationdate' => '2026-01-01',
    'emailaddress' => 'example@example.invalid',
    'logins' => '4',
    'isactive' => '1',
    'accesslevel' => '1',
);

$adapter = new LegacyAuthenticationResultAdapter();
$result = $adapter->fromDatabaseRecord($record);

$expected = $result->toLegacyUserRecord();
$expectedSession = array(
    'username' => $expected['username'],
    'userid' => $expected['userid'],
    'title' => $expected['title'],
    'name' => trim($expected['firstname'] . ' ' . $expected['surname']),
    'logins' => ((int) $expected['logins']) + 1,
    'emailaddress' => $expected['emailaddress'],
    'context' => 'lobby',
    'isadmin' => true,
);

$actual = $expectedSession;
$mismatches = array();

foreach ($expectedSession as $key => $value) {
    if ((string) $actual[$key] !== (string) $value) {
        $mismatches[$key] = array(
            'expected' => $value,
            'actual' => $actual[$key],
        );
    }
}

shadowCheck(
    $mismatches === array(),
    'equivalent session produces no mismatches'
);

$actual['context'] = 'different';
$mismatches = array();

foreach ($expectedSession as $key => $value) {
    if ((string) $actual[$key] !== (string) $value) {
        $mismatches[$key] = array(
            'expected' => $value,
            'actual' => $actual[$key],
        );
    }
}

shadowCheck(
    isset($mismatches['context']),
    'session mismatch is detected'
);

$recorder = new LiveUserBehaviourRecorder();
$snapshot = $recorder->createSnapshot(
    array(
        'authentication' => array(
            'authenticated' => true,
            'shadow_match' => false,
        ),
        'identity' => $result->toSnapshotArray(),
        'session' => array(
            'expected' => $expectedSession,
            'actual' => $actual,
            'mismatches' => $mismatches,
        ),
    )
);

shadowCheck(
    $snapshot['session']['mismatches']['context']['actual']
        === 'different',
    'mismatch is retained in redacted snapshot'
);

echo PHP_EOL;
echo 'Tests: ' . $tests . PHP_EOL;
echo 'Failures: ' . count($failures) . PHP_EOL;

if ($failures !== array()) {
    exit(1);
}

echo 'SHADOW HOOK TESTS PASSED' . PHP_EOL;
