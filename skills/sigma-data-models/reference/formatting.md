# Column and Metric Formatting

Add a `format` property to any column or metric object to control how values are displayed in the Sigma UI.

## Datetime

```json
{
  "id": "<col-id>",
  "formula": "[<TableName>/Order Date]",
  "format": {
    "kind": "datetime",
    "formatString": "%b %d, %Y"
  }
}
```

Common `formatString` patterns:

| Pattern | Example output |
|---|---|
| `"%Y-%m-%d"` | 2024-03-15 |
| `"%b %d, %Y"` | Mar 15, 2024 |
| `"%m/%d/%Y"` | 03/15/2024 |
| `"%a, %b %d, %Y"` | Fri, Mar 15, 2024 |
| `"%Y-%m-%dT%H:%M:%S"` | 2024-03-15T14:30:00 |

## Number and currency

```json
{
  "id": "<col-id>",
  "formula": "[<TableName>/Revenue]",
  "format": {
    "kind": "number",
    "formatString": "$.2f",
    "decimalSymbol": ".",
    "digitGroupingSymbol": ",",
    "digitGroupingSize": [3],
    "currencySymbol": "$"
  }
}
```

Common `formatString` patterns:

| Pattern | Example output | Use for |
|---|---|---|
| `"$.2f"` | $1,234.56 | Currency (USD) |
| `"€.2f"` | €1,234.56 | Currency (EUR) |
| `",.0f"` | 1,235 | Integer with thousands separator |
| `".2f"` | 1234.56 | Decimal, 2 places |
| `".1%"` | 12.3% | Percentage |
| `".0%"` | 12% | Percentage, no decimals |

Omit `currencySymbol`, `decimalSymbol`, `digitGroupingSymbol`, and `digitGroupingSize` if they are not needed for the format.
