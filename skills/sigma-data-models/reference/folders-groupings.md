# Folders, Groupings, Order, and Sort

These properties are all set on the table element alongside `columns` and `metrics`.

## Folders

Group columns into visual folders using the `folders` array. Reference the folder `id` in the `order` array to position the folder in the column list.

```json
"folders": [
  {
    "id": "folder-dates",
    "name": "Date Fields",
    "items": [
      "<col-id-order-date>",
      "<col-id-ship-date>"
    ]
  },
  {
    "id": "folder-financials",
    "name": "Financials",
    "items": [
      "<col-id-price>",
      "<col-id-cost>",
      "col-profit"
    ]
  }
]
```

**Folder schema:** `id` (required), `name` (required), `items`? (array of column IDs and/or nested folder IDs)

## Groupings

Groupings define default group-by behavior on the table element.

```json
"groupings": [
  {
    "id": "grouping-1",
    "groupBy": [
      "<column-id>"
    ],
    "calculations": [
      "<calculation-column-id>"
    ]
  }
]
```

**Grouping schema:** `id` (required), `groupBy`? (array of column or folder IDs), `calculations`? (array of calculation column IDs)

## Column order

The `order` array sets the display sequence of columns and folders. Items not listed appear after the listed ones. Summary columns are excluded from `order`.

```json
"order": [
  "folder-dates",
  "<col-id-1>",
  "<col-id-2>",
  "folder-financials"
]
```

## Sort

The `sort` array sets the default sort order on the table element.

```json
"sort": [
  {
    "columnId": "<col-id>",
    "direction": "descending",
    "nulls": "last"
  }
]
```

**`direction` values:** `"ascending"`, `"descending"`

**`nulls` values:** `"first"`, `"last"`, `"connection-default"`
