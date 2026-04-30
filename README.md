# Sigma Computing Agent Skills

Multi-provider agent skills for [Sigma Computing](https://sigmacomputing.com). The same shared skill content runs in **Claude Code**, **Cursor**, **OpenAI Codex**, and **Snowflake Cortex Code**.

This repository is a curated, read-only mirror. Pull requests and issues from non-maintainers are auto-closed — please contact Sigma support for questions or feature requests. Releases are tagged `vX.Y.Z`; see [`CHANGELOG.md`](./CHANGELOG.md) for what shipped in each release.

## Installation

### Claude Code

```bash
/plugin marketplace add https://github.com/sigmacomputing/sigma-agent-skills.git
/plugin install sigma-computing@sigma-computing
```

### Cursor

Configure `.cursor-plugin/plugin.json` from this repo as a Cursor plugin source.

### OpenAI Codex

Codex auto-loads `AGENTS.md` from the repo root.

### Snowflake Cortex Code

Inside a Cortex Code session:

```
/skill add https://github.com/sigmacomputing/sigma-agent-skills.git
```

Skills are cached locally and auto-discovered from `.cortex/skills/`. To update to the latest version:

```
/skill sync
```

## Skills

Agents activate these automatically based on the user's request.

| Skill | Description |
|-------|-------------|
| **sigma-api** | Authenticate against the Sigma REST API (OAuth client credentials, bearer tokens, base URL per cloud). Prerequisite for the other skills. |
| **sigma-data-models** | Create, retrieve, or modify a Sigma data model spec (sources, columns, metrics, relationships, filters, controls, folder groupings, column-level security) via the REST API. |

## Team Deployment (Claude Code)

Add this plugin to your project's `.claude/settings.json` so it's available to your whole team automatically:

```json
{
  "extraKnownMarketplaces": {
    "sigma-computing": {
      "source": {
        "source": "github",
        "repo": "sigmacomputing/sigma-agent-skills"
      }
    }
  },
  "enabledPlugins": {
    "sigma-computing@sigma-computing": true
  }
}
```

## License

Apache 2.0 — see [`LICENSE`](./LICENSE).
