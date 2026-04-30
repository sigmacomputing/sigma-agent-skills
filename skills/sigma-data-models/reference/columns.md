# Columns

Columns are defined in the `columns` array of a table element. All columns require `id` and `formula`.

## Warehouse columns

Warehouse columns reference source data with the `[TableName/Column Name]` formula syntax. Their IDs follow the `inode-<tableId>/<COLUMN_NAME>` pattern — use `<YOUR_TABLE_INODE>/<COL_NAME>` as a placeholder until the real inode is known.

```json
[
  { "id": "<YOUR_TABLE_INODE>/ORDER_NUMBER", "formula": "[<YOUR_TABLE_NAME>/Order Number]", "name": "Order Number" },
  { "id": "<YOUR_TABLE_INODE>/PRICE",        "formula": "[<YOUR_TABLE_NAME>/Price]",        "name": "Price" },
  { "id": "<YOUR_TABLE_INODE>/DATE",         "formula": "[<YOUR_TABLE_NAME>/Date]",         "name": "Date" }
]
```

## Calculated columns

Calculated columns use any Sigma formula expression. Use a short descriptive ID.

```json
[
  { "id": "col-profit",   "formula": "[Price] - [Cost]",                                                "name": "Profit" },
  { "id": "col-margin",   "formula": "[Profit] / [Revenue]",                                            "name": "Margin" },
  { "id": "col-lifetime", "formula": "DateDiff(\"day\", Date([Cust Json].CUST_SINCE), Today())",        "name": "Customer Lifetime Days" }
]
```

## Column schema

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Short alphanumeric or `inode-<tableId>/<COL>` pattern |
| `formula` | string | yes | Sigma formula expression |
| `name` | string | no | Display name shown in UI |
| `description` | string | no | Tooltip / description text |
| `hidden` | boolean | no | Hides column from non-admin users when `true` |
| `format` | Format object | no | See [formatting.md](formatting.md) |

---

## Column Reference Rules

Every column formula references either a column **outside** the element or a column **inside** the same element.

### Outside the element — use `[SourceName/column_name]`

The prefix depends on the source type:

- **Warehouse table**: `SourceName` = last segment of the `path` array.
  - Path `["DB", "SCHEMA", "ORDERS"]` → `[ORDERS/revenue]`
  - Path `["ANALYTICS", "PUBLIC", "USERS"]` → `[USERS/email]`

- **Another workbook element**: `SourceName` = that element's `name` field.
  - Element named "Sales Table" → `[Sales Table/Revenue]`

- **Join source**: `SourceName` = the `name` field on a specific join leg, or the top-level `name` on the join object (for the `primarySource` leg).
  - Join with `primarySource.name` implicitly tied to top-level `name: "Sales Star"` → `[Sales Star/Order Number]` for primary columns.
  - Join leg with `name: "Sales"` → `[Sales/Cust Key]` for that joined table's columns.
  - Warehouse path segments do **not** become the prefix inside a join — use the join leg's `name` instead.

- Column names must match exactly what the describe endpoint returns. **Never invent column names.**

### Inside the same element — use `[column_name]` (no prefix)

References a column already defined in this element by its `name` field.

```
// Given columns: "Revenue" (formula: [ORDERS/revenue]), "Cost" (formula: [ORDERS/cost])
// A third column can reference them:
[Revenue] - [Cost]       // valid — references sibling columns by name
Sum([Revenue])           // valid — aggregation over a sibling column
```

**A column cannot reference itself** — that is a circular reference error. This trips up copy-paste: if a column's `name` field matches any bracketed reference inside its own `formula`, the server treats it as circular even when you meant to reference a different column. Rename one side to break the cycle.

### Common mistakes

| Wrong | Correct | Why |
|-------|---------|-----|
| `[revenue]` | `[ORDERS/revenue]` | Missing table prefix for warehouse column |
| `[ORDERS/Total Revenue]` | `[Total Revenue]` | "Total Revenue" is a sibling column, not a warehouse column |
| `[Revenue]` in the "Revenue" column | N/A — circular | A column cannot reference itself |

### Special characters

If you retrieve column names from the `connections/tables/<id>/columns` endpoint, normalize column names by going to title case and removing special characters like `/` and `-` before using them in column references.

For example, `Country/Region` should become `Country Region`, and `Sub-Category` should become `Sub Category`

## Operators

### Arithmetic
`+`, `-`, `*`, `/`, `%` (modulo), `^` (power)

**Do not use** `Power()` or `Mod()` — use `^` and `%` instead.

### Boolean
`and`, `or`, `not`

### String concatenation
`&` (not `+`)

**Do not use** `Concat()` — use `&` instead.

## Aggregation Functions

| Function | Description |
|----------|-------------|
| `Sum([col])` | Sum of values |
| `Avg([col])` | Average of values |
| `Count([col])` | Count of non-null values |
| `CountDistinct([col])` | Count of distinct values |
| `Min([col])` | Minimum value |
| `Max([col])` | Maximum value |
| `Median([col])` | Median value |

## Date Functions

| Function | Example |
|----------|---------|
| `DateTrunc(<part>, <date>)` | `DateTrunc("month", [Date])` |
| `DateDiff(<part>, <start>, <end>)` | `DateDiff("day", [Start], [End])` |
| `DateAdd(<part>, <units>, <date>)` | `DateAdd("month", 3, [Date])` |
| `DateFormat(<date>, <fmt>)` | `DateFormat([Date], "%Y-%m-%d")` |

Date parts (must be quoted strings): `"year"`, `"quarter"`, `"month"`, `"week"`, `"day"`, `"hour"`, `"minute"`, `"second"`

## Conditional

```
If(<condition>, <then>, <else>)
```

Supports multiple conditions (chained):
```
If([Status] = "Active", "Active", [Status] = "Pending", "Pending", "Other")
```

**Do not use** `Case` — use `If` instead.

## Text Functions

| Function | Description |
|----------|-------------|
| `Contains(<text>, <search>)` | True if text contains search |
| `Left(<text>, <n>)` | First n characters |
| `Right(<text>, <n>)` | Last n characters |
| `Upper(<text>)` | Uppercase |
| `Lower(<text>)` | Lowercase |
| `Trim(<text>)` | Remove leading/trailing whitespace |
| `Length(<text>)` | Character count |
| `Replace(<text>, <old>, <new>)` | Replace occurrences |

## Other Functions

| Function | Description |
|----------|-------------|
| `Coalesce(<a>, <b>, ...)` | First non-null value |
| `In([col], "a", "b", "c")` | True if value is in the list |
| `IsNull([col])` | True if null |
| `Null` | Null literal |

## Window Functions

| Function | Description |
|----------|-------------|
| `Rank()` | Rank within partition |
| `RowNumber()` | Row number within partition |
| `Lead(<col>)` | Next row's value |
| `Lag(<col>)` | Previous row's value |
| `RunningSum(<col>)` | Cumulative sum |
| `RunningAvg(<col>)` | Cumulative average |
