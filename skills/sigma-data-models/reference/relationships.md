# Relationships

Relationships are pre-defined joins added to the `relationships` array of a table element. They let workbook authors create cross-table analyses without defining joins themselves — the join logic is encoded in the data model.

```json
"relationships": [
  {
    "id": "rel-orders-customers",
    "targetElementId": "<id-of-target-table-element>",
    "keys": [
      {
        "sourceColumnId": "<column-id-in-this-table>",
        "targetColumnId": "<column-id-in-target-table>"
      }
    ],
    "name": "Orders → Customers"
  }
]
```

Both elements must be on the same page. Use the table element `id` values (e.g., `"table-1"`, `"table-2"`) for `targetElementId`.

## Relationship schema

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | |
| `targetElementId` | string | yes | `id` of the related table element on the same page |
| `keys` | array | yes | One or more column pairs defining the join condition |
| `name` | string | no | Display name for the relationship |
| `description` | string | no | |

Each key in `keys`:
- `sourceColumnId` — column ID in this table
- `targetColumnId` — column ID in the target table
