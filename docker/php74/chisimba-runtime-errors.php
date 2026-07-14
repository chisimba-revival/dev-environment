<?php
/*
 * Chisimba PHP 7.4 runtime error policy.
 *
 * Legacy warnings, notices, strict messages, and deprecations are logged
 * but not rendered into HTML. Fatal errors remain visible and logged.
 */

$fatalMask = E_ERROR
    | E_PARSE
    | E_CORE_ERROR
    | E_COMPILE_ERROR
    | E_USER_ERROR
    | E_RECOVERABLE_ERROR;

error_reporting($fatalMask);

ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
ini_set('log_errors', '1');

set_error_handler(
    static function (
        int $severity,
        string $message,
        string $file,
        int $line
    ) use ($fatalMask): bool {
        if (($severity & $fatalMask) !== 0) {
            return false;
        }

        error_log(
            'Suppressed legacy PHP warning: '
            . $message
            . ' in '
            . $file
            . ':'
            . $line
        );

        return true;
    }
);
