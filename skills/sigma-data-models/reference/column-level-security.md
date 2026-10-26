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

Look up team IDs by name, and user IDs (`memberId`) by email:

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/teams?limit=200" | jq -c '.entries[] | {teamId, name}'

curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/members?limit=200" | jq -c '.entries[] | {memberId, email}'
```

If a team the user names doesn't exist, stop and ask. Don't substitute a similarly named team or create one.

The API can confirm a rule is stored, not that it's enforced — the query endpoint runs as you. Tell the user to check enforcement by viewing the model as someone outside the allowed teams. If other elements can reach the restricted column through relationships, ask them to check it from those elements too.

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
