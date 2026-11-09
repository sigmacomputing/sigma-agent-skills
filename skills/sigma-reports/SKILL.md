---
name: sigma-reports
description: >-
  Build, validate, retrieve, and safely update Sigma report code
  representations through /v2/reports. Use for fixed-layout or
  pixel-perfect reports, executive board packets, wide operational tables,
  invoices, statements, regulatory documents, and PDF delivery. Covers
  reusable report scaffolds, report pages, absolute pixel layout,
  header/footer panels, common elements, verification, full-contents
  replacement, and workbook conversion to reports. Do not use for responsive dashboards; use
  sigma-workbooks instead. Requires SIGMA_API_TOKEN from the sigma-api skill.
---

# Sigma Reports (Code Representation via REST API)

Use this skill for Sigma **reports**, the fixed-page authoring surface exposed
by `/v2/reports`. Reports are a private-beta resource. They share common
element shapes with workbooks but have a different resource lifecycle and a
different layout language.

## Choose the correct resource

Use a report for invoices, statements, regulatory packets, printable forms,
branded documents, and other outputs whose physical page size matters. Use
`sigma-workbooks` for responsive dashboards, exploratory analysis, application
workflows, containers, tabs, modals, drawers, or workbook navigation.

Never create a report by sending `kind: report` to a workbook endpoint. The
resource families are separate:

- Reports: `POST /v2/reports`, `GET /v2/reports/{reportId}?includeContents=true`, `PUT /v2/reports/{reportId}/contents`
- Workbooks: `POST /v2/workbooks`, `GET /v2/workbooks/{workbookId}?includeContents=true`, `PUT /v2/workbooks/{workbookId}/contents`
- Conversion: `/v2/workbooks/{workbookId}/convertToReport`

## Source of truth

Use the current compiled OpenAPI for endpoint envelopes and published shapes:

```
https://assets.sigmacomputing.com/openapi/public-rest-api/sigma-computing-public-rest-api.json
```

The report endpoints currently declare `application/json` only. Author JSON
unless a live request proves another media type works. The schema is broader
than the documented report contract, so a published element kind is not proof
that reports can safely author it. Read
`reference/specification/support-matrix.md` before selecting elements.

Live baseline, verified 2026-08-11: a JSON report with a warehouse-table
source, text, KPI, combo-chart, bar-chart, grouped presentation table, data
bars, a hidden dependency page, and header/footer panels passed a `dryRun: true`
dry run, created successfully, survived GET readback, updated as a new document version,
and exported as a one-page landscape PDF with populated data. The support
matrix records which findings this proves and which schema-published features
remain gated.

Expanded baseline, verified from a populated five-page PDF on 2026-09-19:
custom-SQL sources on a hidden data page, comparative KPI scorecards, inline
SVG hero/band images, themed multi-page output, conditional tables, and a
column-backed `waterfall-chart` all rendered successfully. This evidence
supersedes the earlier policy that rejected waterfall charts and treated
report settings as unproven.

Shared-shape refresh, verified 2026-09-15 against the compiled OpenAPI and a
non-persistent `dryRun: true` request: common element pointers now use
`{columnId: ...}`, pivot shelves use `{columnId: ...}`, and
`seriesLineAreaStyle` is a list of `{columnId, style}` objects. Text/KPI
alignment uses directional values (`left`/`center`/`right` and
`top`/`center`/`bottom`), not `start`/`middle`/`end`. The old pointer, map, and
alignment forms returned HTTP 400 while the replacement forms verified
`valid:true`. Report PUT also publishes optional `documentVersion` for
optimistic concurrency.

When documentation, this skill, and a live verify/readback disagree, prefer
the live result and preserve the evidence.

## Prerequisites and safety

1. Authenticate with the `sigma-api` skill. Set `SIGMA_BASE_URL` and
   `SIGMA_API_TOKEN`.
2. Confirm reports are enabled for the organization and the caller has
   **Create, edit, and publish reports** permission. Updating also requires
   **Can edit** access to the report.
3. Treat every create as persistent. The current OpenAPI exposes no report
   DELETE endpoint. Do not create a probe report without explicit user
   approval and a named destination folder.
4. Treat PUT as full-contents replacement, and remember it's **contents-only**
   — `name`, `folderId`, or `description` sent alongside `contents` are
   silently ignored, not applied. Always GET, back up, compare, edit,
   validate, verify, PUT with the retrieved `documentVersion`, and read back.
5. A report GET can omit unsupported UI-authored features. Never assume a GET
   representation is lossless merely because the request succeeded.

## Recommended workflow

### Step 1: Discover identity and folder; use references only when needed

```bash
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/whoami" > /tmp/whoami.json
```

Do not browse arbitrary reports. If the OpenAPI, scaffolds, and references do
not answer a specific shape question, list reports once, choose one relevant
reference, cache its spec, and use it only for that question. Obtain the
current `schemaVersion` from a relevant report GET or a user-provided target;
do not hardcode the value shown in examples.

```bash
# List once; pick one relevant reference.
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/reports?limit=25" | jq '.entries[] | {reportId, name, path}'

# Cache its spec and read the current schemaVersion.
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/reports/<reference-report-id>?includeContents=true" \
  > /tmp/reference-report.json
jq '.contents.schemaVersion' /tmp/reference-report.json
```

Load `reference/workflows/discover.md` and resolve the report's source,
all paginated columns, grain, period rules, and page-slice counts before
drafting. The raw table-columns endpoint returns only 50 entries by default.

### Step 2: Classify and scaffold the report

Load `reference/workflows/generate.md`. Classify the request as an executive/
board report, wide operational table, or statement. Generate a complete local
starting point instead of drafting raw JSON from nothing:

```bash
ruby scripts/scaffold-report.rb \
  --template board \
  --name "Quarterly Business Review" \
  --folder-id "<folder-id>" \
  --connection-id "<connection-id>" \
  --company "ACME" \
  --output /tmp/report-spec.json
```

Use `--template wide-table` for multi-page tabloid-landscape tables. Replace
the synthetic SQL/data labels while retaining the proven geometry, panels,
hidden data page, and explicit column contracts.

### Step 3: Load the relevant references

Always read:

- `reference/specification/schema.md`
- `reference/specification/layout.md`
- `reference/specification/support-matrix.md`
- `reference/workflows/discover.md`
- `reference/workflows/validate.md`

Also read `reference/workflows/crud.md` before an API write and
`reference/workflows/convert.md` before converting a workbook.

Common element internals, source formulas, and column shapes are published in
the same OpenAPI union used by workbooks. If `sigma-workbooks` is installed,
its table, chart, map, KPI, control, source, formula, and formatting references
are useful shape recipes. Apply only kinds allowed by the report support
matrix, and never copy workbook grid layout or workbook-only elements.

For shared shapes changed by the released code contract:

- use `columnId`, never `id`, in map channels and pivot
  `rowsBy`/`columnsBy` shelf entries;
- emit `seriesLineAreaStyle` and theme `colorOverrides` as lists, not
  ID/name-keyed maps;
- use `verticalAlign: top|center|bottom`;
- use KPI `layout.anchor: left|center|right` and
  `layout.verticalAnchor: top|center|bottom`;
- wrap page background URLs as
  `backgroundImage: {source: {kind: url, url: ...}, style: ...}`;
- use `settings.theme.{name,overrides}`, not the removed contents-level
  `themeName`/`themeOverrides`.

### Step 4: Draft the wrapped JSON representation

Start with `reference/specification/example-minimal.json`. The create and
verify envelope is:

```json
{
  "name": "Monthly Statement",
  "folderId": "<folder-id>",
  "contents": {
    "schemaVersion": 1,
    "kind": "report",
    "config": {"pageWidth": 816, "pageHeight": 1056, "margin": 48},
    "elements": [],
    "pages": [{"id": "page-1", "name": "Page 1"}],
    "layout": "<Page id=\"page-1\"></Page>"
  }
}
```

Rules:

- Keep literal elements in flat `contents.elements`.
- Keep pages and panels as metadata; never nest `elements` inside them.
- Put all placement in `contents.layout` XML.
- Place leaves with absolute `x`, `y`, `width`, and `height` pixel values.
- Use report panels only for `header` and `footer` regions.
- Do not emit workbook `gridColumn`, `gridRow`, container, tab, overlay, or
  sidebar syntax.
- Compute horizontal positions from widths + gaps and vertical positions from
  a y-cursor. Never rely on unrelated magic-number offsets.
- Put reusable SQL/data-model sources on a hidden data page and declare every
  custom-SQL alias through `[Custom SQL/<alias>]`.
- For wide multi-page output, clone the visible table per page and filter each
  clone with an explicit page-slice key; do not rely on one tall table flowing
  without inspection.

### Step 5: Validate locally

```bash
ruby scripts/validate-spec.rb --mode create /tmp/report-spec.json
```

Fix every error. The validator catches pointer casing/targets, grouped-table
mistakes, SQL contracts, overlaps, geometry, and representation shape.
Warnings identify schema-only/unknown capabilities or visible detail columns
that need a deliberate decision.

### Step 6: Verify without persistence

Add `"dryRun": true` to the request body (`contents` is required when
`dryRun` is true — a 400 results otherwise), then POST to the same create
endpoint:

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-spec-dry-run.json \
  "$SIGMA_BASE_URL/v2/reports" \
  > /tmp/report-verify.json
```

A valid spec returns either bare metadata (no `valid` key) or `{"valid":
true, "warnings": [...]}`; an invalid one returns `{"valid": false, "errors":
[{"summary": ...}], "warnings": [...]}`. Verification checks server-side
representation and dependencies without creating a report. It does not prove
the PDF layout is correct or that GET will round-trip every UI feature.

### Step 7: Create only with explicit approval

After the user approves the persistent write and destination folder:

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-spec.json \
  "$SIGMA_BASE_URL/v2/reports" \
  > /tmp/report-create.json
```

Save the submitted representation under a report-ID-specific path. Report the
report URL, ID, and saved path.

### Step 8: Read back and inspect output

Immediately GET the representation and compare normalized documents. Confirm
that optional fields survived and that no element, panel, page, or setting was
silently dropped. Then export the affected pages to PDF and inspect the actual
page breaks, clipping, typography, header/footer repetition, and margins.

```bash
ruby scripts/verify-report.rb "<report-id>"
ruby scripts/render-report.rb "<report-id>" /tmp/report-render --layout portrait
```

Read every generated `page-N.png`. For dense tables, verify the final visible
row and each subtotal; for board reports, verify the narrative hierarchy,
KPI labels/deltas, chart axes, bridge start/end totals, and negative colors.

Do not claim parity from a successful POST or PUT alone.

### Step 9: Update with a loss check

Follow `reference/workflows/crud.md`. The short version is:

1. GET and back up the current report representation
   (`GET /v2/reports/{id}?includeContents=true`).
2. Inventory the report with `GET /v2/reports/{id}/pages`, `/elements`, and
   `/controls` (commands in `reference/workflows/crud.md`).
3. Stop if the inventory contains content absent from the GET representation.
4. Edit the complete `contents`.
5. Validate in `--mode update` and dry-run it with `POST /v2/reports` +
   `dryRun: true`, assembled from the current name/folder and edited `contents`.
6. PUT `{"contents": {...}, "documentVersion": <version-from-GET>}` to
   `PUT /v2/reports/{id}/contents`. The version is optional in OpenAPI but
   strongly recommended so a concurrent edit fails instead of being
   overwritten. Sending `name`/`folderId`/`description` here is silently
   ignored — this endpoint only ever touches `contents`.
7. GET again, compare, export, and inspect.

## Reference index

| File | Load when |
|---|---|
| `reference/specification/schema.md` | Always. Wrapped envelope, contents fields, pages, panels, response metadata. |
| `reference/specification/layout.md` | Always. Pixel XML, bounds, page and panel placement. |
| `reference/specification/support-matrix.md` | Always. Safe, gated, unsupported, and workbook-only kinds. |
| `reference/specification/example-minimal.json` | Starting a new report representation. |
| `reference/workflows/discover.md` | Finding sources/columns, proving grain, resolving periods, and sizing page slices. |
| `reference/workflows/generate.md` | Generating executive/board reports, statements, or wide multi-page operational tables. |
| `reference/workflows/crud.md` | Creating, retrieving, or replacing a report's contents. |
| `reference/workflows/validate.md` | Before every verify, POST, or PUT and after readback. |
| `reference/workflows/convert.md` | Converting an existing workbook into a report. |

## Troubleshooting

| Symptom | Action |
|---|---|
| `unknown field`, `unexpected property`, or missing field | Compare the endpoint against the compiled OpenAPI and rerun the contract test. |
| `Invalid kind` after adding a channel or shelf | Replace legacy `{id: ...}` with `{columnId: ...}` and check list-vs-map fields. |
| A field or element disappears on GET | Treat the representation as lossy; do not PUT until the omitted feature is removed intentionally or preserved another way. |
| Content overlaps or clips | Check pixel bounds, page dimensions, margins, and repeated panel height; inspect a PDF export. |
| A wide table clips or loses its final rows | Split it into explicit page-filtered table clones, budget row height, and inspect every rendered page. |
| `columnID`, `{id: ...}`, or an unknown column pointer appears | Use exact `columnId` and a column ID declared on the owning element; run the local validator before verify. |
| A custom-SQL source renders unknown columns | Quote aliases in SQL and declare each with `[Custom SQL/<exact alias>]`. |
| A workbook grid attribute appears in report XML | Replace it with absolute `x`, `y`, `width`, and `height`. |
| `progress` or synced control is requested | Stop or redesign; the published schema is not a safe report-authoring guarantee. `waterfall-chart` is supported using the proven shape in the board scaffold. |
| Conversion succeeds with warnings | Review every warning and its element IDs before accepting the generated report. |

Reports are private beta. Prefer explicit evidence and reversible local edits
over speculative API writes.
