<?php
require_once dirname(__FILE__)
    . '/../../../framework/app/core_modules/security/classes/nativeauth/'
    . 'nativedatabaseadapterinterface.php';

class ArrayDatabaseAdapter implements NativeDatabaseAdapterInterface
{
    private $users;
    private $executions;

    public function __construct(array $users)
    {
        $this->users = $users;
        $this->executions = array();
    }

    public function fetchOne($sql, array $parameters = array())
    {
        if (strpos($sql, 'FROM tbl_users WHERE username = ?') !== false) {
            $username = isset($parameters[0]) ? (string) $parameters[0] : '';
            foreach ($this->users as $user) {
                if (isset($user['username'])
                    && (string) $user['username'] === $username
                ) {
                    return $user;
                }
            }
            return null;
        }

        if (strpos($sql, 'WHERE userid = ? OR id = ?') !== false) {
            $value = isset($parameters[0]) ? (string) $parameters[0] : '';
            foreach ($this->users as $user) {
                $userid = isset($user['userid']) ? (string) $user['userid'] : '';
                $id = isset($user['id']) ? (string) $user['id'] : '';
                if ($userid === $value || $id === $value) {
                    return $user;
                }
            }
            return null;
        }

        throw new RuntimeException('Unexpected test query: ' . $sql);
    }

    public function fetchAll($sql, array $parameters = array())
    {
        throw new RuntimeException('fetchAll() is not used in these tests.');
    }

    public function execute($sql, array $parameters = array())
    {
        $this->executions[] = array(
            'sql' => $sql,
            'parameters' => $parameters,
        );
        return 1;
    }

    public function getExecutions()
    {
        return $this->executions;
    }
}
