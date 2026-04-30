# Column-Level Security (CLS)

CLS rules restrict which users can see specific columns. They are defined in the `columnSecurities` array of a table element.

Each rule specifies a `criteria` (who is allowed to view) and a `restrictedColumns` list (which columns to protect). Users who do not meet the criteria cannot see the listed columns.

## No one can view

Hides the column from all users, including admins.

```json
"columnSecurities": [
  {
    "id": "cls-ssn",
    "criteria": { "kind": "no-one-can-view" },
    "restrictedColumns": ["<column-id>"]
  }
]
```

## Specific users and teams

Only the explicitly listed users and/or teams can view the column.

```json
{
  "id": "cls-finance",
  "criteria": {
    "kind": "specific-users-and-teams",
    "assignments": [
      { "type": "user", "userId": "<user-id>" },
      { "type": "team", "teamId": "<team-id>" }
    ]
  },
  "restrictedColumns": ["<column-id>"]
}
```

## User attribute

Only users whose attribute matches the required value can view the column. Useful for dynamic, attribute-based access control.

```json
{
  "id": "cls-region",
  "criteria": {
    "kind": "user-attribute",
    "assignments": [
      { "userAttributeId": "<attr-id>", "value": "<required-value>" }
    ]
  },
  "restrictedColumns": ["<column-id>"]
}
```

## Enum values

**`criteria.kind` values:** `"no-one-can-view"`, `"specific-users-and-teams"`, `"user-attribute"`
