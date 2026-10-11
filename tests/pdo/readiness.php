<?php
/** Prove native MySQL PDO behaviour against a disposable MariaDB database.
 * @author Derek Keats
 */
if (PHP_SAPI !== 'cli' || getenv('CHISIMBA_PDO_FIXTURE') !== '1') {
    exit(64);
}
function check(bool $condition, string $message): void
{
    if (!$condition) throw new RuntimeException($message);
}
check(in_array('mysql', PDO::getAvailableDrivers(), true), 'pdo_mysql is missing');
check(extension_loaded('mysqli'), 'MDB2 still needs mysqli during migration');
$connect = static fn() => new PDO(
    'mysql:host=pdo-db;dbname=pdo_fixture;charset=utf8mb4',
    'root', getenv('CHISIMBA_PDO_PASSWORD'),
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
     PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
     PDO::ATTR_EMULATE_PREPARES => false]
);
$db = $connect();
$other = $connect();
$db->exec('CREATE TABLE probe (id INT PRIMARY KEY, body TEXT NULL) ENGINE=InnoDB');
$value = "Quotation ' backslash \\ Unicode é 中文 🌍";
$insert = $db->prepare('INSERT INTO probe (id, body) VALUES (?, ?)');
check($db->beginTransaction(), 'begin failed');
check($insert->execute([1, $value]) && $insert->rowCount() === 1, 'insert failed');
check((int)$other->query('SELECT COUNT(*) FROM probe')->fetchColumn() === 0, 'uncommitted write visible');
check($db->rollBack(), 'rollback failed');
check((int)$db->query('SELECT COUNT(*) FROM probe')->fetchColumn() === 0, 'rollback lost');
$db->beginTransaction();
$insert->execute([1, $value]);
$insert->execute([2, null]);
check($db->commit(), 'commit failed');
check($other->query('SELECT body FROM probe WHERE id=1')->fetchColumn() === $value, 'Unicode or commit visibility failed');
check($db->query('SELECT body FROM probe WHERE id=2')->fetch() === ['body' => null], 'null/fetch shape changed');
$update = $db->prepare('UPDATE probe SET body=? WHERE id=? AND body=?');
$update->execute(['revised', 1, $value]);
check($update->rowCount() === 1, 'compare-and-set success count wrong');
$update->execute(['stale', 1, $value]);
check($update->rowCount() === 0, 'stale compare-and-set count wrong');
try {
    $insert->execute([1, 'duplicate']);
    throw new RuntimeException('Duplicate key did not throw');
} catch (PDOException $error) {
    check($error->getCode() === '23000', 'unexpected SQLSTATE');
}
check((int)$db->query("SELECT GET_LOCK('pdo_fixture_lock', 0)")->fetchColumn() === 1, 'lock acquisition failed');
check((int)$other->query("SELECT GET_LOCK('pdo_fixture_lock', 0)")->fetchColumn() === 0, 'lock exclusion failed');
check((int)$db->query("SELECT RELEASE_LOCK('pdo_fixture_lock')")->fetchColumn() === 1, 'lock release failed');
echo "PASS: PDO MySQL prepared values, Unicode, nulls, commit/rollback, isolation, affected counts, errors and advisory locks; mysqli retained\n";
