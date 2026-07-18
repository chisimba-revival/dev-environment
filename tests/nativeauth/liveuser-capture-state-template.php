<?php
/**
 * TEMPLATE ONLY — not loaded by Chisimba.
 *
 * A future, explicit hook will populate these fields from verified runtime
 * APIs after a successful login. Do not include passwords or raw cookies.
 */
return array(
    'authentication' => array(
        'authenticated' => false,
        'method' => 'LiveUser',
    ),
    'identity' => array(
        'user_id' => null,
        'username' => null,
        'email' => null,
        'is_active' => null,
    ),
    'groups' => array(),
    'roles' => array(),
    'permissions' => array(),
    'session' => array(),
    'context' => array(),
    'language' => array(),
    'liveuser' => array(),
    'database_queries' => array(),
);
