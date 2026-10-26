# Modeling: Grain, Fan-out, and Shared Definitions

Load this before composing any model that combines tables or defines metrics. A data model exists so every workbook computes a measure the same way — a definition that's wrong at some grouping level spreads that error to every workbook built on it.

## Pick the grain for each element

The grain is what one row represents: one order line, one order, one customer. Decide it per element before writing formulas.

- A measure whose denominator is an attribute of an entity (square footage of a store, seats on a contract, headcount of a team) belongs on an element at that entity's grain.
- Line-level analysis (trends by month, by product) belongs on an element at line grain.
- A model can and often should have both. Elements on the same page can reference each other.

## Fan-out

Joining a dimension onto a fact repeats the dimension's attributes on every fact row. Any aggregate of those attributes is then weighted by row count.

| Customers | Order lines | `Sum([Credit Limit])` after joining customers onto lines |
|---|---|---|
| A — credit limit 1,000 | 3 lines | 3,000 |
| B — credit limit 1,000 | 1 line | 1,000 |

A metric like `Sum([Line Amount]) / Avg([Credit Limit])` on that join looks right when grouped by customer but is wrong for every group above it — including the grand total. Don't aggregate dimension attributes on a fact-grain element.

## Aggregate onto the entity with `Rollup`

To put a fact total on each entity row, add a `Rollup` column to the entity's element. `Rollup` aggregates rows of another element in the same model by matching keys, so the model stays at one row per entity, with no custom SQL and no join element.

```
Rollup(<aggregate>, <local key>, <external key>[, <local key 2>, <external key 2>, ...])
```

Rollups chain across elements. When amounts live on order lines and only orders carry the customer key, roll lines up to orders, then orders up to customers:

```json
{
  "id": "table-orders",
  "kind": "table",
  "name": "Orders",
  "source": { "kind": "warehouse-table", "connectionId": "<YOUR_CONNECTION_ID>", "path": ["<DB>", "<SCHEMA>", "ORDERS"] },
  "columns": [
    { "id": "<ORDERS_INODE>/ORDER_ID",    "formula": "[ORDERS/Order Id]",    "name": "Order Id" },
    { "id": "<ORDERS_INODE>/CUSTOMER_ID", "formula": "[ORDERS/Customer Id]", "name": "Customer Id" },
    { "id": "col-order-amount", "name": "Order Amount",
      "formula": "Rollup(Sum([Order Lines/Line Amount]), [Order Id], [Order Lines/Order Id])" }
  ]
},
{
  "id": "table-customers",
  "kind": "table",
  "name": "Customers",
  "source": { "kind": "warehouse-table", "connectionId": "<YOUR_CONNECTION_ID>", "path": ["<DB>", "<SCHEMA>", "CUSTOMERS"] },
  "columns": [
    { "id": "<CUSTOMERS_INODE>/CUSTOMER_ID",  "formula": "[CUSTOMERS/Customer Id]",  "name": "Customer Id" },
    { "id": "<CUSTOMERS_INODE>/CREDIT_LIMIT", "formula": "[CUSTOMERS/Credit Limit]", "name": "Credit Limit" },
    { "id": "col-lifetime-amount", "name": "Lifetime Amount",
      "formula": "Coalesce(Rollup(Sum([Orders/Order Amount]), [Customer Id], [Orders/Customer Id]), 0)" }
  ],
  "metrics": [
    { "id": "metric-amount-per-limit", "name": "Amount per Credit Limit",
      "formula": "Sum([Lifetime Amount]) / Sum([Credit Limit])" }
  ]
}
```

- `[Order Lines/...]` and `[Orders/...]` reference other elements by their `name` (see **Column Reference Rules** in `columns.md`).
- `Rollup` returns null for an entity with no matching rows. Wrap it in `Coalesce(..., 0)` when zero is the correct answer.
- The generated SQL is a pre-aggregated left join, so the entity's row count doesn't change. Confirm with the query endpoint in the CREATE **Verify** step (`workflows/crud.md`).
- To filter what's rolled up (for example, exclude returns), filter inside the aggregate: `Rollup(SumIf([Order Lines/Line Amount], [Order Lines/Type] = "Sale"), ...)`.
- Roll up from the base fact elements, not from a join element that includes the target entity — that's a circular dependency.

Use `Lookup` instead of `Rollup` when the match is many-to-one and you want a single value rather than an aggregate.

## "Join X to Y" requests

Users say "join" for two different needs. Cover the one they mean, and usually both:

| Need | Build |
|---|---|
| Slice facts by entity attributes (sales by store region, by month) | A relationship from the fact element to the entity element (`relationships.md`). Workbook authors can then pull store columns onto sales rows without a join element. |
| Per-entity totals and ratios (lifetime revenue per square foot) | `Rollup` columns and ratio metrics on the entity element, as above. |

If you build a flat join element anyway, leave out the dimension's additive attributes (square footage, headcount, rent), so nobody can sum them after the fan-out. Don't put ratio metrics on it.

## Ratio metrics

Write ratios as a ratio of sums: `Sum(<numerator>) / Sum(<denominator>)`. It returns the per-entity value when grouped by entity and the correctly weighted value at every level above, including the total.

If the entity has more than one plausible denominator (selling vs. total square footage, full-time vs. total headcount), that choice is often why existing reports disagree. Ask which one the user means. If you can't ask, pick one, put the column name in the metric's `description`, and tell the user.

Never average a per-row ratio (`Avg([Amount per Limit])`). It weights every entity equally regardless of size and disagrees with the ratio of sums at every level above the entity.

## Metric or column

Define each measure once. Defining a ratio as both a per-row column and a metric gives workbook authors two definitions to drift between.

| Use a | When the value | Example |
|---|---|---|
| Column | Belongs to one row and needs no aggregation to mean something | `DateDiff("month", [Open Date], Today())` |
| Column | Is an input to a metric | `Lifetime Amount` above |
| Metric | Has to roll up across rows | `Sum([Lifetime Amount]) / Sum([Credit Limit])` |

A metric grouped by the entity key returns the per-entity value, so a ratio defined as a metric doesn't also need a column.

The same applies across grains. Define an additive metric like `Revenue` once, on the finest-grain element that holds the amount, and let workbook authors reach it through relationships. Defining `Sum(...)` again on the order and store elements gives three revenue metrics to drift between. The exception is a metric that needs a different grain's columns, like the per-entity ratios above.

Time-relative columns (`Today()`, `Now()`) are evaluated at query time, so "as of today" values stay current without a refresh. The SQL from the query endpoint shows today as a literal timestamp — that's filled in when the SQL is generated, not frozen into the model.

`DateDiff("month", ...)` counts month boundaries crossed, not completed months: a store opened Jan 31 shows 1 month open on Feb 1. Say so in the column `description`. If the user needs completed months, ask.

## When to use custom SQL instead

Prefer warehouse-table elements with `Rollup`, `Lookup`, relationships, and joins. They keep column lineage to the warehouse, work with source swapping, and keep the logic in formulas workbook authors can read.

Use a `sql` source (`sources.md`) only when the logic can't be expressed with elements and formulas — for example, warehouse-specific functions or a window over raw rows that formulas can't express. Tell the user why you chose it and what they give up.
