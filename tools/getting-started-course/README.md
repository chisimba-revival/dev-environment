# Minimal introductory course — 18 October 2026

Commissioned by Derek: a simple private Getting started with Chisimba course on
Chisimba.com, with Derek as teacher and one synthetic student for testing.
Created code `gettingstarted` and username `chisimba_test_student` using canonical
user provisioning, context and group services. No email sent, no public home-page
changes, no messaging code deployment and no additional teaching content.

`setup.php local-check` verified provisioning, teacher/student membership and
rollback on the local PHP 8.5 runtime. `setup.php chisimba-com` completed on the
named production container; it refuses duplicates. Student HTTPS login and
private course entry passed. Private credentials were retrieved to the workspace
private-storage/course-testing directory and the remote temporary copy removed.
Do not commit credentials. The account has a synthetic example.invalid email and
is not intended for password-reset email delivery. Keep the course; the labelled
test account and sample material can be removed later when no longer needed.
