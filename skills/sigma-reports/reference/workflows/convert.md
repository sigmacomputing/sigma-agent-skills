# Convert a Workbook to a Report

Use `POST /v2/workbooks/{workbookId}/convertToReport`. The source workbook is
not modified; the endpoint creates a new report.

```json
{
  "name": "Operations Packet",
  "destinationFolderId": "<folder-id>",
  "description": "Printable operations summary",
  "pageIds": ["overview-page-id"],
  "format": {
    "pageSize": "letter",
    "layout": "landscape"
  }
}
```

Preset page sizes are `letter`, `a4`, `legal`, and `a3`, with `portrait` or
`landscape` layout. A custom format accepts `pageSize: custom`, a unit of
`pixels`, `inches`, or `centimeters`, and explicit width/height.

The response contains `convertedReport`, `sourceWorkbook`, and `warnings`.
Treat `warnings` as a required review gate, including unknown future warning
codes. Details can identify source and generated report element IDs.

Conversion can remove unsupported contents or move supported dependents to a
hidden page. Common risks include containers, repeated containers, tabs,
actions, overlays, sidebars, schedules, and sharing configuration. Do not
accept a converted report until you:

1. Review every warning and affected ID.
2. GET the generated report representation.
3. Compare source workbook intent with generated report pages and elements.
4. Replace workbook interaction patterns with fixed report-page designs.
5. Validate the representation locally and through report verify.
6. Export the complete report to PDF and inspect every page.
7. Recreate report schedules, grants, and delivery settings intentionally;
   they are not implied by code-representation conversion.

Conversion is persistent and creates a report. Obtain explicit approval for
the destination and name before invoking it.
