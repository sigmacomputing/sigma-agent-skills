# Source Types

The `source` property of a table element defines where the data comes from. Replace the entire `source` object with the appropriate type for your use case.

## warehouse-table (default)

Direct connection to a warehouse table.

```json
"source": {
  "kind": "warehouse-table",
  "connectionId": "<YOUR_CONNECTION_ID>",
  "path": ["<YOUR_DATABASE>", "<YOUR_SCHEMA>", "<YOUR_TABLE_NAME>"]
}
```

## Custom SQL

Run a raw SQL query against a connection. Columns then reference `[Custom SQL/<Column Name>]` in their formulas.

```json
"source": {
  "kind": "sql",
  "connectionId": "<YOUR_CONNECTION_ID>",
  "statement": "SELECT order_id, customer_id, SUM(price) AS REVENUE FROM orders GROUP BY 1, 2"
}
```

> **Column naming:** The formula prefix `[Custom SQL/...]` must match the **exact output column name** from the SQL query. For Snowflake (the most common warehouse), unquoted column names and aliases are returned in UPPERCASE — e.g., `SUM(price) AS revenue` becomes `[Custom SQL/REVENUE]`. Use double-quoted aliases (e.g., `AS "revenue"`) if you need mixed-case or lowercase column names.

## Join

Combine two table elements using a join. Both source tables must be defined as separate elements on the same page and referenced by their element `id`.

```json
"source": {
  "kind": "join",
  "joins": [
    {
      "left":  { "kind": "table", "elementId": "<left-table-element-id>" },
      "right": { "kind": "table", "elementId": "<right-table-element-id>" },
      "columns": [
        { "left": "[<Left Join Column>]", "right": "[<Right Join Column>]" }
      ],
      "joinType": "inner"
    }
  ],
  "primarySource": { "kind": "table", "elementId": "<primary-table-element-id>" }
}
```

**`joinType` values:** `"inner"`, `"left-outer"`, `"right-outer"`, `"full-outer"`, `"lookup"`

**Join column `op`** (optional, defaults to `=`): `"="`, `"!="`, `"<"`, `"<="`, `">"`, `">="`, `"within"`, `"intersects"`

To use a non-equality join condition, add `"op": "<value>"` alongside `"left"` and `"right"` in a join column object.

**Column formulas in the join element** reference each source element by its `name` field, using `[ElementName/Column Name]`. Use the primary/left element name for columns from that table and the right element name for columns from the joined table. If a column name appears in both, qualify it to disambiguate:

```json
{
  "id": "table-orders-with-customers",
  "kind": "table",
  "name": "Orders with Customers",
  "source": { "kind": "join", "..." : "..." },
  "columns": [
    { "id": "col-order-id",  "formula": "[Orders/Order Id]",   "name": "Order Id" },
    { "id": "col-revenue",   "formula": "[Orders/Revenue]",    "name": "Revenue" },
    { "id": "col-cust-name", "formula": "[Customers/Name]",    "name": "Customer Name" },
    { "id": "col-city",      "formula": "[Customers/City]",    "name": "City" }
  ]
}
```

## Union

Stack rows from multiple sources. `sourceColumns` accepts `null` for columns absent in a given source.

```json
{
  "id": "table-union",
  "kind": "table",
  "source": {
    "kind": "union",
    "sources": [
      { "kind": "table", "elementId": "<element-id-of-source-1>" },
      { "kind": "table", "elementId": "<element-id-of-source-2>" }
    ],
    "matches": [
      { "outputColumnName": "Column A", "sourceColumns": ["[Column A]", "[Column A]"] },
      { "outputColumnName": "Column B", "sourceColumns": ["[Column B]", null] }
    ]
  },
  "columns": [
    { "id": "col-a", "formula": "[Union of 2 Sources/Column A]", "name": "Column A" },
    { "id": "col-b", "formula": "[Union of 2 Sources/Column B]", "name": "Column B" }
  ]
}
```

**Union element `columns` and naming:** The union element's `columns` array uses a self-referential formula prefix. The API auto-generates this prefix as `"Union of N Sources"` where N is the number of sources in the `sources` array (e.g. 2 sources → `"Union of 2 Sources"`, 3 sources → `"Union of 3 Sources"`).

> **Do NOT set a `name` on the union element.** If an explicit `name` is provided, formula validation rejects self-referential column references because the API cannot resolve the element by name during spec creation/update. Leave `name` omitted — the element will be named "Union of N Sources" in the UI and can be renamed manually afterward. Setting `columns: []` avoids the validation error but leaves the table with zero visible columns.

**Use `elementId`-based sources, not direct `warehouse-table` sources.** Direct `warehouse-table` entries in `sources` work for simple column names but fail for columns containing `/` or `-`. Always define intermediate warehouse-table elements and reference them by `elementId`.

**`sourceColumns` reference format:** Each entry is a bare `[Column Name]` resolved within that source element's own column set — use the `name` field of each column in the source element's `columns` array, NOT the raw warehouse column name.

> **`sourceColumns` and special characters:** `sourceColumns` entries are resolved by column name within the source element's own column set, not re-parsed as a Sigma formula expression. Always use the `name` field value of the column in the source element — not the raw warehouse name. With friendly names ON, a warehouse column `Sub-Category` will have `name: "Sub Category"` (space), so reference it as `"[Sub Category]"`. With a SQL source that aliases it as `"Sub-Category"`, the `name` is `Sub-Category` and you reference it as `"[Sub-Category]"`.

- **Warehouse-table source elements:** Sigma normalizes ALL_CAPS single-word names to title case (`SALES` → `Sales`, `REGION` → `Region`), and splits ALL_CAPS underscore-delimited names on `_`, title-casing each part (`CUSTOMER_ID` → `Customer Id`, `FIRST_NAME` → `First Name`). Digits are preserved in place: `PHONE1` → `Phone1`, `STORE_2` → `Store 2`. Mixed-case quoted identifiers resolve as-is (`Order ID` → `Order ID`, `Last Updated` → `Last Updated`).
- **SQL source elements:** The column name is exactly what the SQL outputs (your alias) — no normalization. `SELECT SEGMENT AS "Segment"` produces `[Segment]`; `SELECT "Order ID"` produces `[Order ID]`.

**Example:** A warehouse-table source element on Snowflake's `CUSTOMER_ID`, `FIRST_NAME`, `SALES` columns would be referenced in `sourceColumns` as `"[Customer Id]"`, `"[First Name]"`, `"[Sales]"`.

**Column name casing in `sourceColumns`:** (See normalization rules above.) When in doubt, use the name exactly as returned by `/v2/connections/tables/{tableId}/columns` but convert any fully-uppercase name to title case.

**Column names containing `/`:** How `/` is handled depends on whether **friendly names** are enabled for the org.

- **Friendly names ON (default for most orgs):** Sigma automatically replaces `/` **and** `-` with a space when the column is materialized into an element. `Country/Region` → `Country Region`; `Sub-Category` → `Sub Category`. Reference them with the space form in both column formulas and `sourceColumns` — no SQL workaround needed. This is the most common case.

- **Friendly names OFF:** The `/` is a hard blocker — the Sigma formula engine parses it as a path separator, so there is no formula syntax that can reference such a column at runtime. The only working solution is a `sql` source that aliases the column to a slash-free name:

```json
"source": {
  "kind": "sql",
  "connectionId": "<YOUR_CONNECTION_ID>",
  "statement": "SELECT *, \"Country/Region\" AS \"Country Region\" FROM <DB>.<SCHEMA>.<TABLE>"
}
```

Then define the column using `"formula": "[Custom SQL/Country Region]"` and reference `"[Country Region]"` in `sourceColumns`.

> **Prefer explicit SELECT over `SELECT *`** when using SQL to rename a slash column, to avoid both the original and aliased name appearing as columns. List every column explicitly, aliasing just the problem one.

**Practical guidance:** When building a spec for an org you don't control, assume friendly names are ON unless the user tells you otherwise — use direct warehouse-table elements and reference the column with the `/` replaced by a space.

**Column names containing `-`:** With **friendly names ON** (default), hyphens are automatically replaced with spaces — the same behavior as `/`. A warehouse column named `Sub-Category` materializes as `Sub Category` inside the element. Use `"formula": "[TABLE_NAME/Sub Category]"` and `"name": "Sub Category"`. Reference it as `[Sub Category]` in `sourceColumns`.

With **friendly names OFF**, a hyphen is a hard blocker in formula expressions (treated as subtraction). Use a `sql` source with a double-quoted alias: `"Sub-Category" AS "Sub-Category"` preserves the hyphen cleanly. Then `"formula": "[Custom SQL/Sub-Category]"` and reference as `[Sub-Category]` in `sourceColumns`.

**Other special characters (`%`, `(`, `)`, `#`, `@`):** These have no special meaning in Sigma formula syntax and can appear in column names without issues. `[Profitability (in %)]` is a valid formula reference.

## Transpose — column-to-row

Merge multiple columns into key/value pairs (unpivot).

```json
"source": {
  "kind": "transpose",
  "source": { "kind": "warehouse-table", "connectionId": "<YOUR_CONNECTION_ID>", "path": ["<DB>", "<SCHEMA>", "<TABLE>"] },
  "direction": "column-to-row",
  "columnsToMerge": ["Column A", "Column B", "Column C"],
  "columnLabelForMergedColumns": "Event Type",
  "columnLabelForValues": "Event Time"
}
```

## Transpose — row-to-column

Pivot row values into column headers.

```json
"source": {
  "kind": "transpose",
  "source": { "kind": "warehouse-table", "connectionId": "<YOUR_CONNECTION_ID>", "path": ["<DB>", "<SCHEMA>", "<TABLE>"] },
  "direction": "row-to-column",
  "columnToTranspose": "<column-id-whose-values-become-headers>",
  "valueColumn": "<column-id-for-cell-values>",
  "outputColumns": ["Value A", "Value B", "Value C"],
  "aggregate": "sum"
}
```

**Row-to-column `aggregate` values:** `"min"`, `"max"`, `"count"`, `"count-if"`, `"count-distinct"`, `"sum"`, `"avg"`, `"median"`
