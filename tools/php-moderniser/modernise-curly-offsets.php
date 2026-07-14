<?php
declare(strict_types=1);

/*
 * Disabled intentionally.
 *
 * The previous curly-offset pass corrupted valid PHP string interpolation,
 * including SQL-building expressions such as "{$comma}{$fieldName}".
 *
 * Genuine legacy curly offsets must be handled by a redesigned,
 * independently tested transformer before this pass is enabled again.
 */

echo "Curly-offset moderniser is disabled to protect valid interpolation.\n";
exit(0);
