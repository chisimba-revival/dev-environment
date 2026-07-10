# ADR 0001: Preserve the Historical Runtime Boundary

## Status

Accepted

## Context

Chisimba historically consisted of separate framework, modules, canvases and
shellscripts repositories. Installation also depended on system-level PEAR
packages.

Earlier experiments copied and patched dependencies inside the framework tree.
That proved that Chisimba could still execute, but did not provide a clean or
reproducible restoration strategy.

## Decision

The revival environment will:

- preserve the historical repositories separately;
- install PEAR dependencies globally in the container;
- assemble the runtime outside the application repositories;
- avoid modifying historical source merely to satisfy the development environment;
- establish a working historical baseline before modernisation.

## Consequences

The initial Docker profile will use obsolete and unsupported software.

It must only be used for local development and historical verification.

Once the baseline works, later profiles will modernise PHP, database access and
dependency management in controlled steps.
