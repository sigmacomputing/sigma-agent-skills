---
name: sigma-data-models
description: >-
  Create, retrieve, or modify a Sigma data model spec (the JSON/YAML
  semantic-layer definition with sources, columns, metrics, relationships,
  filters, controls, folder groupings, and column-level security) by calling
  the Sigma REST API directly. Use when the user wants to author a new data
  model from a description, export/inspect/download an existing model's spec,
  edit columns or metrics, change a model's source, add relationships or
  row-level filters, or otherwise round-trip a data model through code.
  Requires an SIGMA_API_TOKEN — obtain via the sigma-api skill first.
---

# Sigma Data Models (Create / Get / Update)

Round-trip a Sigma data model spec — the JSON definition of pages, sources, columns, metrics, relationships, filters, controls, folder groupings, and column-level security — through the Sigma REST API.

**Auth:** Authenticate via the `sigma-api` skill first to set `$SIGMA_BASE_URL` and `$SIGMA_API_TOKEN`. This skill assumes both are already exported.

**Requirements:** `curl`, `jq`, `base64`; admin account type; developer API credentials; document owner or "Can edit" access on the destination folder (create) or the existing data model (update).

## Reference Index

Feature-specific JSON patterns live in `reference/`. Load each file when you identify the corresponding feature in the user's request — don't read every file up-front.

| File | When to load |
|------|--------------|
| `reference/columns.md` | Calculated columns, formula columns, derived columns; **renaming a column, changing a formula**, warehouse-column ID conventions, column reference rules. |
| `reference/metrics.md` | Metrics, aggregate measures, metric timelines, time-series / trend metrics; **adding a metric to an existing table or changing aggregation**. |
| `reference/relationships.md` | Relationships, foreign-key linking, related tables, cross-table lookups; **adding a relationship between an existing element and a new one** (mixed-ID rule — see `workflows/crud.md`). |
| `reference/sources.md` | Custom SQL sources, join sources, union sources, transpose sources; **swapping a model's source kind** on an existing model. |
| `reference/filters.md` | Row filters, where clauses, date range filters, top-N; **adding/removing a filter on an existing model**. |
| `reference/folders-groupings.md` | Folders, column groupings, column ordering, sort, organize columns; **reordering existing columns**. |
| `reference/column-level-security.md` | Column-level security (CLS), data masking, restrict columns by team / user attribute; **applying CLS to an existing column**. |
| `reference/controls.md` | List/dropdown, text input, text area, number input, number range, date, date range, slider, range slider, segmented, switch, checkbox, top-N controls; **adding a control to an existing page**. |
| `reference/formatting.md` | Column or metric formatting — currency, percentage, date format, decimals, datetime; **reformatting a column or metric on an existing model**. |

## Workflows Index

| File | When to load |
|------|--------------|
| `reference/workflows/crud.md` | Authoring a new model, retrieving an existing model's spec, or modifying / editing / adding to / changing the source of an existing model. Always load before any POST / GET / PUT against `/v2/dataModels` endpoints. Contains the ID-semantics contrast table (CREATE remap vs GET source-of-truth vs UPDATE preserve), full step-by-step CREATE / GET / UPDATE recipes, and the mixed-ID rule for relationships in updates. |

## ID Conventions

Cross-cutting rules. Per-workflow ID semantics (remap vs preserve vs mixed cross-references) live in `reference/workflows/crud.md`.

- Short alphanumeric IDs for generated entities: `"page-1"`, `"table-orders"`, `"col-revenue"`.
- Warehouse column IDs follow `"inode-<tableId>/<COLUMN_NAME>"` — use `"<YOUR_TABLE_INODE>/<COL_NAME>"` as a placeholder.
- Control `id` is the element ID; `controlId` is the formula reference name — keep them distinct.

## Unsupported Features

Call out any of these before presenting the final spec:

- Multiple tables with identical names in the same data model
- Input tables, Python elements, and UI elements
- Referencing Sigma elements in custom SQL
- Partial updates — the create and update endpoints both require the full representation
