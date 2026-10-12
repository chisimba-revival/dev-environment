#!/usr/bin/env bash
# Refuse older automation that would restore retired dependencies.
echo 'PEAR and MDB2 are retired. Use native PDO MySQL; no PEAR pack is required.' >&2
exit 64
