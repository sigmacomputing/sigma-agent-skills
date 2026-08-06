---
name: sigma-cli
description: >-
  Drive the full Sigma Computing REST API surface from the local `sigma`
  binary (Sigma CLI) and its OpenAPI-generated command tree. Use whenever
  the user wants to call any Sigma endpoint from the command line, needs a
  uniform `--params` / `--json` shape across resources, wants to install or
  configure the CLI, or asks about `sigma api …`, `sigma auth login`,
  `list-prefixes`, or `schema`. Prefer this skill over raw `curl` when the
  user has the `sigma` binary installed; fall back to `sigma-api` for OAuth
  fundamentals and direct HTTP.
---

# Sigma CLI (`sigma`)

Installing, authenticating, and driving the Sigma REST API through the local
`sigma` binary — calling convention, discovery, output, and error handling.
Every operation in the published OpenAPI spec gets a corresponding
`sigma api <group> [<sub-group> …] <operation>` command, generated at runtime.

Not in scope: raw HTTP and OAuth fundamentals (`sigma-api` — hand off if the
user wants `curl`), or spec-body authoring for data models (its own skill).

## Sources of truth

The command tree is generated; this skill is commentary layered on top.
**When they disagree, the spec wins.**

- **What exists** → `sigma api list-prefixes`, `sigma api <group> --help`
- **Method, path, parameters** → `sigma api schema <command-path…>`
- **Request / response body shape** → read the spec file directly (*Discovery
  loop*, step 3).

**Operation names, fields, and enum values here are illustrative, not
exhaustive** — the API grows continuously. If you want a capability and don't
see it, assume it may exist and check. Report anything unrecognized verbatim;
never coerce it into a value you do recognize, never flag it as a bug.

`sigma auth …` and the global flags are hand-written CLI surface, so what's
listed here is the whole set. Never present the generated `sigma api …` tree
that way — answer from `list-prefixes` or `--help` instead.

## Topical reference index

| Task | File |
|------|------|
| Find or list things by folder / path, browse the document tree, move or rename files, scope a list to a location rather than a resource type | [`reference/files-and-folders.md`](reference/files-and-folders.md) |
| Manage users and teams, assign user attributes, list account-type permissions, configure SAML | [`reference/identity-and-access.md`](reference/identity-and-access.md) |
| Grant or revoke access on any resource (workbook / workspace / connection / dataset), share workbooks across orgs, manage embed URLs, manage favorites | [`reference/permissions-and-sharing.md`](reference/permissions-and-sharing.md) |
| Build / inspect / update workbooks, work with the spec endpoint, list elements / pages / columns / queries, manage bookmarks, version history, lineage | [`reference/workbook-authoring.md`](reference/workbook-authoring.md) |
| Build / inspect / update data models (and migrate from datasets), spec CRUD, columns / elements / sources / lineage | [`reference/data-model-authoring.md`](reference/data-model-authoring.md) |
| Create / list / test connections, look up paths and tables, swap data sources on workbooks / data-models / templates, manage source-swap-policies | [`reference/connections-and-sources.md`](reference/connections-and-sources.md) |
| One-off exports, scheduled exports, query download, webhook delivery | [`reference/delivery-and-schedules.md`](reference/delivery-and-schedules.md) |
| Trigger and poll materializations, audit materialization schedules (schedules are authored via the workbook/data-model spec) | [`reference/materializations.md`](reference/materializations.md) |
| Multi-tenant orgs, deployment policies, templates / shared templates, organization translations | [`reference/tenancy-and-deployments.md`](reference/tenancy-and-deployments.md) |

Open at most one topical file — `SKILL.md` plus that file is the whole context
for a normal workflow.

## Setup — install and authenticate

Both are one-time. If `sigma auth status` already reports a validating
profile, skip to *Calling convention*.

```sh
brew install sigmacomputing/tap/sigma-computing-cli   # brew upgrade to update
sigma auth login
```

`sigma --version` verifies the install; if it's missing or resolves to another
tool, see *Troubleshooting*.

Bare `auth login` opens a profile picker, or the create flow when no profiles
exist. That flow asks which auth method to use — **OAuth** (browser sign-in,
personal accounts) or **API key** (client credentials, service accounts; create
it in Sigma under **Administration → APIs & embed secrets** first) — then
walks an interactive prompt sequence. Credentials are stored encrypted, never
in a plaintext config file; on systems without a usable OS keyring, set
`SIGMA_CLI_KEYRING_BACKEND=file` to keep the encryption key under
`~/.sigma-cli` instead. `sigma auth --help` lists the rest (status, token,
set-default, rename, delete).

`auth login` is interactive — never attempt to drive it non-interactively. For
headless or CI use, set `SIGMA_BASE_URL`, `SIGMA_CLIENT_ID`, and
`SIGMA_CLIENT_SECRET` instead; they take precedence over stored profiles. See
the `sigma-api` skill for what each variable means and where to find it.

Two seams matter when scripting against auth:

- **`sigma auth token` prints a bare JWT on stdout** — not a JSON wrapper.
  `TOKEN=$(sigma auth token)` is correct; piping it through `jq` empties it and
  you get a 401 that looks like an expired credential.
- **`sigma auth status` writes its report to stderr** and prints nothing on
  stdout (`-f json` included), so parsing it needs `2>&1`. That report is how
  you get the active profile's API host without hardcoding a hostname, which
  a direct `curl` against an endpoint needs.

## Calling convention

Every operation takes the same shape:

```
sigma api <group> [<sub-group> …] <operation>
        [--params '<JSON>']     # path + query + header parameters
        [--json   '<JSON>']     # request body (create/update ops)
        [-f json|table|yaml|csv]
        [-p <profile>]
```

`--params` is a single JSON object bundling **every** path, query, and header
parameter for the operation. `--help` marks it required only when a *path*
parameter is required — required query and header parameters aren't reflected
there, so read requiredness off `schema`, not `--help`.

> **Keys the operation doesn't declare are silently forwarded as query
> parameters — no error, exit 0.** A misspelled parameter name therefore
> returns a plausible-looking wrong answer instead of failing. Confirm names
> against `sigma api schema <command-path…>` before trusting a filtered,
> paginated, or otherwise parameter-dependent result.

The `api` segment is optional, but use it — one spelling keeps every example
copy-pasteable as written.

```sh
# List — no parameters, so no --params
sigma api workbooks list

# Get — path id goes in --params
sigma api workbooks get --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}'

# Create — body in --json
sigma api workbooks create --json '{"name":"My Workbook","folderId":"<YOUR_FOLDER_ID>"}'

# Sub-resources nest under their parent, mirroring the API hierarchy
sigma api connections paths grants list --params '{"connectionPathId":"<YOUR_CONNECTION_PATH_ID>"}'
```

Both flags take a literal JSON string, so substitute a file in the shell:
`--json "$(cat ./workbook-spec.json)"`. Check `--help` for a file-input flag
before assuming that's the only way.

**Mutating operations take effect on the live tenant as soon as they're
accepted.** Before a `delete`, a `revoke`, or an `update` that replaces a spec,
resolve the id to a name and confirm the target with the user — ids are
opaque, so a wrong-but-valid one fails by succeeding on the wrong resource.

## Discovery loop

Use this whenever the user names a resource you haven't touched before, or
whenever a call returns a shape error. The three steps below run one task
end to end — exporting a workbook.

### 1 — Drill into a group

`--help` at any depth enumerates that level's leaves and sub-groups; on a leaf
it shows whether `--params` is required and whether `--json` is accepted.

```sh
sigma api workbooks --help
sigma api workbooks elements columns --help    # sub-groups recurse
sigma api workbooks export --help              # leaf: flags for one operation
```

### 2 — Inspect parameters

`sigma api schema <command-path…>` prints the resolved operation's metadata —
method, path template, summary, and parameters:

```sh
sigma api schema workbooks export
```

The argument is **command segments, not an HTTP path** — `workbooks export`,
not `/v2/workbooks/{workbookId}/export`, which fails with `no command at path`.
The HTTP path template it *reports* is what step 3 needs.

`[path…]` is variadic and swallows trailing flags, so any flag must come
**before** the path segments — `schema --resolve-refs workbooks export`, never
`schema workbooks export --resolve-refs`.

### 3 — Inspect request / response body shape

`sigma api schema` reports only *whether* an operation takes a body, never its
shape — `--resolve-refs` inlines `$ref` pointers but still won't surface body
properties, so it doesn't substitute for reading the spec. For the shape, read
the same spec the CLI resolved against, using the method and path from step 2:

```sh
SPEC="${SIGMA_CLI_OPENAPI_SPEC:-$HOME/.sigma-cli/cache/openapi.json}"

# step 2 gave: .method "POST", .path "/v2/workbooks/{workbookId}/export"
jq '.paths."/v2/workbooks/{workbookId}/export".post.requestBody.content."application/json".schema' "$SPEC"
jq '.paths."/v2/workbooks/{workbookId}/export".post.responses."200".content."application/json".schema' "$SPEC"
```

**Bodies routinely compose with `allOf` / `oneOf`.** Required fields and the
accepted variants are spread across branches, and a field is often an object
where a scalar looks natural (export's `format` is `{"type":"csv"}`, not
`"csv"`). Read every branch before composing a body — don't stop at the first
`properties` block.

If the cache file is missing, any `sigma api …` call repopulates it — it's the
CLI's own runtime source, and outranks every other copy, this skill included.

Resolution order is `$SIGMA_CLI_OPENAPI_SPEC`, then
`~/.sigma-cli/cache/openapi.json`, then `assets.sigmacomputing.com`. On an
air-gapped or proxied machine, download the spec once and point the variable at
it. The cache TTL is 60s, so a stale schema is rarely the cause of a shape
error; `--refresh-spec` forces a redownload if you need to rule it out.

## Global flags

`-f json|table|yaml|csv` — default `json`. `table` handles both shapes (rows
for a list, flattened key/value for a single object); `csv` only makes sense
on a list. `-p <name>` selects a profile; omitted, the profile marked default
is used — *except* `sigma auth login`, where omitting `-p` starts the
create-a-new-profile flow instead. `--refresh-spec` forces a spec redownload.
Any `--help` prints the current set.

`--yaml` is **not** `-f yaml`: it asks the *server* for YAML
(`Accept: application/yaml`) and exits 3 if the endpoint can't produce it,
whereas `-f yaml` renders locally and always works.

Output goes to stdout, so it pipes cleanly:

```sh
sigma api workbooks list | jq '.entries[].name'
sigma api workbooks get --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' > workbook.json
```

## Paginating list results

`page` is a **cursor token, not an offset** — read `nextPage` off the response
and pass it back verbatim. Incrementing an integer is the most expensive
mistake on this surface: the call succeeds and silently re-serves the same
rows, so you get duplicates and no error. Treat the token as opaque; don't
parse, decode, or synthesize it.

**Stop when `nextPage` is absent**, not on a count. `total` and `hasMore`
aren't on every endpoint, and where `total` is present it sometimes counts the
current page rather than the collection.

```sh
PAGE=''
while :; do
  P=$(jq -cn --arg p "$PAGE" '{limit:500} + (if $p == "" then {} else {page:$p} end)')
  RESP=$(sigma api files list --params "$P")
  jq -r '.entries[] | [.id, .name] | @tsv' <<<"$RESP"
  PAGE=$(jq -r '.nextPage // empty' <<<"$RESP")
  [ -n "$PAGE" ] || break
done
```

Collections can be far larger than they look — a single connection's path list
can run to tens of thousands of entries. Bound any sweep you don't need in
full, and say so when you stop early rather than presenting a partial list as
complete.

Use the largest `limit` the endpoint accepts; over-large values are clamped
rather than rejected, and shrinking `limit` only multiplies the call count —
which is how a sweep runs into throttling (*Troubleshooting*).

## Polling async jobs

Some operations return a job handle you poll rather than a result you read
directly. Read the response schema (*Discovery loop*, step 3) to find the
readiness signal before writing a deadline-bounded loop; the topical files
carry worked loops and per-operation traps for the ones they cover.

**Hardcode the *in-progress* set, not the terminal set,** and treat everything
else as terminal. Status fields are open strings, so a value you haven't seen
would otherwise fall into the keep-waiting branch, burn the whole deadline, and
get misreported as a timeout. When a job is terminal but carries no success or
failure marker, report it as indeterminate rather than picking a side.

## Troubleshooting

Errors print as structured JSON on stdout, with a colored label on stderr. Read
the matching entry before retrying — several of these get worse on a blind
retry. Treat any code not listed as failure and surface stderr verbatim.

| Code | Meaning |
|------|---------|
| 0 | Success — see *A call succeeds but the answer looks wrong* |
| 1 | API error (HTTP 4xx/5xx) — three entries below, by what the message says |
| 2 | Authentication error |
| 3 | Local validation error, raised before any request is sent; the message names the cause |
| 4 | Transport, spec fetch, or a response the CLI couldn't parse |

### `command not found: sigma`

SigmaHQ ships an unrelated tool with the same binary name; when it's present
Homebrew won't link Sigma's. If a command name from older docs fails instead,
the binary was renamed — it's `sigma` now.

```sh
brew link --overwrite sigma-computing-cli
```

### Exit 1 with 403 Forbidden

The credential authenticated but isn't permitted for this operation. Check the
role on the credential and the resource-level grants
([`reference/permissions-and-sharing.md`](reference/permissions-and-sharing.md)).

### Exit 1 with a 400 — the body is wrong

Bodies are validated server-side, so a bad field lands here rather than on 3.
Re-read the request body schema (*Discovery loop*, step 3) and compare it
against what you sent, checking **every** `allOf` / `oneOf` branch — required
fields and accepted variants are spread across them. One automated retry with
the corrected shape, then stop and report.

### Exit 1 with an HTML body — you're being throttled

A wall of HTML where a `message` field belongs is an edge/challenge page, not a
malformed request: you're sending too many requests too fast. The CLI has no
backoff of its own, so an immediate retry makes it worse. Stop the loop, report
how far it got, and raise the page `limit` before any resume.

### Exit 2 — authentication error

The profile's credentials are missing, expired, or rejected.

```sh
sigma auth status 2>&1          # active profile, its type, whether it validates
sigma auth login -p <profile>   # refresh it
```

If an API-key profile still fails after a refresh, re-issue the credential in
Sigma under **Administration → APIs & embed secrets**. If no profile is set at
all, `sigma auth login` creates one and `sigma auth set-default <name>` selects
an existing one.

### Exit 4 — transport, spec fetch, or unparseable response

Usually the spec download — on an air-gapped or proxied machine, pin a local
copy (*Discovery loop*, step 3). It also covers a 2xx whose body isn't JSON; the
message says which, and neither case improves on a retry.

### A call succeeds but the answer looks wrong

Undeclared `--params` keys (*Calling convention*) or integer-incremented
pagination (*Paginating list results*). Check parameter names against
`sigma api schema <command-path…>` first — it's the cheaper of the two.

### Debug logging

```sh
SIGMA_CLI_LOG=sigma_cli=debug sigma api connections list   # to stderr
SIGMA_CLI_LOG_FILE=/tmp sigma api connections list         # daily rotating files
```
