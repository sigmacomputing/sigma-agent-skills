# Filters

Row filters restrict which rows are included in a table element's results. They are defined in the `filters` array of the table element.

## Number range

```json
{
  "id": "filter-price",
  "columnId": "<column-id>",
  "kind": "number-range",
  "min": 100,
  "max": 500,
  "includeNulls": "when-no-value-is-selected"
}
```

## Date range

Date range filters support two modes. Use `"between"` for a start/end window and `"on"` for a single date.

```json
{
  "id": "filter-date-window",
  "columnId": "<column-id>",
  "kind": "date-range",
  "mode": "between",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-12-31T23:59:59Z",
  "includeNulls": "when-no-value-is-selected"
}
```

```json
{
  "id": "filter-date-on",
  "columnId": "<column-id>",
  "kind": "date-range",
  "mode": "on",
  "date": "2024-06-15T00:00:00Z",
  "includeNulls": "when-no-value-is-selected"
}
```

## List (include or exclude)

```json
{
  "id": "filter-region",
  "columnId": "<column-id>",
  "kind": "list",
  "mode": "include",
  "values": ["West", "East"]
}
```

## Text match

```json
{
  "id": "filter-name",
  "columnId": "<column-id>",
  "kind": "text-match",
  "mode": "contains",
  "value": "search term",
  "case": "insensitive",
  "includeNulls": "when-no-value-is-selected"
}
```

## Top N

Returns the top (or bottom) N rows ranked by a column. `rowCount` sets the number of rows; `rankingFunction` is always `"rank"`.

```json
{
  "id": "filter-top10",
  "columnId": "<column-id>",
  "kind": "top-n",
  "mode": "top-n",
  "rankingFunction": "rank",
  "rowCount": 10,
  "includeNulls": "when-no-value-is-selected"
}
```

## Enum values

**`kind` values:** `"number-range"`, `"date-range"`, `"list"`, `"text-match"`, `"top-n"`

**`includeNulls` values:** `"always"`, `"never"`, `"when-no-value-is-selected"`

**Date range `mode` values:** `"between"` (requires `startDate` + `endDate`), `"on"` (requires `date`)

**Text match `mode` values:** `"equals"`, `"does-not-equal"`, `"contains"`, `"does-not-contain"`, `"starts-with"`, `"does-not-start-with"`, `"ends-with"`, `"does-not-end-with"`, `"like"`, `"not-like"`, `"matches-regexp"`, `"does-not-match-regexp"`

**Text `case` values:** `"sensitive"`, `"insensitive"`

**List `mode` values:** `"include"`, `"exclude"`
