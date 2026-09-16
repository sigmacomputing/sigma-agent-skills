# Report Element Support Matrix

The report request schema references `CommonElement`, but schema publication is
not the same as safe report support. Use this conservative matrix.

## States

| State | Meaning | Authoring policy |
|---|---|---|
| Live-proven | Passed a dry run, create, readback, update, and PDF export in a report-enabled org | Safe baseline; still validate each new shape |
| Documented | Covered by report examples or report documentation and present in OpenAPI | Validate and verify before write |
| Schema-only | Present in `CommonElement`, but report behavior or PDF behavior is not established here | Warn; require targeted live verify/readback/PDF evidence |
| Unsupported | Report documentation identifies the feature as unsupported | Reject for authoring |
| Workbook-only | Present only in `WorkbookElement` | Reject; redesign or use a workbook |

## Live-proven baseline

The following kinds passed a dry run, persistent create, GET readback,
full-contents PUT, and populated landscape PDF export on 2026-08-11:

- `bar-chart`, including horizontal orientation, single color, sorting, and
  hidden legend
- `combo-chart`, with bar and line series over a `DateTrunc("quarter", ...)`
  axis
- `kpi-chart`, with `Sum`, `CountDistinct`, ratio formulas, number formats,
  value color/font size, and layout anchor/title orientation
- `table`, including warehouse-table and table-element sources, grouping,
  aggregate calculations, presentation style, banding, horizontal grid lines,
  and `dataBars` conditional formatting
- `text`, including Markdown and inline font/color styling

The same report proved a hidden dependency page, absolute pixel layout,
header/footer panel assignment and rendering, complete panel readback, and a
new document version after PUT. This is a baseline, not blanket proof of every
optional field on these kinds.

## Current shared-shape contract

A 2026-09-15 readback of 16 existing reports and non-persistent `/verify`
probes established the released common-element forms:

- text `verticalAlign` is `top`, `center`, or `bottom`;
- KPI `layout.anchor` is `left`, `center`, or `right`, and
  `layout.verticalAnchor` is `top`, `center`, or `bottom`;
- pivot `rowsBy`/`columnsBy` entries are `{columnId: ...}`;
- map and scalar chart channel pointers use `{columnId: ...}`, not `{id: ...}`;
- `seriesLineAreaStyle` is a list of `{columnId, style}` objects, not a map;
- theme `colorOverrides`, when preserving report settings, is a list of
  `{name, color}` objects, not a map.

The current forms returned `valid:true` for a report readback, combo-series
style, and pivot-shelf probe. The corresponding legacy `middle`, `{id: ...}`,
and map-shaped `seriesLineAreaStyle` forms returned HTTP 400. This proves the
shape contract, not blanket report/PDF support for every optional field.

## Documented common kinds

- `area-chart`
- `control`, except `controlType: synced` and the schema-only `file-upload`
- `divider`
- `geography-map`
- `image`
- `line-chart`
- `pivot-table`
- `point-map`
- `region-map`
- `scatter-chart`

Use the current OpenAPI for each complete element shape. When installed, the
matching `sigma-workbooks/reference/specification/` element, source, formula,
and formatting guides provide useful common-shape recipes. Ignore all workbook
layout and workbook-only behavior in those guides.

## Schema-only kinds

- `box-chart`
- `button`
- `embed`
- `funnel-chart`
- `gauge-chart`
- `input-table`
- `plugin`
- `sankey-chart`
- `treemap-chart`

These may verify in some configurations, but interactive or write-back
behavior and PDF output require explicit evidence. The local validator emits a
warning rather than accepting them silently.

`controlType: file-upload` is also schema-only. Its upload lifecycle and PDF
behavior are not established for reports.

The inherited top-level `contents.settings` field is also schema-published but
not report-proven by this skill. Preserve it unchanged when it appears in a
readback, warn before PUT, and do not author new theme/navigation settings
without targeted verify, readback, and PDF evidence. If present,
`settings.theme.overrides.colorOverrides` uses the released list form
`[{name, color}]`.
The removed contents-level `themeName` and `themeOverrides` keys must be moved
to `settings.theme.name` and `settings.theme.overrides`; do not PUT the legacy
keys because the API can silently drop them.

## Unsupported kinds and subtypes

- `waterfall-chart`
- `progress` (gauge/progress presentation)
- `control` with `controlType: synced`

These appear in the shared OpenAPI union but are called unsupported by report
documentation. The local validator rejects them.

## Workbook-only kinds

- `chat`
- `code`
- `container`
- `form`
- `navigation`
- `page-break`
- `repeated-container`
- `single-row-container`
- `tabbed-container`
- `value-list`

Do not emulate these by copying workbook layout XML. Convert the design to
fixed report pages or keep it as a workbook.

## Unknown future kinds

The API can add common kinds before this skill is updated. The validator warns
on an unknown kind instead of claiming it is invalid. Inspect the current
OpenAPI and report documentation, dry-run `POST /v2/reports` with
`dryRun: true`, and update the matrix only after evidence establishes the
correct state.

## Lossy readback warning

`GET /v2/reports/{reportId}?includeContents=true` can omit features
unsupported by report code representation. Before PUT, compare the code
representation with the report's element, page, and control inventory APIs.
If inventory objects are missing from `contents`, stop. Replacing `contents`
can permanently remove omitted features from the next report version.
