# Permissions and Sharing

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Grant or revoke access on individual resources (workbooks, workspaces,
connections, datasets), share workbooks across organizations, mint embed
URLs. Load this when the user asks "how do I give X access to Y" or "how
do I share this externally."

> Provisioning the *principals* (members, teams, attributes) lives in
> [`identity-and-access.md`](identity-and-access.md). This file picks up
> after the principal exists.

The grant model has two surfaces — a top-level inventory (`api grants
…`) and per-resource sub-groups (`api workbooks grants …`, `api
workspaces grants …`, `api connections grants …`, etc.); prefer
per-resource for write paths, top-level for cross-resource audits. Run
`sigma api grants --help` / `sigma api workbooks grants --help` for the
current shape.

## Workflow — grant a team read access to a workbook

`grantee` is a **nested one-of**, not a flat id + type pair: `{"teamId":…}` or
`{"memberId":…}`, and the key itself is what picks the principal kind.

```sh
sigma api workbooks grants create \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json   '{
    "grants":[{
      "grantee":{"teamId":"<YOUR_TEAM_ID>"},"permission":"view"
    }]
  }'
```

Same envelope for `workspaces grants create` (scope spans every document in
the workspace) and `connections grants create` (scope spans every model
built on the connection). Use the narrowest scope that satisfies the
ask.

**`permission` is a different enum per resource** — workbooks take
`view`/`explore`/`edit`, connections take `usage`/`annotate`. A value that's
valid on one resource is rejected on another, so read the enum from the
`grants create` body schema for the resource you're granting on.

**Reads don't mirror writes.** List responses return the principal *flat*, as
sibling `memberId` / `teamId` fields with the unused one `null` — not as the
nested `grantee` the write path requires. Don't reuse a list entry as a create
body, and don't look for `grantee` in output.

## Workflow — audit who has access to a resource

The top-level grants group filters by **grantee or inode** — a member id, a
team id, or the resource's *inode* id, which is not the same thing as its
workbook or connection id. Read the current selectors from
`sigma api schema grants list` before composing the call.

```sh
# By resource — the resource's inode id, not its workbook/connection id
sigma api grants list --params '{"inodeId":"<YOUR_INODE_ID>"}'

# By grantee — this is what finds grants the per-resource lists don't show
sigma api grants list --params '{"userId":"<YOUR_MEMBER_ID>"}'
sigma api grants list --params '{"teamId":"<YOUR_TEAM_ID>"}'
```

At least one selector is required: an unfiltered call returns
`400 User, Team or Inode need to be specified.` No org-wide dump is exposed
today, so a full audit means sweeping members and teams — check
`sigma api grants --help` before assuming that's still true.

A wrong selector name here is the undeclared-parameter hazard in its most
expensive form — it's silently forwarded as a query parameter, so the request
goes out effectively unfiltered and you get a plausible answer to a different
question. Check the name before trusting the result.

**Per-resource lists are not complete.** `connections grants list` shows
connection-root grants only; grants scoped to a connection *path* live
under `connections paths grants list`, and grants held by a member show up
only in a `userId` sweep. An audit built from one surface will read as
"nobody has access" when someone does.

For workspace-level audits, prefer `api workspaces grants list` — the
scoped list is paginated and avoids globbing the whole org.

### Resolving `scope` inodes

Path-scoped grants come back with `inodeType: "scope"`. The forward lookup is
cheap — a `urlId` from `connections paths list` works as-is as a selector:

```sh
sigma api grants list --params '{"inodeId":"<URL_ID_FROM_PATHS_LIST>"}'
```

- **Deduplicate on `grantId`.** The `inodeId` returned is usually not the one
  you queried: an inherited grant reports the connection root, so one grant
  echoes on every path beneath it.
- **A refusal here is informative, not a failure.** `files get` names the type
  (`It is of type: scope`); `connections paths get` echoes a UUID form of the
  same inode. Neither is worth retrying.
- **Don't go backwards.** An inherited grant's root isn't in `connections paths
  list`, so scanning for it can't succeed. Report the raw inode id as
  unresolved, say what you scanned, and let the user finish in the Sigma UI —
  don't guess a database or schema name from context.

`teams list` can return zero teams while grants still reference a built-in team
id such as All Members; `teams get` refuses it with `Cannot get All Members
team`, so take the name from the error text and keep the raw id.

## Workflow — revoke a grant

By grant id (from any list call):

```sh
sigma api grants delete --params '{"grantId":"<YOUR_GRANT_ID>"}'
```

Or scoped to the resource — use this when you don't have the grant id
but do have the grantee + resource:

```sh
sigma api workbooks grants delete \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>","grantId":"<YOUR_GRANT_ID>"}'
```

## Workflow — mint an embed URL with attribute personalization

Embeds give external viewers a signed URL that carries identity +
attribute values without minting a real Sigma account.

```sh
# Read the current body shape first — signing options, role overrides,
# parameter overrides, and fragment passthrough are the most volatile
# fields here — read the body schema first (SKILL.md *Discovery loop* step 3).

sigma api workbooks embeds create \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json "$(cat ./embed.json)"
```

Revoke with `workbooks embeds delete`; list outstanding URLs with
`workbooks embeds list`.

## Workflow — share a workbook to another Sigma organization

Different from cross-tenant deployment (one org, many tenants — see
[`tenancy-and-deployments.md`](tenancy-and-deployments.md)) and from
sharing a *template* (use `shared-templates` instead).

Targets are named by **org slug, not org id**, and the field is a list —
`orgSlugs`. Optional flags on the same body cover whether to copy input-table
data and whether to email the recipient org's admins.

```sh
sigma api workbooks share-cross-org \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json   '{"orgSlugs":["<TARGET_ORG_SLUG>"]}'
```

The receiving org sees a pending entry via `api shared-templates
shared-with-you list` and accepts with `api shared-templates accept`.

## Workflow — schema-scoped grant on a connection

When you want a team to see *one schema* of a warehouse rather than the
whole connection — more granular than `connections grants create`, which
scopes the entire connection.

This operation is keyed by a single `connectionPathId` — it does **not** take
`connectionId` plus a `path` array. That id is the `urlId` from
`connections paths list` (same resolver as the scope-inode section above).

```sh
# 1. Find the path's id
sigma api connections paths list \
  --params '{"connectionId":"<YOUR_CONNECTION_ID>","limit":500}' \
  | jq -r '.entries[] | select(.path == ["WAREHOUSE","SCHEMA"]) | .urlId'

# 2. Grant on it — connection permissions are `usage` or `annotate`
sigma api connections paths grants create \
  --params '{"connectionPathId":"<URL_ID_FROM_STEP_1>"}' \
  --json   '{
    "grants":[{
      "grantee":{"teamId":"<YOUR_TEAM_ID>"},"permission":"usage"
    }]
  }'
```

## Note on favorites

`api favorites …` exposes per-user favorited documents. It's discovery
metadata, not access control — favoriting a workbook the caller can't see
fails. Reach for it when answering "what does this user care about,"
not "what can this user see."

## Cross-references

- Looking up the principal (member or team) before granting →
  [`identity-and-access.md`](identity-and-access.md).
- Promoting access *with* the asset across tenants →
  [`tenancy-and-deployments.md`](tenancy-and-deployments.md).
- Connection discovery / testing / sync — the source-first context for
  connection-path grants above →
  [`connections-and-sources.md`](connections-and-sources.md).
