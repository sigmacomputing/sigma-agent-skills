# Workbook Spec CRUD

Recipe + traps for POST / GET / PUT against the workbook content endpoints. Load this when creating, retrieving, or updating a workbook.

```bash
jq '.paths."/v2/workbooks".post, .paths."/v2/workbooks/{workbookId}".get, .paths."/v2/workbooks/{workbookId}/contents".put' /tmp/sigma-api.json
```

The endpoints are straightforward; the spec value is in calling out the **non-obvious behaviors**: YAML is the default content type (this skill prefers it for human readability), PUT being full-replacement of `contents` (anything you omit is dropped), server-managed fields being ignored rather than rejected on write, and the request/response body being **wrapped, not flat** (below).

Every call includes `-H "Authorization: Bearer $SIGMA_API_TOKEN"`. Auth comes from the `sigma-api` skill.

## The body is wrapped under `contents`

`schemaVersion`, `kind`, flat `elements`, metadata-only `pages`, `overlays`,
`panels`, `layout`, `settings`, and `agents` nest under `contents`; `name`,
`folderId`, `description`, and response metadata stay outside it. A flat body
gets HTTP 400.

## Endpoints

```bash
# CREATE — POST the workbook, response includes workbookId.
# YAML by default on both directions. `--data-binary` preserves the
# multiline body byte-for-byte (`-d` strips newlines, breaking YAML).
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks"

# GET — retrieve current spec (YAML by default). `includeContents=true` adds
# the `contents` key (and `documentVersion`) alongside the resource metadata
# that a bare GET already returns:
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>?includeContents=true"

# UPDATE — PUT replaces the entire contents. Send ONLY the contents object —
# {contents: {...}} — not name/folderId; the workbook id in the URL is
# what's being updated. `documentVersion` is optional, for an optimistic-
# concurrency stale-write check.
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec-put-body.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/contents"
```

If you'd rather work in JSON, swap `application/yaml` → `application/json` and `--data-binary @file.yaml` → `-d @file.json` on each call. Sigma accepts both. YAML is the recommended default for this skill because workbook specs are human-reviewable artifacts and YAML diffs cleanly in PRs.

> **`PUT .../contents` is contents-only.** Sending `name`, `folderId`, or `description` alongside `contents` is silently ignored, not applied — use `PUT /v2/files/{fileId}` to rename or move a workbook.

## Required Fields on CREATE

The POST body must include:

- `name` (string) — outer level
- `folderId` (string — usually the user's `homeFolderId`) — outer level
- `contents.schemaVersion` (number — use the value returned by `GET /v2/workbooks/<reference-workbook-id>?includeContents=true`, do NOT hardcode it)
- `contents.kind: workbook`
- `contents.elements` (flat array; required even when empty)
- `contents.pages` (metadata array; no nested elements)

Optional in OpenAPI: `description` (outer), `contents.overlays`,
`contents.panels`, `contents.settings`, `contents.agents`, and
`contents.layout`. This skill requires layout whenever elements is non-empty.
Omitting `contents` entirely still creates a blank workbook.

```yaml
name: Sales Dashboard
folderId: <homeFolderId>
description: Sales overview dashboard
contents:
  schemaVersion: 1
  kind: workbook
  elements: [...]
  pages: [...]
  layout: |
    <?xml version="1.0" encoding="utf-8"?>
    ...
```

The server rejects a spec whose `schemaVersion` doesn't match what the current API expects, hence the rule against hardcoding it — always read it back from a recent reference GET.

The CREATE response shape (in YAML, the default):

```yaml
success: true
workbookId: <uuid>
```

Extract `workbookId` with `yq -r '.workbookId' /tmp/create-response.yaml` (or `jq` if you switched to JSON content types).

## Persisting the Spec

After a successful CREATE, copy the spec to a workbook-keyed path so it survives the next build, the user can diff or re-POST it, and subsequent PUTs can start from it:

```bash
WORKBOOK_ID=$(yq -r '.workbookId' /tmp/create-response.yaml)
cp /tmp/workbook-spec.yaml "/tmp/workbook-spec-${WORKBOOK_ID}.yaml"
```

After a successful PUT, refresh the saved copy from the file you just submitted so it tracks server state:

```bash
cp /tmp/current-spec.yaml "/tmp/workbook-spec-<workbook-id>.yaml"
```

Report **both** the workbook URL **and** the saved spec path.

## UPDATE Is Full Replacement (No Diffs)

The PUT endpoint replaces the entire `contents` — partial updates are not supported, and metadata fields (`name`, `folderId`, `description`) sent alongside `contents` are silently ignored rather than applied. Always:

1. GET the current spec first (`?includeContents=true`).
2. Edit inside `contents` — preserving `elements`, `pages`, `overlays`,
   `panels`, `layout`, `settings`, and `agents`.
3. PUT the **full** `contents` object back — just `{contents: {...}}`, not the outer `name`/`folderId`/response-only fields the GET also returned.

If you skip the GET and submit a partial `contents`, anything you didn't include is gone.

## IDs Are Preserved on CREATE

The `id` values you send in `POST /v2/workbooks` — for pages, elements, and columns — are **preserved verbatim**. Layout `elementId` attributes, control bindings, and cross-element `source` references that name your IDs all stay valid after create. You can edit your saved spec and `PUT` it back directly (re-wrapped as `{contents: {...}}` — see below); `GET` the current spec first only when you don't have your latest copy on hand.

## Response-Only Fields to Strip

`GET /v2/workbooks/<id>?includeContents=true` returns extra server-managed fields at the **outer level** (alongside `name`/`folderId`, not inside `contents`) — `workbookId`, `url`, `documentVersion`, etc. Since PUT only accepts `{contents: {...}}` anyway (see *The body is wrapped under `contents`*, above), these never go on the wire for an update — there's nothing to strip once you're sending just the `contents` object. `documentVersion` is the one exception worth sending deliberately: pass it alongside `contents` in the PUT body to get an optimistic-concurrency check (the update fails if it's stale); omit it for last-write-wins. See `reference/specification/schema.md` for the canonical list.

## Iteration Pattern

```bash
# Get current spec (YAML by default) — full response shape:
# {name, folderId, ..., documentVersion, contents: {schemaVersion, kind, elements, pages,
# overlays, panels, layout, settings, agents}}
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>?includeContents=true" \
  > /tmp/current-spec.yaml

# If you also want the HTTP status (e.g. for trace logging), keep streams
# separate: write the body via -o, send the status to stdout via -w.
# NEVER combine `-w "...%{http_code}..."` with `> body.yaml` — that mixes
# status text into the body file and corrupts the YAML.
curl -s -o /tmp/current-spec.yaml -w "%{http_code}\n" \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>?includeContents=true"

# Edit /tmp/current-spec.yaml on disk (edit inside .contents), then extract
# ONLY the contents object for the PUT body — sending the outer name/folderId/
# response-only fields alongside it is silently ignored, not applied:
yq '{"contents": .contents}' /tmp/current-spec.yaml > /tmp/current-spec-put.yaml
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/current-spec-put.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/contents" | yq .

# Refresh the saved copy (full GET shape) so the next edit starts from the latest spec
cp /tmp/current-spec.yaml "/tmp/workbook-spec-<workbook-id>.yaml"
```
