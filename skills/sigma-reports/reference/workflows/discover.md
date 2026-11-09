# Report Data Discovery

Run discovery before choosing report metrics, period comparisons, table
columns, or page slices. Reports use the same Sigma/warehouse sources as
workbooks, but fixed pages make a wrong grain or cardinality especially costly:
the PDF can look polished while showing duplicated totals or clipped groups.

## Decision order

1. Use an already-connected Sigma MCP (`search`, `describe`, `query`) or
   warehouse-native MCP for semantic discovery.
2. Otherwise list Sigma connections and browse
   `/v2/connections/paths`, following `nextPage` while `hasMore` is true.
3. Resolve candidate paths with `/v2/connection/{connectionId}/lookup`.
4. Read every column-metadata page with the shared `sigma-api`
   `list-table-columns.sh` helper.
5. If several sources remain plausible, show a short candidate list and ask
   one focused question. Do not repeatedly open unrelated reports.

REST path matching is not semantic catalog search. Bound the candidate pass;
“sales,” “inventory,” and “customer” can each match dozens of tables.

## Folder and identity

```bash
USER_ID=$(curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/whoami" | jq -r '.userId')

HOME_FOLDER_ID=$(curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/members/$USER_ID" | jq -r '.homeFolderId')
```

Use an explicitly requested folder when supplied. A report create is
persistent and currently has no DELETE endpoint.

## Warehouse source discovery

```bash
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections"

curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/paths?limit=500&page=1"
```

After choosing a path:

```bash
INODE_ID=$(curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"path":["DATABASE","SCHEMA","TABLE"]}' \
  "$SIGMA_BASE_URL/v2/connection/<connection-id>/lookup" |
  jq -r '.inodeId')

bash <sigma-api-skill-dir>/scripts/list-table-columns.sh "$INODE_ID" |
  jq '.entries[] | {name,type,description,visibility}'
```

The raw columns endpoint defaults to 50 results and returns
`nextPageToken`; pagination is complete only when that field is absent. Never
conclude a report field is unavailable from one page.

Use exact returned names. For custom SQL, quote output aliases and declare each
with `[Custom SQL/<alias>]`.

## Data-model source discovery

Use the consuming element endpoint, not the model's internal spec:

```bash
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<data-model-id>/elements" |
  jq '.entries[] | {elementId,name,columns}'
```

Relationship-derived columns may include suffixes such as
`Region (CUSTOMER_DIM)`. Use the exposed name verbatim.

## Prove the report grain

Before authoring, state what one row represents and prove it:

```sql
SELECT COUNT(*) AS rows, COUNT(DISTINCT <grain_key>) AS distinct_keys
FROM <composed_source>;
```

For composite keys, group by every key and require zero duplicate groups.
For joins, compare left-row and distinct-key counts before and after. Record
the expected counts for post-render/export verification.

## Probe report-specific values

Check:

- actual distinct category labels before filters or conditional text;
- latest closed period and equal elapsed periods for comparisons;
- negative/zero/null cases for sign and formatting rules;
- longest labels for table-width budgeting;
- category cardinality for chart selection;
- row counts per page-slice key for wide operational reports.

Executive reports should derive “latest” periods from closed-period metadata
instead of hardcoding quarter names. Wide reports should assign deterministic
`page_no`, brand group, region group, or row-number bands before authoring
their physical pages.

## Cache the discovery result

Keep one local manifest with selected IDs, exact columns, grain checks,
distinct values, period rules, and page-slice counts. Reuse it throughout the
build; do not repeat workspace-wide searches for each page.
