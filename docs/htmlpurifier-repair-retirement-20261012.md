# Retired HTML Purifier repair scripts

Removed `tools/fix-htmlpurifier-autoload.sh` and
`tools/fix-htmlpurifier-autoload-v2.sh`. These were one-off patches for the former
HTML Purifier 4.2.0 library and local PHP 8.2 assembly. They have no executable
callers in the dev-environment source. Historical documentation may still name
them as work performed at the time.

The framework now bundles upstream HTML Purifier 4.19.1 and its supported
autoloader. New assemblies must copy that complete versioned vendor tree, without
running old repair scripts. The scripts remain recoverable from Git history.
This retirement changes neither running containers nor deployment configuration.
