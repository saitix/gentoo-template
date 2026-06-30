# Agent Instructions — gentoo-template

These instructions apply to any AI agent (GitHub Copilot, etc.) working in this repository.

## README maintenance

**Whenever you modify this project, you must also update [README.md](README.md) to reflect those changes.**

Specifically:

- **New or renamed files** → update the _Repository layout_ section.
- **New packages added to `ADDITIONAL_PACKAGES`** → update the _What gets installed_ table.
- **Changes to default configuration values** (`HOSTNAME`, `TIMEZONE`, networking, kernel type, etc.) → update the _Configuration_ section.
- **New scripts or helper utilities** → add an entry under _Helper scripts_.
- **Changes to the install command or workflow** → update the _Quick start_ section.
- **Changes to system requirements** → update the _Requirements_ section.

## General conventions

- `gentoo.conf` is the single source of truth for all installer configuration. Keep it well-commented.
- Scripts must remain compatible with the Gentoo minimal installation CD environment (bash, busybox-like toolset, no Python).
- Do not break the one-liner quick-start command.
- Prefer `set -euo pipefail` at the top of every new shell script.
