# Controls

Controls are interactive filter elements. They are defined as separate entries in the page's `elements` array — **not** nested inside table elements.

## Common fields

| Field | Required | Notes |
|---|---|---|
| `kind` | yes | Always `"control"` |
| `id` | yes | Element ID — must be unique on the page |
| `controlId` | yes | Formula reference name (e.g., `"RegionFilter"`) — keep distinct from `id` |
| `controlType` | yes | Determines the UI widget and filter behavior |
| `filters` | no | Array of `{ "source": { "kind": "table", "elementId": "..." }, "columnId": "..." }` — connects the control to columns on table elements |

---

## List values

Dropdown or multi-select picker sourced dynamically from a column.

```json
{
  "kind": "control",
  "id": "ctrl-region",
  "controlId": "RegionFilter",
  "controlType": "list",
  "mode": "include",
  "selectionMode": "multiple",
  "values": [],
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "<table-element-id>" },
    "columnId": "<source-column-id>"
  },
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode`: `"include"` | `"exclude"` · `selectionMode`: `"multiple"` | `"single"`

---

## Text input

Single-line text filter control.

```json
{
  "kind": "control",
  "id": "ctrl-search",
  "controlId": "SearchText",
  "controlType": "text",
  "mode": "contains",
  "value": "",
  "case": "insensitive",
  "includeNulls": "when-no-value-is-selected",
  "showOperators": false,
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode` values: `"equals"`, `"does-not-equal"`, `"contains"`, `"does-not-contain"`, `"starts-with"`, `"ends-with"`, `"like"`, `"matches-regexp"`, and their negations.

---

## Text area

Multi-line text input control.

```json
{
  "kind": "control",
  "id": "ctrl-notes",
  "controlId": "NotesInput",
  "controlType": "text-area",
  "value": "",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

---

## Number input

Single numeric value filter.

```json
{
  "kind": "control",
  "id": "ctrl-qty",
  "controlId": "QuantityFilter",
  "controlType": "number",
  "mode": ">=",
  "value": 0,
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode` values: `"="`, `"!="`, `"<"`, `"<="`, `">"`, `">="`

---

## Number range

Two-value numeric range filter.

```json
{
  "kind": "control",
  "id": "ctrl-price-range",
  "controlId": "PriceRange",
  "controlType": "number-range",
  "min": 0,
  "max": 100,
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

---

## Date control

Single date filter.

```json
{
  "kind": "control",
  "id": "ctrl-date",
  "controlId": "DateFilter",
  "controlType": "date",
  "mode": ">=",
  "value": "2024-01-01T00:00:00Z",
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode` values: `"="`, `"<"`, `"<="`, `">"`, `">="`

Dynamic value: `{ "op": "now-minus", "unit": "day", "value": 2 }` (or `"now-plus"`); `unit` values: `"year"`, `"quarter"`, `"month"`, `"week"`, `"day"`, `"hour"`, `"minute"`

---

## Date range

Two-date range filter.

```json
{
  "kind": "control",
  "id": "ctrl-date-range",
  "controlId": "DateRange",
  "controlType": "date-range",
  "mode": "between",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-12-31T23:59:59Z",
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

---

## Slider

Single-handle slider with a comparison operator.

```json
{
  "kind": "control",
  "id": "ctrl-slider",
  "controlId": "ScoreSlider",
  "controlType": "slider",
  "low": 0,
  "high": 100,
  "mode": "<=",
  "value": 50,
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode` values: `"="`, `"<"`, `"<="`, `">"`, `">="` · `low`/`high` define the slider range

---

## Range slider

Dual-handle slider selecting a min/max range.

```json
{
  "kind": "control",
  "id": "ctrl-range",
  "controlId": "ScoreRange",
  "controlType": "range-slider",
  "low": 0,
  "high": 100,
  "min": 20,
  "max": 80,
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`low`/`high` define the slider range; `min`/`max` are the selected values.

---

## Segmented control

Radio-button style selector sourced from a column.

```json
{
  "kind": "control",
  "id": "ctrl-segment",
  "controlId": "CategoryPicker",
  "controlType": "segmented",
  "value": true,
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "<table-element-id>" },
    "columnId": "<source-column-id>"
  },
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

---

## Switch

Boolean toggle control.

```json
{
  "kind": "control",
  "id": "ctrl-switch",
  "controlId": "ActiveToggle",
  "controlType": "switch",
  "mode": "True/False",
  "value": true,
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode` values: `"True/False"`, `"True/All"`

---

## Checkbox

Boolean checkbox control.

```json
{
  "kind": "control",
  "id": "ctrl-check",
  "controlId": "ActiveOnly",
  "controlType": "checkbox",
  "mode": "True/False",
  "value": true,
  "filters": [
    { "source": { "kind": "table", "elementId": "<table-element-id>" }, "columnId": "<column-id>" }
  ]
}
```

`mode` values: `"True/False"`, `"True/All"`

---

## Top N

Limits results to the top or bottom N rows by a ranking function.

```json
{
  "kind": "control",
  "id": "ctrl-top-n",
  "controlId": "TopProducts",
  "controlType": "top-n",
  "rankingFunction": "rank",
  "mode": "top-n",
  "rowCount": 10,
  "includeNulls": "when-no-value-is-selected"
}
```

`rankingFunction` values: `"rank"`, `"rank-dense"`, `"row-number"`

`mode` values: `"top-n"`, `"bottom-n"`

Percentile variant: use `percentile` (number) instead of `rowCount`, with `rankingFunction`: `"rank-percentile"` or `"cume-dist"`, and `mode`: `"top-percentile"` or `"bottom-percentile"`
