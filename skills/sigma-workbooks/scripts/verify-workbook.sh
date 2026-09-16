#!/usr/bin/env bash
# verify-workbook.sh — confirm a created workbook's elements compile to valid SQL.
#
# Why this exists: POST /v2/workbooks is generous. It accepts specs whose
# column formulas don't actually resolve, then surfaces the failures at query
# time as string literals embedded in the compiled SQL — e.g.
#   select 'Unknown column "[ORDER_TOTAL]"' V_44 from ...
#   select 'Circular column reference to [Quarter]' V_11 ...
# The UI renders these elements as empty. Catching this is impossible from the
# spec alone; only Sigma's compiler knows. This script asks the server.
#
# For each element on the workbook, it fetches the compiled SQL via
#   GET /v2/workbooks/{id}/elements/{eid}/query
# and greps the markers. Any hit means a formula doesn't resolve.
#
# Usage: ./verify-workbook.sh <workbook-id>
# Requires env: SIGMA_BASE_URL, SIGMA_API_TOKEN.
# Exit codes:
#   0  — every element compiled clean
#   1  — one or more elements have unresolved/circular references
#   2  — setup / input error

set -euo pipefail

WB_ID="${1:-}"
if [ -z "$WB_ID" ]; then
  echo "Usage: $0 <workbook-id>" >&2
  exit 2
fi

if [ -z "${SIGMA_BASE_URL:-}" ] || [ -z "${SIGMA_API_TOKEN:-}" ]; then
  echo "Error: SIGMA_BASE_URL and SIGMA_API_TOKEN must be set in the environment." >&2
  echo "Authenticate via the sigma-api skill first." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 2
fi

ELEMENTS_JSON=$(curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/$WB_ID/elements") || {
  echo "Error: could not fetch elements for workbook $WB_ID." >&2
  exit 2
}

ERRORS=0
TOTAL=0
while IFS=$'\t' read -r EID NAME; do
  TOTAL=$((TOTAL + 1))
  # /elements/{id}/query 4xx's on controls and similar non-queryable elements —
  # don't let -f kill the loop. Just skip them.
  RAW=$(curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
    "$SIGMA_BASE_URL/v2/workbooks/$WB_ID/elements/$EID/query")
  SQL=$(printf '%s' "$RAW" | jq -r '.sql // ""' 2>/dev/null || true)

  if [ -z "$SQL" ]; then
    printf '  [skip] %-30s (%s) — no SQL (control or non-queryable element)\n' "$NAME" "$EID"
    continue
  fi

  # grep exits 1 when no matches, which would trip `set -o pipefail` — swallow that
  # case explicitly so a clean element doesn't kill the loop.
  BAD=$(printf '%s' "$SQL" \
    | grep -oE "(Unknown column \"[^\"]+\"|Circular column reference to \[[^]]+\])" \
    | sort -u | paste -sd '; ' - || true)
  if [ -n "$BAD" ]; then
    printf '  [FAIL] %-30s (%s) — %s\n' "$NAME" "$EID" "$BAD"
    ERRORS=$((ERRORS + 1))
  else
    printf '  [ok]   %-30s (%s)\n' "$NAME" "$EID"
  fi
done < <(echo "$ELEMENTS_JSON" | jq -r '.entries[]? | [.elementId, .name] | @tsv')

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "$ERRORS of $TOTAL element(s) have unresolved formula references."
  echo "Fix the offending columns in the spec (see reference/specification/formulas.md)"
  echo "and re-PUT the spec, then re-verify."
  exit 1
fi
echo "All $TOTAL element(s) compile cleanly."
exit 0
