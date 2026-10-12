# PEAR retirement — 12 October 2026

The deployable PEAR dependency set is empty. The curated runtime pack and the
framework application PEAR directory have been removed. The builder and historical
PEAR installation scripts refuse execution before changing files.

PDO MySQL is the only supported backend; use Chisimba dbTable and the shared
native schema service. Install pdo_mysql in the container before deploying.
Do not restore PEAR to activate dormant modules: audit and modernise them first.

Historical licensed comparison fixtures remain in framework/tests only. They
must never be copied into a web release. See framework/docs/pear-final-20261012.md
for validation and release boundaries. Old dependency lists and patches describe
history and are not assembly inputs.
