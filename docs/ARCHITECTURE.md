# Development Environment Architecture

The Chisimba Revival development environment is designed around separate source repositories.

The source repositories remain untouched:

- framework
- modules
- canvases
- shellscripts

The dev-environment repository provides tooling only.

## Principles

1. Do not copy application source into this repository.
2. Assemble runtime environments from sibling repositories.
3. Keep historical reproduction separate from modernisation.
4. Prefer scripts and configuration that work from any workspace path.
5. Treat Docker as one backend, not the whole architecture.

## Expected Workspace

chisimba-revival/
├── framework/
├── modules/
├── canvases/
├── shellscripts/
├── dev-environment/
└── chisimba-info/
