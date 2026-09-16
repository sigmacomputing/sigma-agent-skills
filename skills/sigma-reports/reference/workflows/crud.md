# Report Code Representation CRUD

All calls require `Authorization: Bearer $SIGMA_API_TOKEN`. The current OpenAPI
declares JSON bodies and responses for the report content endpoints.

## Verify without persistence

Use the create envelope with `dryRun: true`, POSTed to the same create
endpoint (`contents` is required when `dryRun` is true — a 400 results
otherwise):

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-spec-dry-run.json \
  "$SIGMA_BASE_URL/v2/reports"
```

Make this the default live probe. It does not create a report. A valid spec
returns either bare metadata (no `valid` key) or `{"valid": true, "warnings":
[...]}`; an invalid one returns `{"valid": false, "errors": [{"summary":
...}], "warnings": [...]}`.

## Create

Creating is persistent and the current API has no report DELETE endpoint. Get
explicit approval for the destination folder before calling:

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-spec.json \
  "$SIGMA_BASE_URL/v2/reports" \
  > /tmp/report-create.json
```

The response is bare metadata, not a `{success, reportId}` envelope — there is
no `success` key. Save `reportId` and treat the submitted representation as
canonical under a report-ID-specific path immediately.

Live-confirmed 2026-09-16 against the new `POST /v2/reports`: create returned
HTTP 200 with `reportId`, `reportUrlId`, `name`, `url`, `path`,
`latestVersion`, and no `success` key, after the same envelope returned clean
from a dry run. Code written against the legacy `{"success":true,...}` shape
reads every successful create as a failure.

## Retrieve

```bash
curl -sf \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/reports/<report-id>?includeContents=true" \
  > /tmp/report-<report-id>-before.json
```

Keep the complete response as the rollback record. It includes outer metadata
and the report `contents`.

## Update

`PUT /v2/reports/{reportId}/contents` is full replacement of `contents` and
creates a new report version. It is **contents-only** — `name`, `folderId`,
and `description` sent alongside `contents` are silently ignored, not
applied. Send `contents` and the `documentVersion` from the latest GET:

```bash
jq '{contents: .contents, documentVersion: .documentVersion}' \
  /tmp/report-edited.json \
  > /tmp/report-put.json

ruby scripts/validate-spec.rb --mode update /tmp/report-put.json

curl -sf -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-put.json \
  "$SIGMA_BASE_URL/v2/reports/<report-id>/contents" \
  > /tmp/report-update-response.json
```

Before PUT:

1. GET the latest representation (`?includeContents=true`) and preserve
   `documentVersion`.
2. List the report's pages, elements, and controls through their inventory
   endpoints.
3. Compare inventory IDs with the representation.
4. Stop if inventory content is absent from `contents`; GET can be lossy.
5. Preserve every page, panel, element, source, formula, setting, and layout
   entry not intentionally changed.
6. Validate the update body locally.
7. Assemble a create envelope around the edited `contents` and dry-run it
   (`dryRun: true`).

The current OpenAPI makes `documentVersion` optional, but omitting it removes
the optimistic-concurrency guard. Include it unless intentionally forcing the
latest complete `contents` over concurrent edits. A stale version must be
resolved by GET, reapplying the intended edit, and repeating validation; do not
blindly retry without reconciling.

After PUT, GET again and compare normalized representations. Export the
affected pages as PDF and inspect them.

Live-confirmed 2026-08-11: PUT returned HTTP 200, retained the report ID, and
advanced `documentVersion`/`latestDocumentVersion` from 1 to 2. Header/footer
panels, element IDs, and pixel layout survived readback unchanged.

## No automated cleanup assumption

Do not design tests around create-then-delete. The current OpenAPI exposes GET
on `/v2/reports/{reportId}` but no DELETE operation. Reuse a designated manual
test report only when the user has approved that persistent resource.
