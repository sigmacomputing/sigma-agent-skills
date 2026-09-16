# Column Formats

Recipe for column-level `format` objects + the d3-format / strftime conventions Sigma uses. A `format` object is either `kind: number` or `kind: datetime`. For the canonical schema of each:

```bash
jq --arg k number   'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
jq --arg k datetime 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

`format` is optional on every column — omit it for raw values. This file is mainly the cheat sheet of common format strings (currency, percentages, dates) since the OpenAPI doesn't enumerate them.

## Number Formats

```yaml
kind: number
formatString: "$,.0f"
```

Common format strings (d3-format conventions):

| String | Example output | Description |
|--------|----------------|-------------|
| `"$,.0f"` | `$1,234` | Currency, no decimals |
| `"$,.2f"` | `$1,234.56` | Currency, 2 decimals |
| `",.0f"` | `1,234` | Integer with thousands separator |
| `",.2f"` | `1,234.56` | Number, 2 decimals |
| `",.2%"` | `12.34%` | Percentage, 2 decimals |
| `".3~e"` | `1.23e+3` | Scientific, 3 significant digits |

Format-string cheat sheet:
- `$` — currency prefix
- `,` — thousands separator
- `.<n>f` — fixed decimal places
- `.<n>%` — percent with decimals (value × 100)
- `.<n>~e` — scientific with trimmed trailing zeros

Alternatively, build a number format from **structured fields** instead of (or alongside) a raw `formatString` — e.g. `prefix`, `suffix`, `displayNullAs`, `currencySymbol`, `decimalSymbol`, `digitGroupingSymbol`. See the `kind: number` recipe above for the full set.

## Datetime Formats

```yaml
kind: datetime
formatString: "%b %Y"
```

Common format strings (strftime conventions):

| String | Example output | Description |
|--------|----------------|-------------|
| `"%Y-%m-%d"` | `2026-04-21` | ISO date |
| `"%b %Y"` | `Apr 2026` | Short month + year |
| `"%B %Y"` | `April 2026` | Full month + year |
| `"%Y-%m-%d %H:%M"` | `2026-04-21 14:30` | ISO datetime |
| `"%a, %b %-d"` | `Tue, Apr 21` | Short day + month + day (no zero pad) |

Tokens:
- `%Y` — 4-digit year · `%y` — 2-digit year
- `%m` — month number (01–12) · `%-m` — unpadded · `%b` — short name · `%B` — full name
- `%d` — day of month · `%-d` — unpadded
- `%H` / `%I` — 24h / 12h hour · `%M` — minutes · `%S` — seconds
- `%a` / `%A` — short / full weekday

## Where Format Goes

Inline on any column:

```yaml
id: col-sales
name: Sales
formula: Sum([Master/Sales Amount])
format:
  kind: number
  formatString: "$,.0f"
```
