# Report Pixel Layout

Report layout is an XML fragment stored in `contents.layout`. It is not the
responsive CSS-grid representation used by workbooks.

## Grammar

Top-level roots are `<Page>` and `<Panel>`. Leaf elements use absolute pixel
coordinates:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page id="page-1">
  <Element elementId="title" x="48" y="40" width="720" height="48"/>
  <Element elementId="detail" x="48" y="112" width="720" height="760"/>
</Page>
<Panel id="statement-footer" type="footer">
  <Element elementId="footer-text" x="48" y="8" width="720" height="24"/>
</Panel>
```

The API describes layout as a fragment with multiple top-level roots. XML
tools that require one document root must wrap it temporarily for parsing;
never send that wrapper to Sigma.

## Placement rules

- Each `<Page id>` matches exactly one `contents.pages[].id`.
- Each `<Panel id>` matches exactly one `contents.panels[].id`.
- Panel layout `type` must equal the panel metadata type: `header` or `footer`.
- Each `<Element elementId>` matches one flat `contents.elements[].id`.
- Place each element exactly once across all pages and panels.
- `x` and `y` are finite, non-negative pixel coordinates.
- `width` and `height` are finite, positive pixel dimensions.
- An element must fit within its page dimensions or panel dimensions.
- Put no element arrays inside page or panel metadata.

## Page and margin bounds

`contents.config.pageWidth` and `pageHeight` define the physical page canvas.
`margin` defines the intended inset. The local validator enforces the outer
page bounds and checks that margins leave a positive content area.

Keep authored page content inside the margin unless the design intentionally
uses bleed. A layout can be mathematically inside the page and still overlap a
header, footer, or printable margin, so PDF inspection remains mandatory.

For a page width `W`, height `H`, and margin `M`, a conservative content box is:

```
x >= M
y >= M + header height
x + width <= W - M
y + height <= H - M - footer height
```

The API's absolute coordinate origin and panel repetition behavior should be
confirmed from a readback/PDF in the target organization before automating a
large document.

## Forbidden workbook syntax

Do not use:

- `gridColumn`, `gridRow`, `gridTemplateColumns`, `gridTemplateRows`
- `<Container>`, `<TabbedContainer>`, `<Tab>`, `<Overlay>`
- workbook header/sidebar panel types
- workbook-only `kind` values: `chat`, `code`, `container`, `form`,
  `navigation`, `page-break`, `repeated-container`, `single-row-container`,
  `tabbed-container`, and `value-list`

Those constructs belong to workbook layout. A report page already has fixed
physical dimensions; pagination comes from report pages, not workbook
`page-break` elements.

## Header and footer panels

A report panel is declared once and assigned to pages through `panels[].pages`.
Its content is placed in one matching layout root:

```xml
<Panel id="statement-header" type="header">
  <Element elementId="company-logo" x="48" y="8" width="120" height="40"/>
  <Element elementId="statement-label" x="520" y="8" width="248" height="40"/>
</Panel>
```

Size panel children against `panels[].config.height` and the report page width.
A page can receive at most one header and one footer.

Live-confirmed 2026-08-11: a 70-pixel navy header and 30-pixel footer, each
containing styled text elements, passed verify and create, round-tripped with
panel metadata and layout unchanged, survived a full-contents PUT, and rendered
in the exported landscape PDF. Panel element coordinates are local to the
panel; the visible page's element coordinates remained local to the page body.

## Validation

Run:

```bash
ruby scripts/validate-spec.rb --mode create /tmp/report-spec.json
```

The validator parses XML with a real XML parser, rejects workbook grid
attributes and nested layout tags, checks page/panel roots, verifies exact
element coverage, and checks numeric outer bounds. It cannot prove visual
quality. Export and inspect a PDF after every persistent write.
