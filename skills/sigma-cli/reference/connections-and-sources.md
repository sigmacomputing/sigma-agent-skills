# Connections and Sources

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Manage the data plumbing — warehouse connections, the schema/table paths
under them, source-discovery for spec authoring, and the operations that
swap one source for another across workbooks, data models, and
templates. Load this when the user wants to add or test a connection,
discover a table, repoint an asset from staging to prod, or define a
recurring swap policy.

Everything here lives under `sigma api connections …`, plus
`source-swap-policies` and the cross-resource `*-swap-sources` ops on
`workbooks` / `data-models` / `templates`. Run
`sigma api connections --help` for the current shape.

Connection bodies are warehouse-specific (Snowflake / BigQuery /
Databricks / Postgres each take different fields). For any
create/update, read the request body schema from the spec
(`SKILL.md` *Discovery loop* step 3) and inspect the discriminated union before
composing a body.

## Workflow — discover a warehouse table for use in a spec

The standard preamble before authoring a workbook or data-model spec.

```sh
# 1. Find the connection
sigma api connections list \
  | jq '.entries[] | select(.type == "snowflake")'

# 2. Resolve the warehouse path to an inode. `path` is the request *body*;
#    only `connectionId` is a parameter. Returns {kind, inodeId, url}.
sigma api connections lookup \
  --params '{"connectionId":"<YOUR_CONNECTION_ID>"}' \
  --json   '{"path":["DATABASE","SCHEMA","TABLE"]}'

# 3. Read the columns — keyed by the inodeId from step 2, not by path
sigma api connections tables columns list \
  --params '{"tableId":"<INODE_ID_FROM_LOOKUP>"}'
```

Never invent column names — only use the `name` values `columns list`
returned. This operation paginates on `pageToken`/`pageSize` rather than the
`page`/`limit` pair most list endpoints use; confirm with
`sigma api schema connections tables columns list` before writing a loop.

`lookup`'s `kind` tells you what you resolved — `table` is what step 3 wants;
a `scope` means you named a database or schema rather than a table.

## Workflow — test a connection

```sh
sigma api connections test get --params '{"connectionId":"<YOUR_CONNECTION_ID>"}'
```

The response is two independent verdicts, not one boolean: `read` is
`SUCCESS` or `FAILED`, and `write` adds `DISABLED` for a connection with
write-back turned off. Report both — a connection that reads fine but can't
write is a working connection for querying and a broken one for input tables.
Treat 4xx with a structured error as a credential / network problem; surface
the error verbatim to the user.

## Workflow — repoint a workbook from staging to prod

The body maps **ids to ids** — it does not take warehouse paths. Two
independent arrays: `connectionMapping` repoints a whole connection,
`sourceMapping` repoints one table (with optional `columnMapping` /
`metricMapping` when names differ on the far side).

```sh
# 1. See current sources
sigma api workbooks sources list --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}'

# 2a. Swap the whole connection — the usual staging → prod move
sigma api workbooks swap-sources \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json   '{"connectionMapping":[
    {"fromId":"<STAGING_CONNECTION_ID>","toId":"<PROD_CONNECTION_ID>"}
  ]}'

# 2b. Or swap one table. Resolve each path to an inodeId with
#     `connections lookup` first (first workflow above).
sigma api workbooks swap-sources \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json   '{"sourceMapping":[
    {"fromId":"<OLD_INODE_ID>","toId":"<NEW_INODE_ID>"}
  ]}'
```

`data-models swap-sources` and `templates swap-sources` take the same body
against `dataModelId` / `templateId`.

For repeated promotions, a **source-swap policy** is a stored mapping you
reference from elsewhere rather than pass to `swap-sources`:

```sh
sigma api source-swap-policies create --params '{}' --json "$(cat ./policy.json)"
```

The resulting id is consumed as `sourceSwapPolicyId` on a connection body, and
as `sourceSwapPolicies` (an array) on a deployment-policy body — which is how
one mapping gets reused across every document a deployment promotes
([`tenancy-and-deployments.md`](tenancy-and-deployments.md)). Read both bodies
per `SKILL.md` *Discovery loop* step 3.

## Workflow — refresh a connection's schema cache

When a new warehouse table isn't visible in Sigma. `path` is a **required body
field**, so this call needs a `--json` — an empty array syncs the entire
connection, a populated one narrows to a database, schema, or table.

```sh
# Whole connection
sigma api connections sync \
  --params '{"connectionId":"<YOUR_CONNECTION_ID>"}' --json '{"path":[]}'

# Just the schema the new table landed in
sigma api connections sync \
  --params '{"connectionId":"<YOUR_CONNECTION_ID>"}' \
  --json   '{"path":["DATABASE","SCHEMA"]}'
```

This refreshes the schema cache, not query results — for that, see
[`materializations.md`](materializations.md).

## Cross-references

- Connection / path grants in the access-control context, including the
  schema-scoped-grant recipe → owned by
  [`permissions-and-sharing.md`](permissions-and-sharing.md).
- Per-data-model swaps in the authoring context →
  [`data-model-authoring.md`](data-model-authoring.md).
