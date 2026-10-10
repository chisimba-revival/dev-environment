# Chisimba Revival Development Environment

This repository contains the development environment for Chisimba Revival.

It does not contain Chisimba application source code. It assumes the following sibling repositories exist beside it:

- framework
- modules
- canvases
- shellscripts
- chisimba-info

The purpose of this repository is to assemble and run reproducible Chisimba environments, beginning with a historically faithful legacy environment and later supporting controlled modernisation.

## Background workers after installation

Use the [complete worker installation checklist](docs/workers.md) after deploying
the web application. It covers Communications, registration cleanup, chapter
quizzes, and Worksheet, Essay and Discussion AI marking, including which schedules
are separate and how to verify or stop them.


## Moving development work between computers

Pull `feature/scoped-file-storage` for the development-environment changes;
framework and modules currently use `release/consolidation-20260930`.
The PHP 8.5 image/security changes are versioned development work. The static
baseline contract passes, but a fresh image build and installed-site smoke test
remain required before deploying this image. The local HTTPS policy permits
same-origin camera use for Events check-in; browser permission is still required.

TLS files in `local-https/certs/` are machine-specific and ignored. Existing local
files are retained, but new checkouts must supply `chisimba.test.crt` and
`chisimba.test.key` before starting HTTPS. With mkcert installed, establish the
local CA using `mkcert -install`, then run from this repository:

```sh
mkdir -p local-https/certs
mkcert -cert-file local-https/certs/chisimba.test.crt -key-file local-https/certs/chisimba.test.key chisimba.test localhost 127.0.0.1 ::1
chmod 600 local-https/certs/chisimba.test.key
```

Do not copy a private key from Git history onto another computer; generate a new
local identity. Removing the tracked files does not erase historical copies.
The certificate files on the current development machine were not changed by
this repository cleanup.
