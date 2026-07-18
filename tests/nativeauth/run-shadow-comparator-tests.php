<?php
$root = dirname(__FILE__) . '/../../../';
$auth = $root
    . 'framework/app/core_modules/security/classes/nativeauth/';

require_once $auth . 'nativeauthshadowcomparator.php';

$tests = 0;
$failures = array();

function comparatorCheck($condition, $message)
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

class ComparatorTestConfig
{
    private $path;

    public function __construct($path)
    {
        $this->path = $path;
    }

    public function getcontentBasePath()
    {
        return $this->path;
    }
}

class ComparatorTestUser
{
    public $objConfig;
    private $record;
    private $session;

    public function __construct($path, array $record, array $session)
    {
        $this->objConfig = new ComparatorTestConfig($path);
        $this->record = $record;
        $this->session = $session;
    }

    public function lookupData($username)
    {
        return $this->record;
    }

    public function getSession($key)
    {
        return array_key_exists($key, $this->session)
            ? $this->session[$key] : null;
    }
}

$base = sys_get_temp_dir()
    . '/chisimba-shadow-comparator-'
    . getmypid();
$directory = $base . '/auth-shadow';

mkdir($directory, 0700, true);

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

$session = array(
    'username' => 'example',
    'userid' => 'user-1',
    'title' => 'Dr',
    'name' => 'Example User',
    'logins' => 5,
    'email' => 'example@example.invalid',
    'context' => 'lobby',
    'isAdmin' => true,
);

$user = new ComparatorTestUser($base, $record, $session);
$comparator = new NativeAuthShadowComparator();

comparatorCheck(
    !$comparator->isEnabled($user),
    'comparator is disabled without marker or constant'
);

file_put_contents($directory . '/ENABLED', '');
chmod($directory . '/ENABLED', 0600);

comparatorCheck(
    $comparator->isEnabled($user),
    'marker file explicitly enables comparator'
);

$result = $comparator->compare($user, 'example');

comparatorCheck(is_array($result), 'enabled comparison returns a result');
comparatorCheck($result['match'] === true, 'matching session is reported');
comparatorCheck(is_file($result['target']), 'snapshot file is created');
comparatorCheck(
    substr(sprintf('%o', fileperms($result['target'])), -3) === '600',
    'snapshot file permissions are 0600'
);

unlink($result['target']);
unlink($directory . '/ENABLED');
rmdir($directory);
rmdir($base);

echo PHP_EOL;
echo 'Tests: ' . $tests . PHP_EOL;
echo 'Failures: ' . count($failures) . PHP_EOL;

if ($failures !== array()) {
    exit(1);
}

echo 'SHADOW COMPARATOR TESTS PASSED' . PHP_EOL;
