# Generate a Polished Multi-Page Report

Use this workflow for net-new executive/board reports, statements, and dense
operational tables. It turns the report request into a reusable configuration
and page system instead of drafting one large JSON object from scratch.

## 1. Classify the report

Choose one primary composition:

| Composition | Use for | Default scaffold |
|---|---|---|
| Executive / board | Narrative, KPIs, trends, bridge, drill-down | `board` |
| Wide operational table | Many columns, subtotals, repeated column groups, multiple physical pages | `wide-table` |
| Statement / notice | Account-level facts, activity detail, legal text | Start from `board`, then simplify |

Generate a local starting point:

```bash
ruby scripts/scaffold-report.rb \
  --template board \
  --name "Quarterly Business Review" \
  --folder-id "<folder-id>" \
  --connection-id "<connection-id>" \
  --company "ACME" \
  --output /tmp/report-spec.json
```

Use `--template wide-table` for tabloid-landscape operational output. Replace
the scaffold's synthetic SQL and labels; keep its geometry, panels, hidden
data page, and source-column contracts until the first successful render.

## 2. Record the report contract before authoring

Run `reference/workflows/discover.md`, then write a short local manifest
containing:

- audience and decision the report supports;
- physical paper/orientation;
- visible pages and each page's one-sentence job;
- repeating header/footer content;
- source tables/data models and exact columns;
- metric definitions, comparison periods, and sign conventions;
- brand tokens (primary, deep, text, muted, line, surface, success, warning,
  danger, categorical series);
- any totals/subtotals and page-splitting key;
- expected row counts and representative values.

Do not browse arbitrary reports for inspiration. Read at most one relevant
reference report when the OpenAPI/scaffolds do not answer a specific shape
question, and cache that readback for the session.

## 3. Build the data layer first

Use a hidden `pdata` page for reusable SQL/data-model source elements. Every
source still needs a layout placement.

For custom SQL, declare a literal column contract:

```json
{
  "id": "src-summary",
  "kind": "table",
  "name": "Summary",
  "source": {
    "kind": "sql",
    "connectionId": "<connection-id>",
    "statement": "SELECT ... AS \"current_sales\""
  },
  "columns": [
    {
      "id": "summary-current-sales",
      "name": "current_sales",
      "formula": "[Custom SQL/current_sales]"
    }
  ]
}
```

Quote SQL aliases when the warehouse otherwise changes their case. Downstream
elements reference the source element's `name`, for example
`Sum([Summary/current_sales])`.

Make date/period logic advance automatically. Resolve the latest closed period
from data and compare equal elapsed periods; do not hardcode a quarter that
will age out.

## 4. Compose with computed geometry

Use `scripts/lib/report_builder.rb` or equivalent helpers:

- define paper size, margins, pages, and panels once;
- compute row x-positions from widths + gaps;
- advance vertical cursors from block heights;
- assert each row fits before emitting layout;
- bake decorative bands/hero surfaces into SVG images when element background
  styling does not render reliably;
- never place columns with unrelated magic-number offsets.

Useful 96-DPI page sizes:

| Paper | Portrait | Landscape |
|---|---:|---:|
| US Letter | 816 × 1056 | 1056 × 816 |
| US Legal | 816 × 1344 | 1344 × 816 |
| US Tabloid | 1056 × 1632 | 1632 × 1056 |
| A4 | 794 × 1123 | 1123 × 794 |

The local validator rejects same-region overlaps. If a design needs text over
an image, compose both into one SVG asset; report element layering is not a
safe authoring surface.

## 5. Executive / board composition

A strong five-page sequence:

1. **Executive highlights** — asymmetric branded hero, three KPI cards,
   five concise data-bound takeaways.
2. **Scorecard** — three labeled columns of comparative KPI cards.
3. **Trend + segment performance** — one chart and one compact table with an
   explicit time-comparison note.
4. **Bridge** — KPI rail plus a waterfall from prior to current total.
5. **Operational drill-down** — summary KPIs and a ranked exception table.

Use section bands sparingly. Keep each page's main question obvious from its
title and the largest visual.

## 6. Wide operational-table composition

Use tabloid landscape for 12–18 tightly formatted columns. Put semantic column
groups in colored bands above one aligned table:

- identity/dimension columns;
- inventory or balance snapshots;
- rolling-period activity;
- turns/rates/days-supply calculations;
- exception or special-population columns.

Do not depend on a single tall table flowing cleanly across pages. Create one
table element per physical page and filter each clone by a deterministic page
slice (`page_no`, brand group, region group, or row-number band). This makes
page breaks reviewable and preserves subtotal groups. Keep source/detail row
ordering stable and color subtotal rows through conditional formatting.

Estimate rows before finalizing height. Tables can clip their last row without
an API error. Conversely, an over-tall table can be classified as expanded by
PDF export and moved onto a separate continuation page, leaving its authored
column-band page empty. Size each page clone to its expected row slice and
export every page before acceptance.

## 7. Validation and render loop

Before any write:

```bash
ruby scripts/validate-spec.rb --mode create /tmp/report-spec.json
```

Then POST the same envelope to `/v2/reports` with `dryRun: true`. Fix locally
and allow one evidence-backed retry per error class—do not rotate through
guessed property names.

After the approved persistent create/update:

```bash
ruby scripts/verify-report.rb "<report-id>"
ruby scripts/render-report.rb "<report-id>" /tmp/report-render --layout portrait
```

Read every rendered PNG. Check:

- page count, clipping, whitespace, and overlap;
- repeated furniture and column-band alignment;
- KPI labels/deltas and chart axes;
- table continuation, subtotal rows, and final visible row;
- negative-value color and sign conventions;
- representative values against the data contract.

Promote any recurring fix into the builder, scaffold, validator, or this
workflow rather than rediscovering it on the next report.
