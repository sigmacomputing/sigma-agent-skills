# Materializations

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Trigger and poll materialization jobs across workbooks and data models.
Load this when the user wants to refresh / build / cache a workbook
element or data-model element, or to inspect a running job.

Everything here lives under `workbooks materializations` /
`workbooks materialization-schedules` and the parallel `data-models`
sub-groups (plus `datasets materialization`, which the spec marks
deprecated). Run
`sigma api workbooks --help` / `sigma api data-models --help` for the
current shape.

A *materialization* is an async job that runs a query and stores its
result. Two halves: trigger (ad-hoc or scheduled) → poll the job
document for status. This is the status-field-polling shape referenced
in `SKILL.md`'s `## Polling async jobs`. The job document requires
`materializationId` and `status`; `startedAt`, `readyAt`, `expiredAt`,
and `error` are optional. `status` is an open string, not a closed enum —
don't hardcode its values.

## Workflow — trigger and poll a workbook materialization

`sheetId` in the request body is **not** the element ID — it's the
identifier of that element's *materialization schedule*, and it's opaque
(e.g. `cNJfIyk3vM`), unrelated to the element's own `id`/`elementId`.
`workbookId` is the only parameter this operation declares. (Passing
`elementId` in `--params` would be silently forwarded as a query parameter
and ignored; see `SKILL.md` *Calling convention*.)

A schedule must already exist for the element before this call will
succeed — as of this writing there's no `create`/`update` endpoint for
`workbooks materialization-schedules` (`--help` shows `list` only), so
today that means materialization was enabled on the element through the
Sigma UI, not via `sigma api`. Check `--help` yourself before assuming
that's still true. Look up the real `sheetId` first — and note that entries
identify their element by **`elementName`, not `elementId`**, so an element id
from `workbooks elements list` gives you nothing to join on here; match on the
name, and say so when you report which element you materialized:

```sh
sigma api workbooks materialization-schedules list \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  | jq '.entries[] | {elementName, sheetId, paused}'
```

Then trigger and poll using that `sheetId`. The trigger call itself
commonly fails before any job exists — confirmed live: 403 (credential
lacks materialize permission), 400 ("Scheduled materialization is not
configured for this element" — the schedule lookup above was skipped or
is stale), and 409 ("Materialization already in progress" — a schedule or
another caller already has one running). None of these produce a
`materializationId`, so check for one before polling; otherwise the loop
below polls a `null` ID until `DEADLINE` instead of failing fast:

```sh
RESP=$(sigma api workbooks materializations create \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json   '{"sheetId":"<SHEET_ID_FROM_SCHEDULES_LIST>"}')
JOB_ID=$(echo "$RESP" | jq -r '.materializationId // empty')
if [ -z "$JOB_ID" ]; then
  echo "trigger failed: $RESP"; exit 1
fi

DEADLINE=$(( $(date +%s) + 900 ))
# Only `pending` and `building` continue the loop. Everything else ends it,
# including a status this list has never seen — an unknown value is a new
# terminal state, not a reason to keep waiting (SKILL.md, "Polling async
# jobs"). Observed terminal values, and what they mean, are in *failure
# triage* below; success is `ready`, not `succeeded`.
while :; do
  STATUS=$(sigma api workbooks materializations get \
    --params "{\"workbookId\":\"<YOUR_WORKBOOK_ID>\",\"materializationId\":\"$JOB_ID\"}" \
    | jq -r '.status')
  case "$STATUS" in
    pending|building) : ;;
    *) echo "materialization ended with status: $STATUS"; break ;;
  esac
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "gave up waiting; last status: $STATUS"; break
  fi
  sleep 5
done
```

## Workflow — trigger and poll a data-model materialization

Same `sheetId`-is-the-schedule-not-the-element caveat as the workbook
workflow above — look up the real value first:

```sh
sigma api data-models materialization-schedules list \
  --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}' \
  | jq '.entries[] | {elementName, sheetId, paused}'
```

```sh
RESP=$(sigma api data-models materialize \
  --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}' \
  --json   '{"sheetId":"<SHEET_ID_FROM_SCHEDULES_LIST>"}')
JOB_ID=$(echo "$RESP" | jq -r '.materializationId // empty')
if [ -z "$JOB_ID" ]; then
  echo "trigger failed: $RESP"; exit 1
fi

# Same trigger-failure checks and poll-until-terminal loop as the workbook
# workflow above — swap in `data-models materializations get` and
# `dataModelId` as the params.
sigma api data-models materializations get \
  --params "{\"dataModelId\":\"<YOUR_DATA_MODEL_ID>\",\"materializationId\":\"$JOB_ID\"}"
```

## Workflow — failure triage

A job ending other than `ready` doesn't necessarily mean failure, and doesn't
necessarily carry an `error` string. Values observed live: `ready` (success),
`failed` (carries `error`), plus `expired`, `canceled`, and `skipped` — that
last meaning Sigma declined to run it because the source data hadn't changed
since the last successful run ([materialization
docs](https://help.sigmacomputing.com/docs/materialization)). `canceled` and
`skipped` have been seen with no `error` field at all. Surface `status` and
`error` together and let the caller interpret the combination, rather than
assuming a non-`ready` status implies an `error`, or matching `status` against a
hardcoded list:

```sh
sigma api workbooks materializations get \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>","materializationId":"<YOUR_JOB_ID>"}' \
  | jq '{status, error: .error // null}'
```

## Workflow — audit existing schedules

```sh
sigma api workbooks materialization-schedules list \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>","limit":50}'

sigma api data-models materialization-schedules list \
  --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}'
```

Schedules are authored inside the workbook or data-model spec body; check
`sigma api workbooks materialization-schedules --help` for a direct
write path before assuming one doesn't exist. To change a schedule via
the spec, see [`workbook-authoring.md`](workbook-authoring.md) /
[`data-model-authoring.md`](data-model-authoring.md) and re-PUT.

## Cross-references

- Authoring the schedule (which lives inside the spec) →
  [`workbook-authoring.md`](workbook-authoring.md) /
  [`data-model-authoring.md`](data-model-authoring.md).
- Exporting the materialized result →
  [`delivery-and-schedules.md`](delivery-and-schedules.md).
- Connection refresh / sync (different mechanism — refreshes the schema
  cache, not query results) →
  [`connections-and-sources.md`](connections-and-sources.md).
