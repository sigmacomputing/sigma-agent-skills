# Changelog

All notable changes to this project will be documented in this file.

## v1.0.0 - 2026-11-09

Workbooks and reports as code reach 1.0, and every skill now uses the content endpoints.

### Added
- **`sigma-reports`** - New `discover` and `generate` workflows, a report builder, and `scaffold-report.rb`, `render-report.rb` and `verify-report.rb` scripts for building and checking a report before it is created.
- **`sigma-workbooks`** - Stack-layout docs and composition lint support for stack layouts.
- **`sigma-workbooks`** - Two new `validate-spec.sh` checks: columns that reference themselves, and list controls with no value source.
- **`sigma-api`** - New `scripts/list-table-columns.sh` to look up a table's columns. The workbook and report workflows use it.

### Changed
- **`sigma-workbooks`**, **`sigma-reports`**, **`sigma-cli`** - Moved off the legacy `/spec` endpoints. Agents read with `GET …?includeContents=true`, validate with `dryRun: true`, create with `contents`, and update with `PUT …/contents`.
- **`sigma-workbooks`** - Example and fixture specs now use `contents:` instead of `document:`. `POST /v2/workbooks` ignores `document:` and creates a blank workbook.
- **`sigma-cli`** - Workbook authoring now uses `workbooks get` with `includeContents` and `workbooks create` with `contents` or `dryRun`. Updates go through `curl` to `PUT …/contents` with the CLI's token. Documented folder creation from the CLI.
- **`sigma-reports`** - Extended the spec validator and documented the report list, reference and inventory endpoints. `waterfall-chart` is now supported.
- **`sigma-data-models`**, **`sigma-workbooks`**, **`sigma-reports`**, **`sigma-cli`** - If a read warns that some content could not be represented, the agent tells the user before updating. The update writes back only what the read returned, so that content would be lost. For a large amount of affected content, the agent gets explicit confirmation first.

## v0.3.1 - 2026-10-26

`sigma-data-models` modeling guidance, a verify step, and corrected CRUD recipes.

### Added
- **`sigma-data-models`** - New `reference/modeling.md` covering grain and fan-out, per-entity totals with `Rollup`, ratio metrics, choosing between a metric and a column, and when to use custom SQL. Guides agents to models whose metrics stay correct at every grouping level.
- **`sigma-data-models`** - Verify step for create and update: read the spec back, compile each element with the element query endpoint, and get the model's link from the spec's `url` field.

### Changed
- **`sigma-data-models`** - Corrected the create and update ID semantics. Submitted IDs that follow the conventions are stored as submitted.
- **`sigma-data-models`** - Fixed the destination-folder lookup, including how to find the user's My Documents folder. Clarified the difference between a table's URL ID and its UUID. Documented connection path pagination and scoping by `connectionId`.
- **`sigma-data-models`** - Reconciled the join column-reference rules between `columns.md` and `sources.md`. Documented joins of three or more elements, relationship direction, cross-element functions, and column name normalization.
- **`sigma-data-models`** - Added team and member ID lookups for column-level security.
- **`sigma-data-models`** - Added a fallback for authenticating with a logged-in `sigma` CLI.

## v0.3.0 - 2026-09-16

Adds `sigma-workbooks` and `sigma-reports` skills.

### Added
- **`sigma-workbooks`** - Create, update, and retrieve workbooks using the Sigma REST API. Helps guide the user to correctly use the API and create arbitrarily complex workbooks.
- **`sigma-reports`** - Create, update, and retrieve workbooks using the Sigma REST API. Helps guide the user to correctly use the API and create arbitarily complex pixel-perfect reports.

### Changed
- **`sigma-api`** - Now offers `scripts/browser-login.sh` to guide the user through an interactive token exchange using the OAuth flow instead of requiring pre-allocated API keys for each user. Depends on the 'can use OAuth for API' feature permission for the user.

## v0.2.0 — 2026-08-06

Adds `sigma-cli` for the Sigma CLI. 

### Added

- **`sigma-cli`** — Drive the Sigma CLI's introspectable command tree (`sigma api …`) for workbooks, data models, connections/sources, files/folders, identity/access, permissions/sharing, delivery/schedules, materializations, and tenancy/deployments. Covers install/auth setup, the discovery loop for finding the right subcommand, global flags, cursor-based pagination, async job polling, and an exit-code/error triage table.

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
