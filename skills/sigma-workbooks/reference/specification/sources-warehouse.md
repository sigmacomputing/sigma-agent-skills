# Warehouse Table Source

The `warehouse-table` source is the most common source kind — raw data from a warehouse connection. Virtually every workbook starts with at least one element sourced from a warehouse table (or from an element that is, via `kind: "table"` / `kind: "join"`).

For the canonical schema:

```bash
jq --arg k warehouse-table 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

This file covers: path formats per warehouse (which the OpenAPI describes loosely), formula-prefix conventions (which it doesn't describe at all), and the special-character / friendly-name pitfalls.

See `reference/workflows/discover.md` for how to find the `connectionId` and `path` via the REST API.

## Shape

```yaml
kind: warehouse-table
connectionId: <conn-uuid>
path: [DATABASE, SCHEMA, TABLE]
```

## Formula References

Column formulas reference warehouse columns via the **last segment of the path array**:

- Path `["SALES_DB", "PUBLIC", "ORDERS"]` → `[ORDERS/revenue]`, `[ORDERS/order_date]`
- Path `["ANALYTICS", "CORE", "USERS"]` → `[USERS/email]`

Inside a `join` source, warehouse path segments are **not** used as prefixes — use the join leg's `name` instead. See `sources.md` > join section.

## Path Formats by Warehouse

| Warehouse | Path format |
|---|---|
| Snowflake | `["DATABASE", "SCHEMA", "TABLE"]` |
| BigQuery | `["PROJECT", "DATASET", "TABLE"]` |
| Databricks | `["CATALOG", "SCHEMA", "TABLE"]` |
| Redshift | `["SCHEMA", "TABLE"]` |
| PostgreSQL / MySQL | `["SCHEMA", "TABLE"]` |

## Common Pitfalls

- **Column names with special characters** — Sigma accepts discovered raw names
  and may normalize them on readback. Never hand-transform one before POST;
  use the exact discovered name, then use the returned GET-spec form for later
  edits. See `formulas.md` > Raw warehouse names.
- **Inventing column names** — don't. Only reference columns the user has supplied or confirmed.
- **Wrong path depth** — a warehouse table's path must be exactly the depth its warehouse uses (e.g., Snowflake is always 3; Postgres is always 2). Use `/v2/connection/<id>/lookup` to resolve ambiguity.
