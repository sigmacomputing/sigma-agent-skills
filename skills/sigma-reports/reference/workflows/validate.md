# Report Validation

Validation has four separate gates. None substitutes for another.

## 1. Offline representation validation

```bash
ruby scripts/validate-spec.rb --mode create /tmp/report-spec.json
ruby scripts/validate-spec.rb --mode update /tmp/report-put.json
```

The validator checks:

- create or update wrapper shape;
- required `contents` fields and `kind: report`;
- page, panel, and element IDs;
- 1,000-page and 10,000-pixel limits;
- panel types, page assignments, and one-header/one-footer per page;
- documented unsupported, workbook-only, schema-only, and unknown kinds;
- released `columnId` pointers, list-shaped series/theme overrides, and
  directional alignment values;
- page `backgroundImage.source` wrappers and removal of legacy theme keys;
- real XML parsing of Page, Panel, and Element layout nodes;
- absolute numeric coordinates and dimensions;
- page and panel outer bounds;
- exact one-time placement of every element;
- matching layout roots for pages and panels;
- rejection of workbook grid/container syntax.

Warnings are not proof of safety. Resolve schema-only or unknown kinds through
a targeted OpenAPI review and live verify before writing.

## 2. Server verify

POST the create envelope to `/v2/reports` with `dryRun: true`. This is
non-persistent and should precede every create or update. For an update, wrap
the edited `contents` with the current report name and folder solely for
verification, then send `{contents: ..., documentVersion: ...}` to
`PUT /v2/reports/{id}/contents`.

Verify can catch schema and dependency errors that an offline validator cannot.

For a faster signal than a full PDF on whether each element's formulas actually
compile, query one element at a time:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/reports/<report-id>/elements/<element-id>/query"
```

The response carries the generated SQL (`{elementId, name, sql}`), or the
compile error for that element. This is the cheapest way to catch
`Unknown column` and `Circular column reference` — neither of which fails
create, verify, or readback. Run it for every data element before trusting a
report.

Non-data elements have no query: a `text` element returns HTTP 404
`Could not get sheetId`. That is expected, not a defect — only query-backed
kinds (tables, charts, KPIs) return SQL.

## 3. Readback and loss detection

After every persistent write, GET the report representation and compare:

- all element, page, and panel IDs;
- sources, columns, formulas, formats, and filters;
- layout coordinates and dimensions;
- report page configuration;
- panel assignments and heights;
- fields that the service normalized or dropped.

Distinguish the two. A **normalized** field is one whose submitted value equals
the server default and is therefore omitted from the readback — KPI
`layout.verticalAnchor: center` behaves exactly this way, while `top` and
`bottom` persist. A **dropped** field is absent regardless of value. Only the
second is lossy. Diff a non-default value before concluding a field is
unsupported, or an equality check on the readback will raise a false alarm and
push you toward deleting a field that actually works.

Before updating an existing report, compare the GET representation with page,
element, and control inventory endpoints. A feature present in inventory but
absent from the code representation is a destructive-update risk.

## 4. PDF and data parity

Export the affected report to PDF and inspect:

- clipping and overlap;
- page breaks and page count;
- margins, bleed, and whitespace;
- repeating header/footer placement;
- fonts, colors, images, and chart legends;
- table row continuation and totals;
- control/filter effects;
- representative values and aggregates against the warehouse.

API success cannot prove visual or data parity.

## Common failures

| Failure | Meaning |
|---|---|
| `contents.kind must be report` | Workbook contents were sent to a report endpoint. |
| element missing from layout | Add one `<Element elementId="...">` under a Page or Panel root. |
| undeclared element in layout | Fix the ID or add the literal element to `contents.elements`. |
| workbook grid attribute | Replace grid syntax with pixel `x`, `y`, `width`, and `height`. |
| channel or pivot shelf uses `id` | Replace it with `columnId`; the old pointer shape is rejected. |
| `seriesLineAreaStyle` or `colorOverrides` is an object map | Emit a list of `{columnId, style}` or `{name, color}` objects. |
| alignment uses `start`, `middle`, or `end` | Use released directional values (`left`/`center`/`right`, `top`/`center`/`bottom`). |
| page background has a flat `url` | Nest it under `backgroundImage.source` with `kind: url`. |
| contents uses `themeName` or `themeOverrides` | Move them under `settings.theme.name` / `settings.theme.overrides`. |
| panel type mismatch | Make layout and metadata both `header` or both `footer`. |
| field disappears on GET | Re-send a non-default value first: a default-valued field is normalized away, not dropped. If it vanishes for every value, treat readback as lossy and do not blindly PUT the result. |
| verify succeeds but PDF is wrong | Fix physical layout; verify is not a render test. |
