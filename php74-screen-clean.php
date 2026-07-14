<?php
/*
 * Temporary PHP 7.4 restoration aid.
 *
 * Keep fatal errors visible in the browser, but suppress legacy warnings,
 * notices, deprecations, and strict messages that destroy the Chisimba UI.
 * All PHP errors remain available through the container/Apache logs.
 */

error_reporting(
    E_ERROR
    | E_PARSE
    | E_CORE_ERROR
    | E_COMPILE_ERROR
    | E_USER_ERROR
    | E_RECOVERABLE_ERROR
);

ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
ini_set('log_errors', '1');

/*
 * Included legacy files can emit warnings/notices despite application-level
 * settings. Swallow only non-fatal categories. Fatal errors are not handled
 * here and therefore remain visible.
 */
set_error_handler(
    static function (
        int $severity,
        string $message,
        string $file,
        int $line
    ): bool {
        $fatalMask = E_ERROR
            | E_PARSE
            | E_CORE_ERROR
            | E_COMPILE_ERROR
            | E_USER_ERROR
            | E_RECOVERABLE_ERROR;

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
