#!/usr/bin/env python3

"""
Update the living documentation for the Chisimba Revival project.

The script manages only sections enclosed by:

    <!-- BEGIN MANAGED: section-name -->
    ...
    <!-- END MANAGED: section-name -->

Material outside those markers remains untouched.

The script is idempotent: running it repeatedly without changing the
declared project state will not produce additional changes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable


SCRIPT_PATH = Path(__file__).resolve()
DEV_ENV_DIR = SCRIPT_PATH.parent.parent
WORKSPACE_DIR = DEV_ENV_DIR.parent
INFO_DOCS_DIR = WORKSPACE_DIR / "chisimba-info" / "docs"
DEPENDENCIES_DIR = DEV_ENV_DIR / "dependencies"

TODAY = dt.date.today().isoformat()

BEGIN_TEMPLATE = "<!-- BEGIN MANAGED: {name} -->"
END_TEMPLATE = "<!-- END MANAGED: {name} -->"


class DocumentationError(RuntimeError):
    """Raised when a documentation update cannot be completed safely."""


def git_output(repository: Path, *arguments: str) -> str:
    """Return Git output, or a readable fallback when unavailable."""
    try:
        result = subprocess.run(
            ["git", "-C", str(repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"

    output = result.stdout.strip()
    return output if output else "unavailable"


def repository_state(repository_name: str) -> tuple[str, str]:
    """Return branch name and abbreviated commit for a repository."""
    repository = WORKSPACE_DIR / repository_name

    if not repository.is_dir():
        return "missing", "missing"

    branch = git_output(repository, "branch", "--show-current")
    commit = git_output(repository, "rev-parse", "--short", "HEAD")

    return branch, commit


def normalise_content(content: str) -> str:
    """Normalise line endings and ensure one trailing newline."""
    return content.replace("\r\n", "\n").replace("\r", "\n").rstrip() + "\n"


def managed_block(name: str, body: str) -> str:
    """Build one complete managed block."""
    return (
        f"{BEGIN_TEMPLATE.format(name=name)}\n"
        f"{body.strip()}\n"
        f"{END_TEMPLATE.format(name=name)}"
    )


def replace_or_append_managed_block(
    content: str,
    name: str,
    body: str,
) -> str:
    """
    Replace an existing managed block or append it safely.

    A malformed block causes a hard failure rather than risking document
    corruption.
    """
    begin = BEGIN_TEMPLATE.format(name=name)
    end = END_TEMPLATE.format(name=name)
    replacement = managed_block(name, body)

    begin_count = content.count(begin)
    end_count = content.count(end)

    if begin_count != end_count:
        raise DocumentationError(
            f"Malformed managed block '{name}': "
            f"{begin_count} BEGIN marker(s), {end_count} END marker(s)"
        )

    if begin_count > 1:
        raise DocumentationError(
            f"Managed block '{name}' appears more than once"
        )

    if begin_count == 1:
        start = content.index(begin)
        finish = content.index(end, start) + len(end)

        return normalise_content(
            content[:start].rstrip()
            + "\n\n"
            + replacement
            + "\n\n"
            + content[finish:].lstrip()
        )

    if content.strip():
        return normalise_content(content.rstrip() + "\n\n" + replacement)

    return normalise_content(replacement)


def write_if_changed(
    path: Path,
    content: str,
    dry_run: bool,
) -> bool:
    """Write a document only when its content has actually changed."""
    content = normalise_content(content)
    existing = ""

    if path.exists():
        existing = normalise_content(
            path.read_text(encoding="utf-8")
        )

    if existing == content:
        print(f"UNCHANGED: {path.relative_to(WORKSPACE_DIR)}")
        return False

    if dry_run:
        action = "WOULD UPDATE" if path.exists() else "WOULD CREATE"
        print(f"{action}: {path.relative_to(WORKSPACE_DIR)}")
        return True

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")

    action = "UPDATED" if existing else "CREATED"
    print(f"{action}: {path.relative_to(WORKSPACE_DIR)}")
    return True


def update_managed_document(
    path: Path,
    sections: Iterable[tuple[str, str]],
    dry_run: bool,
    initial_heading: str | None = None,
) -> bool:
    """Apply one or more managed sections to a document."""
    if path.exists():
        content = path.read_text(encoding="utf-8")
    elif initial_heading:
        content = initial_heading.rstrip() + "\n"
    else:
        content = ""

    for name, body in sections:
        content = replace_or_append_managed_block(
            content,
            name,
            body,
        )

    return write_if_changed(path, content, dry_run)


def build_project_status() -> str:
    """Create the authoritative current-state document."""
    repository_rows = []

    for repository_name in (
        "framework",
        "modules",
        "canvases",
        "dev-environment",
        "chisimba-info",
        "shellscripts",
    ):
        branch, commit = repository_state(repository_name)
        repository_rows.append(
            f"| `{repository_name}` | `{branch}` | `{commit}` |"
        )

    repositories = "\n".join(repository_rows)

    return f"""# Chisimba Revival Project Status

> This is the authoritative current-state document for the project.
> Historical detail belongs in the installation history, modernisation log,
> project notebook, decisions, and architecture documents.

Last updated: **{TODAY}**

## Current phase

**Milestone 6 — Runtime Compatibility and Core Framework Validation**

The immediate objective is to make the installed, logged-in PHP 7.4 Chisimba
runtime reliably usable before beginning the PHP 8 migration.

## Confirmed working baseline

- PHP 7.4.33 Docker runtime starts successfully.
- MySQL 5.5 database service is operational.
- The Chisimba installer completes successfully from a clean installation state.
- The installed system accepts login from the normal front-page login form.
- Authenticated post-login pages load.
- Prelogin Administration opens from the administration side block.
- Module Catalogue opens successfully.
- The curated PEAR runtime is assembled and loaded.
- The runtime assembler builds from `framework`, `modules`, and `canvases`.
- The rebuild process preserves installed state and keeps a rollback runtime.
- The generic reference-construction moderniser removed active `&new` syntax.

## Completed compatibility classes

| Compatibility class | Result |
|---|---|
| Obsolete `=& new`, `= &new`, and `= & new` construction | 598 replacements across 201 files |
| Removed Magic Quotes runtime calls in curated PEAR | Removed and verified |
| Invalid `continue` behaviour in PEAR switch structures | Corrected |
| Legacy PEAR/MDB2 runtime assembly | Curated PHP 7.4-compatible stack in use |
| PHP 7.4 installer database-extension detection | Working with `mysqli` |
| PHP 7.4 installation and login path | Working from the normal front page |

## Confirmed open issues

| Priority | Issue | Current understanding |
|---|---|---|
| High | Core administration and eLearning workflows are not yet comprehensively tested | Continue systematic runtime validation |
| Medium | Top navigation items lead to `/ch/index.php` without module parameters | Side-block links work; likely menu URL generation or JavaScript |
| Medium | One alternate login route triggers the credentials-in-URL security protection | Normal front-page login works |
| Medium | Runtime ownership can prevent rebuilding disposable files | Safe rebuild process and ownership handling require continued hardening |
| Low | Apache reports that no global `ServerName` is configured | Cosmetic development-environment warning |
| Unconfirmed | `imagecreatefrombmp()` redeclaration | Reproduce before changing code |

## Immediate testing sequence

1. Site configuration.
2. User administration.
3. Group administration.
4. Permissions.
5. Context and course creation.
6. File Manager.
7. Blocks and page configuration.
8. Learning-content functionality.
9. Enrolment and course-user workflows.
10. Optional modules only after the core system is stable.

## Working rules

- Begin installer tests from a completely fresh installation state.
- A fresh installer test requires an empty database and no `installdone.txt`.
- Never continue an installer test from a partially populated schema.
- After a successful installation, preserve that state during runtime development.
- Change source repositories, not files inside the disposable assembled runtime.
- After source modernisation, rebuild the runtime before browser testing.
- Prefer generic transformations over repeated individual-file patches.
- Write diagnostic output to:
  `/run/media/derek/main/chisimba-revival/killme.txt`.
- Use Git as the normal source rollback mechanism.
- Keep runtime-generated state separate from assembled application code.

## Runtime pipeline

```text
framework + modules + canvases
              |
              v
       PHP modernisation
              |
              v
       runtime assembly
              |
              v
         Docker Compose
              |
              v
       integration testing
              |
              v
            browser
