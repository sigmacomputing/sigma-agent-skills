#!/usr/bin/env bash
# validate-spec.sh — scan a workbook spec for likely formula-qualification errors.
#
# Catches the #1 Sigma spec mistake: a bare bracketed reference (e.g. [Question ID])
# inside a formula when the referenced column actually lives on the source element,
# not the current one, and therefore needs a prefix (e.g. [AI Usage Data/Question ID]).
#
# Accepts YAML (recommended) or JSON input. YAML is detected by the
# .yaml/.yml extension and converted to JSON internally before the jq pass.
#
# Usage: ./validate-spec.sh <path-to-spec.yaml|.json>
# Exit codes:
#   0  — no obvious issues
#   1  — issues found
#   2  — setup / input error
#
# Limitations: regex-based, so it does not parse formulas semantically. It can
# produce false positives on bracketed text inside string literals (e.g.
# DateFormat(..., "[MM] %Y") ) — inspect flagged cases before blindly fixing.
# It does NOT verify that qualified refs ([Source/col]) point to real sources;
# the server reports those.

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ]; then
  echo "Usage: $0 <path-to-spec.yaml|.json>" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)." >&2
  exit 2
fi

if [ ! -f "$FILE" ]; then
  echo "Error: file not found: $FILE" >&2
  exit 2
fi

# Convert YAML → JSON in memory if the file looks like YAML.
#
# Earlier versions trusted yq's exit code as proof of JSON output, which broke
# against Go yq (mikefarah, Homebrew default on macOS): `yq . file.yaml` exits 0
# but emits YAML, not JSON, so the downstream jq call failed with
# "Invalid literal at line 1, column 5". Fix: try Go yq's explicit -o=json first,
# fall back to Python yq's bare `.`, and validate each candidate with `jq empty`
# before accepting it — the success criterion is now "output parses as JSON",
# not "yq exited 0".
to_json() {
  case "$FILE" in
    *.yaml|*.yml)
      if command -v yq >/dev/null 2>&1; then
        # Go yq (mikefarah) — explicit JSON output flag, unambiguous.
        out=$(yq -o=json . "$FILE" 2>/dev/null) \
          && printf '%s' "$out" | jq empty >/dev/null 2>&1 \
          && { printf '%s' "$out"; return 0; }
        # Python yq (kislyuk) — bare `.` already emits JSON.
        out=$(yq . "$FILE" 2>/dev/null) \
          && printf '%s' "$out" | jq empty >/dev/null 2>&1 \
          && { printf '%s' "$out"; return 0; }
      fi
      if command -v python3 >/dev/null 2>&1; then
        python3 - "$FILE" <<'PY' 2>/dev/null && return 0
import sys, json
try:
    import yaml
except ImportError:
    sys.exit(2)
with open(sys.argv[1]) as f:
    print(json.dumps(yaml.safe_load(f)))
PY
      fi
      echo "Error: cannot convert YAML to JSON. Install one of:" >&2
      echo "  - Go yq:        brew install yq                (recommended on macOS)" >&2
      echo "  - Python yq:    pip install yq" >&2
      echo "  - PyYAML:       pip install PyYAML            (python3 + import yaml)" >&2
      exit 2
      ;;
    *)
      cat "$FILE"
      ;;
  esac
}

SPEC_JSON="$(to_json)"

# The live workbook content API (POST /v2/workbooks + PUT /v2/workbooks/{id}/contents)
# requires a wrapped contents object with one flat contents.elements array. Pages,
# overlays, and panels are metadata only; contents.layout is the source of truth
# for placement and containment.
#
# NOTE: the compiled OpenAPI's CreateWorkbookSpec schema (and the /v2/workbooks/spec
# endpoint family it belongs to) names this wrapper "document" instead — but that
# endpoint family is being removed, and it is NOT what POST /v2/workbooks / PUT
# /v2/workbooks/{id}/contents accept on the wire (live-verified: a "document"-keyed
# body is silently ignored there, producing a blank workbook). Always validate
# against "contents", matching this skill's documented create/update flow.
SHAPE_ISSUES=$(printf '%s' "$SPEC_JSON" | jq -r '
  if (.contents | type) != "object" then
    "Missing required object: contents"
  else
    .contents as $d |
    (["schemaVersion", "kind", "elements", "pages"][] |
      select($d[.] == null) | "Missing required contents field: \(.)"),
    (select(($d.elements | type) != "array") | "contents.elements must be an array"),
    (select(($d.pages | type) != "array") | "contents.pages must be an array"),
    (select($d.kind != null and $d.kind != "workbook") | "contents.kind must be workbook"),
    ($d.pages[]? | select(has("elements")) |
      "Page \(.id // "(unnamed)") contains forbidden nested elements; move them to contents.elements"),
    ($d.overlays[]? | select(has("elements")) |
      "Overlay \(.id // "(unnamed)") contains forbidden nested elements; move them to contents.elements"),
    ($d.panels[]? | select(has("elements")) |
      "Panel \(.id // "(unnamed)") contains forbidden nested elements; move them to contents.elements"),
    ($d.elements[]? |
      select(.kind == "container" and .style.padding? != null and .style.padding != "none") |
      "Container \(.id // "(unnamed)") style.padding must be none or omitted"),
    (select(($d.elements | type) == "array" and ($d.elements | length) > 0 and
      (($d.layout // "") | length) == 0) |
      "contents.layout is required by skill policy when contents.elements is non-empty")
  end
')

FORMULA_ISSUES=$(printf '%s' "$SPEC_JSON" | jq -r '
  .contents.elements[]? |
    . as $element |
    select($element.source.kind != "warehouse-table") |
    (.columns // []) as $cols |
    ($cols | map(.name // "")) as $named |
    ($cols | map(
      (.formula // "") |
      (try capture("^\\[[^/]+/(?<name>[^\\]]+)\\]$").name catch "")
    )) as $derived |
    (($named + $derived) | map(select(. != ""))) as $siblings |
    $cols[]? |
    . as $col |
    ($col.formula // "") as $formula |
    ( [ $formula | scan("\\[[^/\\]]+\\]") | .[1:-1] ] ) as $bare_refs |
    ( $bare_refs | map(select(. as $ref | $siblings | index($ref) | not)) ) as $unresolved |
    select($unresolved | length > 0) |
    "Element: \($element.name // $element.id // "(unnamed)")\n  Column: \($col.name // $col.id // "(unnamed)")\n  Formula: \($formula)\n  Unresolved bare refs: \($unresolved | join(", "))\n"
')

LAYOUT_ISSUES=$(printf '%s' "$SPEC_JSON" | jq -r '
  .contents as $d |
  (($d.elements // []) | map(.id) | map(select(. != null))) as $declared_all |
  ($declared_all | unique) as $declared |
  ([($d.layout // "") | scan("elementId=\"([^\"]+)\"") | .[0]]) as $placed_all |
  ($placed_all | unique) as $placed |
  ([($d.pages // [])[], ($d.overlays // [])[], ($d.panels // [])[]] |
    map(.id) | map(select(. != null)) | unique) as $declared_regions |
  ([($d.layout // "") | scan("<(?:Page|Overlay|Panel)[^>]*\\bid=\"([^\"]+)\"") | .[0]] | unique) as $placed_regions |
  (($d.elements // []) | map(select(.kind == "page-break") | .id)) as $page_break_ids |
  ([($d.layout // "") |
    scan("<(?:Element|LayoutElement)\\b[^>]*\\belementId=\"([^\"]+)\"[^>]*\\bgridRow=\"\\s*([0-9]+)\\s*/\\s*([0-9]+)\"")]) as $leaf_rows |
  (($d.layout // "") |
    select(test("<LayoutElement\\b")) |
    "Legacy layout tag <LayoutElement> is forbidden for authoring; emit <Element>"),
  (($d.layout // "") |
    select(test("<GridContainer\\b")) |
    "Legacy layout tag <GridContainer> is forbidden for authoring; emit <Container>"),
  ($leaf_rows[]? as $row |
    select(($page_break_ids | index($row[0])) != null and
      (($row[2] | tonumber) - ($row[1] | tonumber) != 1)) |
    "Page break \($row[0]) must span exactly one grid row (got \($row[1]) / \($row[2]))"),
  ($declared_all | group_by(.)[] | select(length > 1) | .[0] |
    "Duplicate contents.elements id: \(.)"),
  ($placed_all | group_by(.)[] | select(length > 1) | .[0] |
    "Element is placed more than once in contents.layout: \(.)"),
  ($placed - $declared)[]? | "Layout references undeclared elementId: \(.)",
  ($declared - $placed)[]? | "Element is not placed in contents.layout: \(.)",
  ($placed_regions - $declared_regions)[]? | "Layout references undeclared page/overlay/panel id: \(.)",
  ($declared_regions - $placed_regions)[]? | "Page/overlay/panel is missing from contents.layout: \(.)"
')

if [ -z "$SHAPE_ISSUES" ] && [ -z "$FORMULA_ISSUES" ] && [ -z "$LAYOUT_ISSUES" ]; then
  echo "OK: no obvious formula qualification errors."
  echo ""
  echo "Note: bare refs on warehouse-table sources are accepted as raw warehouse columns."
  echo "For other sources, this validator flags bare refs ([col] without a '/') that don't"
  echo "match a declared sibling column. It also checks the wrapped flat-contents shape and"
  echo "layout coverage. Qualified refs require server readback and compile verification"
  echo "because Sigma may canonicalize warehouse names on POST."
  exit 0
fi

if [ -n "$SHAPE_ISSUES" ]; then
  echo "Workbook shape errors:"
  echo ""
  echo "$SHAPE_ISSUES"
  echo ""
fi

if [ -n "$LAYOUT_ISSUES" ]; then
  echo "Workbook layout errors:"
  echo ""
  echo "$LAYOUT_ISSUES"
  echo ""
fi

if [ -n "$FORMULA_ISSUES" ]; then
  echo "Likely formula qualification errors:"
  echo ""
  echo "$FORMULA_ISSUES"
  echo "Fix: outside a warehouse-table source, a bare bracketed ref ([col] with no '/')"
  echo "must match a declared column in the SAME element. Otherwise add the source prefix."
  echo ""
  echo "  Wrong:  Count([Question ID])"
  echo "  Right:  Count([AI Usage Data/Question ID])"
fi
exit 1
