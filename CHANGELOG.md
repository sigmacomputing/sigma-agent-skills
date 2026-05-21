# Changelog

All notable changes to this project will be documented in this file.

## v0.1.3 — 2026-05-21

`sigma-api` base-URL allowlist resynced with the current published hosts.

### Changed

- **`sigma-api`** — `scripts/get-token.sh` allowlist now matches the 12-row Base URL table in `SKILL.md`: adds AWS US East / AU Sydney, Azure US/Europe/Canada/UK, and GCP Saudi Arabia, and corrects stale AWS Canada/Europe/UK and Azure US hostnames. Tightened the `SKILL.md` copy pointing users at **Administration → Developer Access** for their base URL.

## v0.1.2 — 2026-05-01

`sigma-api` region/base-URL list synced with the Sigma help docs.

### Changed

- **`sigma-api`** — Replaced the 6-row Base URL table with the full 12-row list from [Supported regions, data platforms, and features](https://help.sigmacomputing.com/docs/region-warehouse-and-feature-support) and linked that page as the source of truth. Adds US East, AU Sydney, three new Azure regions (Europe, Canada, UK), and GCP Saudi Arabia. Corrects stale AWS Canada/Europe/UK and Azure US hostnames.

## v0.1.1 — 2026-04-30

Security hardening for `sigma-api/scripts/get-token.sh` and minor copy edits.

### Changed

- **`sigma-api`** — `scripts/get-token.sh` now pins `$SIGMA_BASE_URL` to the published Sigma cloud hosts, strips the newline `base64` inserts at 76 columns, validates the returned token against the RFC 6750 bearer-token alphabet, and quotes the token via `printf %q` before emitting the `export` line. Together these prevent a hostile or spoofed token endpoint from injecting shell metacharacters into the caller's `eval`.
- **`sigma-data-models`** — Reworded the Requirements line in `SKILL.md` to describe API-credential permissions in terms of Sigma capabilities (create/edit data models, "Can edit" on the folder), and to point users at their Sigma admin on 403.

## v0.1.0 — 2026-04-30

Initial public release of `sigma-agent-skills`.

### Added

- **`sigma-api`** — Authenticate against the Sigma REST API. OAuth client-credentials flow, per-cloud base URLs (AWS US/Canada/Europe/UK, GCP, Azure), bearer token exchange via `scripts/get-token.sh`, and HTTP status-code reference.
- **`sigma-data-models`** — Create, retrieve, and modify Sigma data model specs (sources, columns, metrics, relationships, filters, controls, folder groupings, column-level security) via the REST API.
- Multi-provider packaging: Claude Code plugin (`.claude-plugin/`), Cursor plugin (`.cursor-plugin/`), Snowflake Cortex Code provider metadata (`.cortex-plugin/`), and `AGENTS.md` for OpenAI Codex / Cortex Code session context.
- Cortex Code auto-discovery via `.cortex/skills/` symlinks.
