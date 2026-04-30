# Changelog

All notable changes to this project will be documented in this file.

## v0.1.0 — 2026-04-30

Initial public release of `sigma-agent-skills`.

### Added

- **`sigma-api`** — Authenticate against the Sigma REST API. OAuth client-credentials flow, per-cloud base URLs (AWS US/Canada/Europe/UK, GCP, Azure), bearer token exchange via `scripts/get-token.sh`, and HTTP status-code reference.
- **`sigma-data-models`** — Create, retrieve, and modify Sigma data model specs (sources, columns, metrics, relationships, filters, controls, folder groupings, column-level security) via the REST API.
- Multi-provider packaging: Claude Code plugin (`.claude-plugin/`), Cursor plugin (`.cursor-plugin/`), Snowflake Cortex Code provider metadata (`.cortex-plugin/`), and `AGENTS.md` for OpenAI Codex / Cortex Code session context.
- Cortex Code auto-discovery via `.cortex/skills/` symlinks.
