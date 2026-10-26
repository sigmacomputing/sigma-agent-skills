# Data Model CRUD

POST / GET / PUT against the data-model spec endpoints. Load this for any create, retrieve, or update operation.

The three workflows share auth, ID conventions, and the feature reference files in `reference/`. They differ in HTTP verb, full-replacement semantics, and ID handling. Read the **ID semantics across CRUD** table first — many bugs come from mixing up which IDs the server respects vs. remaps.

Every call includes `-H "Authorization: Bearer $SIGMA_API_TOKEN"`. Auth comes from the `sigma-api` skill.

## ID Semantics Across CRUD

| Phase | What happens to IDs |
|-------|---------------------|
| **CREATE (POST)** | IDs that follow the conventions (short alphanumeric, or `inode-<tableUrlId>/<COL>` for warehouse columns) are normally stored as submitted — pages, elements, columns, metrics, and `columnSecurities` rules alike. Cross-references (`dateColumnId`, relationship keys, `restrictedColumns`) resolve against the submitted IDs. Don't depend on that: the server may assign a different ID, so read IDs back with GET before reusing them. |
| **GET** | The stored IDs. This is the source of truth for any subsequent UPDATE. |
| **UPDATE (PUT) — existing elements** | Keep the IDs from GET verbatim. Changing them on unchanged elements can break workbooks that depend on this data model. |
| **UPDATE (PUT) — new elements added in the same PUT** | Same as CREATE. Give them new IDs that follow the conventions and don't collide with existing ones. |
| **UPDATE — mixed cross-references** (e.g., a relationship between an existing column and a new one) | Existing side uses the ID from GET. New side uses the ID you assigned in this PUT. |

> **Rule of thumb:** GET is the only step that returns IDs you can rely on. Use GET as the entry point for every UPDATE.

## CREATE — Author a New Model

### 1. Gather required IDs

You need a `folderId`, a `connectionId`, and (usually) a warehouse `path` + inode prefix.

**Destination folder:**

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/files?typeFilters=folder&limit=200" \
  | jq '.entries[] | {id, name, path}'
```

The `id` of the target folder becomes `folderId`. Without `typeFilters=folder`, folders can be buried under pages of documents.

The user's **My Documents** folder isn't returned as an entry. Get its ID from the user's member record:

```sh
MEMBER_ID=$(curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/whoami" | jq -r .userId)
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/members/$MEMBER_ID" | jq -r .homeFolderId
```

If the user didn't name a folder, ask, or default to My Documents and say so.

**Connection:**

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections" \
  | jq '.entries[] | {connectionId, name}'
```

**Connection paths and tables:**

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/paths?connectionId=<connectionId>&limit=500"
```

`connectionId` scopes the listing to one connection. Without it, you page through every connection's tables.

Search the `entries` array for depth-3 `path` values (e.g., `["EXAMPLES", "PLUGS_ELECTRONICS", "TABLE_NAME"]`). A page holds at most 500 entries, so expect to paginate: while `hasMore` is `true`, request `&page=<nextPage>`, passing `nextPage` exactly as returned (it's already URL-encoded). Filter each page as you go, e.g. `jq -c '.entries[] | select(.path | join("/") | test("<NAME>"; "i"))'`.

Each table has two different identifiers. Don't mix them up:

| Identifier | Example | Where to get it | Used for |
|---|---|---|---|
| Table URL ID | `5FCsrDpnzcdw5YYJRBbY6l` | `urlId` on each `/v2/connections/paths` entry, or the last segment of `url` from `/lookup` | Warehouse column ID prefix: `inode-5FCsrDpnzcdw5YYJRBbY6l/<COLUMN_NAME>` |
| Table UUID | `<8-4-4-4-12 hex UUID>` | `inodeId` from `/lookup` | Path parameter of the table columns endpoint |

To get the table UUID, look up the path:

```sh
curl -s -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"path": ["<DATABASE>", "<SCHEMA>", "<TABLE>"]}' \
  "$SIGMA_BASE_URL/v2/connection/<connectionId>/lookup" \
  | jq '{inodeId, url}'
```

**Connection table columns** (use to discover real column names + types before composing — never invent column names). Pass the table **UUID**, not the `inode-<urlId>` prefix — that returns `Expecting UUID at tableId`:

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/<tableUuid>/columns" \
  | jq -c '.entries[] | {name, type: .type.type}'
```

Each entry looks like `{"name": "STORE_KEY", "type": {"type": "integer"}, ...}`. Normalize names per the **Special characters** section in `reference/columns.md`. Ignore `<COLUMN> - link` entries; they're link metadata, not data columns.

Before composing, note which table holds each measure the user asked for. A fact table that carries the foreign keys may not carry the amounts — line-item amounts can live in a separate table keyed by order number.

**Existing data-model elements / columns** (only when the user explicitly names an existing model as a relationship target or template):

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/elements"

curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/columns"
```

Use `columnId` values when referencing columns in relationship keys.

> Do **not** read other data models to infer column names, discover table structure, or borrow patterns unless the user explicitly named one as a template or source.

### 2. Identify features

Map the user's request to feature reference files via the SKILL.md **Reference Index**. Tell the user which features you identified and why, then read the relevant files before composing.

If the model combines more than one table or defines metrics, read `reference/modeling.md` first. It covers grain, fan-out, and whether to aggregate with `Rollup` or custom SQL.

If the user explicitly names an existing model to base the new one on, retrieve its spec via the GET workflow below and use it — modified per the description — as the basis instead of the minimal structure.

### 3. Compose the JSON

Start from the minimal structure, then layer in patterns from the reference files.

```json
{
  "name": "<YOUR_DATA_MODEL_NAME>",
  "folderId": "<YOUR_FOLDER_ID>",
  "schemaVersion": 1,
  "pages": [
    {
      "id": "page-1",
      "name": "Main",
      "elements": [
        {
          "id": "table-1",
          "kind": "table",
          "name": "<Element Name>",
          "description": "<Optional: what one row represents>",
          "source": {
            "kind": "warehouse-table",
            "connectionId": "<YOUR_CONNECTION_ID>",
            "path": ["<YOUR_DATABASE>", "<YOUR_SCHEMA>", "<YOUR_TABLE_NAME>"]
          },
          "columns": [
            {
              "id": "<YOUR_TABLE_INODE>/<COLUMN_NAME>",
              "formula": "[<YOUR_TABLE_NAME>/Column Name]",
              "name": "Column Name"
            }
          ]
        }
      ]
    }
  ]
}
```

Give every element a `name`. Other elements reference it by that name (`[<Element Name>/Column]`, `Rollup`, `Lookup`), and workbook authors see it.

If you hand the user a spec that still has placeholders in it, follow the JSON with a "What you need to supply" table. Skip the table when you've resolved every ID yourself and are submitting:

| Placeholder | What it is | How to find it |
|---|---|---|
| `<YOUR_FOLDER_ID>` | Destination folder for the data model | `GET /v2/files` output or the folder URL in Sigma |
| `<YOUR_CONNECTION_ID>` | Data source connection | `GET /v2/connections` output or the Connections page |
| `<YOUR_DATABASE>` / `<YOUR_SCHEMA>` / `<YOUR_TABLE_NAME>` | Warehouse path to source table | The warehouse, or the connection browser in Sigma |
| `<YOUR_TABLE_INODE>` | Inode prefix for warehouse column IDs | Last path segment of the `url` returned by `POST /v2/connection/<id>/lookup` (e.g., `.../t/5FCsrDpnzcdw5YYJRBbY6l` → `inode-5FCsrDpnzcdw5YYJRBbY6l`) |

Reminder on IDs: see the ID semantics table at the top. Cross-references (e.g., `dateColumnId` in metric timelines, relationship keys) resolve against the IDs you submit.

If the same tables exist under more than one database or schema (sample data often does), pick one, tell the user which, and use it for every element.

### 4. Submit

```sh
cat > spec.json <<'EOF'
{ ...the composed JSON... }
EOF

curl -s -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @spec.json \
  "$SIGMA_BASE_URL/v2/dataModels/spec"
```

The response is `{"success": true, "dataModelId": "<uuid>"}`. Don't build a link from `dataModelId` — data model URLs use a different ID, so that link doesn't open. Get the link in the verify step.

### 5. Verify

The POST validates column formulas — an unresolvable column reference is rejected with `Cannot resolve columns on table ...`. **Metric formulas are not validated**: a metric that references a column that doesn't exist is accepted. Before reporting success:

1. **Read the spec back** and confirm every column, metric, relationship, and `columnSecurities` rule is present with the intended formula. For each metric, confirm every bracketed name matches a column `name` in the same element:

   ```sh
   curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
     "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec" > created-spec.json
   ```

2. **Compile each element.** The query endpoint returns the SQL Sigma generates for an element. Getting SQL back confirms the element compiles. Read it to confirm the joins and aggregations are what you intended:

   ```sh
   curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
     "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/elements" \
     | jq -r '.entries[] | "\(.elementId)\t\(.name)"'

   curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
     "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/elements/<elementId>/query" \
     | jq -r .sql
   ```

   What this does and doesn't cover:

   - The SQL ends in a preview row limit (`limit 1000`); that limit isn't part of the model.
   - It returns SQL, not data. It can't answer questions about the values in the data (for example, whether a transaction-type column includes returns) — list those as open questions for the user.
   - It includes columns only. Metrics don't appear, so step 1 is the only API check for them.
   - It runs as you, so restricted columns appear in it. It doesn't show whether column-level security is enforced. Confirm the rule in step 1, and tell the user to check enforcement by viewing the model as someone outside the allowed teams.

   Optionally, `GET /v2/dataModels/<dataModelId>/columns` returns each column's resolved type, which catches a calculated column that resolves to the wrong type (text where you expected a number).

3. **Give the user the link** from the `url` field of the spec:

   ```sh
   jq -r .url created-spec.json
   ```

## GET — Read an Existing Model

> **This is the entry point for an UPDATE — always GET first.** The retrieved spec is the only source of IDs you can safely PUT back.

### 1. List models

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels" \
  | jq '.entries[] | {dataModelId, name}'
```

If the user wants to browse by folder first:

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/files" \
  | jq '.entries[] | {inodeId, name, type}'
```

### 2. Retrieve the spec

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec" \
  | jq .
```

Save to a file for review or as input to the UPDATE workflow:

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec" \
  > my-data-model.json
```

## UPDATE — Modify an Existing Model

The update endpoint uses **PUT** and requires the **complete** representation, not a diff. Always start from the GET so existing elements are preserved.

### 1. List + identify

Same as the GET workflow — `GET /v2/dataModels`, optionally `GET /v2/files` to browse by folder.

### 2. Retrieve the current spec

```sh
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec" \
  > current-spec.json
```

### 3. Identify changes and load references

For each type of change the user is asking for, read the corresponding reference file from the SKILL.md **Reference Index** to get the correct JSON pattern. Common change categories:

- Add, rename, or remove a column or metric → `reference/columns.md`, `reference/metrics.md`
- Add a calculated column or change a formula → `reference/columns.md`
- Change or swap the data source → `reference/sources.md`
- Add a relationship or join → `reference/relationships.md`, `reference/sources.md`
- Add, modify, or remove filters → `reference/filters.md`
- Add column-level security → `reference/column-level-security.md`
- Add or modify controls → `reference/controls.md`
- Reorder columns or change folder/grouping → `reference/folders-groupings.md`
- Reformat a column or metric → `reference/formatting.md`

Use the retrieved spec as structural context — match existing ID conventions and naming patterns.

### 4. Compose the updated spec

Apply the changes to `current-spec.json`. Key rules:

- Include from the GET response: `name`, `folderId`, `ownerId`, `createdAt`, `updatedAt`, `schemaVersion`, and all of `pages`. Server-managed fields (`documentVersion`, `latestDocumentVersion`, `url`, `createdBy`, `updatedBy`) can be omitted — they are silently ignored if present.
- **Preserve existing element IDs** — changing them on unchanged elements can break workbooks that depend on this data model.
- For new elements, follow the ID conventions: short alphanumeric for generated IDs, `inode-<tableUrlId>/<COL>` for warehouse columns. Don't reuse an ID that's already in the spec. Read the stored IDs back in the verify step.
- Controls live in the page `elements` array alongside table elements, not inside them.
- Mixed-ID cross-references (e.g., a relationship between an existing column and a new one): see the ID semantics table at the top of this file. Existing side uses the live server ID; new side uses the placeholder; server resolves on submit.

### 5. Submit

```sh
curl -s -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @current-spec.json \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec"
```

### 6. Verify

Run the CREATE **Verify** step against the updated model. Diff the new GET against `current-spec.json` to confirm only the intended changes landed. Match elements, columns, and metrics by `id`, not position — GET can return elements in a different order than you submitted.
