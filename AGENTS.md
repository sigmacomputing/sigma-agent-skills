# Sigma agent skills

Multi-provider agent skills for [Sigma Computing](https://sigmacomputing.com). The same skill content runs in Claude Code, Cursor, OpenAI Codex, and Snowflake Cortex Code.

This repository is a curated, read-only mirror. For questions or feature requests, contact [Sigma Support](https://help.sigmacomputing.com/docs/sigma-support).

## Installation

### Claude Code

```
/plugin marketplace add https://github.com/sigmacomputing/sigma-agent-skills.git
/plugin install sigma-computing@sigma-computing
```

### Cursor

Configure `.cursor-plugin/plugin.json` from this repo as a Cursor plugin source.

### OpenAI Codex

Codex auto-loads this `AGENTS.md` and the `skills/` directory from the repo root.

### Snowflake Cortex Code

Inside a Cortex Code session:

```
/skill add https://github.com/sigmacomputing/sigma-agent-skills.git
```

To update to the latest version:

```
/skill sync
```

## Skills

Agents activate these automatically based on the user's request.

- **sigma-api** — Authenticate against the Sigma REST API (OAuth client credentials, bearer tokens, base URL per cloud). Prerequisite for the other skills.
- **sigma-data-models** — Create, retrieve, or modify a Sigma data model spec (sources, columns, metrics, relationships, filters, controls, folder groupings, column-level security) via the REST API.

See [`README.md`](./README.md) for full details, including team deployment.
