# Delivery and Schedules

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Get data out of Sigma — one-off exports, scheduled exports, query
downloads, webhooks. Load this when the user wants to email a workbook,
schedule a recurring report, download CSV/JSON from a query, or push to
a webhook.

Everything here lives under `workbooks export` / `send` / `schedules`,
the parallel `reports` sub-groups, `members schedules`, `query download`,
and `webhooks`. Run `sigma api workbooks --help` / `sigma api reports
--help` for the current shape. Export / send / schedule bodies are the
most variable surface in this file — formats, cadence enums, and
delivery channels evolve, and they nest `oneOf` variants several levels
deep — so read the body schema per `SKILL.md` *Discovery loop* step 3
*every time* before composing one.

## Workflow — one-off export of a workbook element

`format` is an **object**, not a string — `{"type":"json"}`, not `"json"`.
The body is a `oneOf`: name the target with either `elementId` or
`pageId`, never both. `type` accepts `csv`, `json`, `jsonl`, and `xlsx`
directly; `pdf` also requires a `layout`. Read the current variants per
`SKILL.md` *Discovery loop* step 3 before using anything else.

The export request returns `queryId` plus a `jobComplete` boolean —
expect `false`. The file is a second call, `query download get`.

**Don't treat the exit code alone as a readiness signal.** A
still-processing export can come back as a zero exit with the literal
`null` written out; the real body arrives on a later attempt. Gate the
loop on the body, not `$?`:

```sh
RESP=$(sigma api workbooks export \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json   '{"elementId":"<YOUR_ELEMENT_ID>","format":{"type":"json"}}')
QUERY_ID=$(jq -r '.queryId // empty' <<<"$RESP")
[ -n "$QUERY_ID" ] || { echo "export request failed: $RESP" >&2; exit 1; }

OUT=./export.json
DEADLINE=$(( $(date +%s) + 900 ))
while :; do
  if sigma api query download get --params "{\"queryId\":\"$QUERY_ID\"}" \
       > "$OUT" && jq -e '. != null' "$OUT" >/dev/null 2>&1; then
    echo "export ready: $OUT"; break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "gave up waiting on export $QUERY_ID" >&2; rm -f "$OUT"; exit 1
  fi
  sleep 5
done
```

The example downloads `json`. For other formats, check
`sigma api query download get --help` for how the CLI writes the body.

This is the retry-until-ready shape referenced in `SKILL.md`'s *Polling
async jobs* — contrast with the status-field shape in
[`materializations.md`](materializations.md).

## Workflow — send a workbook to a recipient

The body's required top level is `targets` / `config` / `attachments` —
not a flat `format` or `recipients` or `subject` field. `targets`
names who receives it (member/team/email, each a `oneOf` variant);
`config` carries title/message fields; `attachments` names what to
export and in what format, per attachment. Read the current variants and
required sub-fields per `SKILL.md` *Discovery loop* step 3 before
composing a body — enum casing and optional fields are the most volatile
part of this shape.

```sh
sigma api workbooks send \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json "$(cat ./send.json)"
```

`reports send` takes an analogous body for the report variant.

## Workflow — schedule a recurring delivery

```sh
# Cadence, format, and recipient shapes are the most volatile bodies in
# the API. Read the body, don't guess it (SKILL.md *Discovery loop* step 3).

sigma api workbooks schedules create \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json "$(cat ./schedule.json)"
```

Update with `workbooks schedules update`, remove with `workbooks
schedules delete`, list with `workbooks schedules list`. Reports follow
the parallel `reports schedules …` shape.

## Workflow — audit a user's deliveries before deprovisioning

Before deactivating a member, list anything they own that will silently
break:

```sh
sigma api members schedules list --params '{"memberId":"<YOUR_MEMBER_ID>"}'
```

Reassign or delete each entry (via `workbooks schedules update` /
`reports schedules update` to change owner/recipients, or the `delete`
counterpart) before calling `members delete`. See
[`identity-and-access.md`](identity-and-access.md) for the full
deprovisioning flow.

## `query` is a download surface

Despite the name, `sigma api query` isn't where you run SQL today — check
`sigma api query --help`, and expect `download get` keyed by a `queryId` an
export already produced. To get rows out, export an element (above) or read an
element's results via `workbooks elements query get`
([`workbook-authoring.md`](workbook-authoring.md)).

## Workflow — trigger a webhook-driven send

`webhooks webhooks` is **not** a generic outbound POST. It's scoped to one
workbook and one configured webhook sequence — both are required path
parameters — and the body is whatever payload that sequence was configured to
accept in Sigma, so its schema is open by design.

```sh
sigma api webhooks webhooks \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>","sequenceId":"<YOUR_SEQUENCE_ID>"}' \
  --json   '{"…":"payload matching the configured webhook spec"}'
```

The `sequenceId` identifies that configured sequence. Run
`sigma api webhooks --help` for the current operation set — if no enumerate
path is listed, get the id from whoever configured the webhook in Sigma.

## Cross-references

- The workbook or report being exported →
  [`workbook-authoring.md`](workbook-authoring.md). Reports CRUD lives
  in this file (it's a delivery-shaped resource).
- Granting external recipients access via signed embed URLs (alternative
  to email delivery) →
  [`permissions-and-sharing.md`](permissions-and-sharing.md).
- Materialization-driven snapshots (when the export should reflect a
  stored snapshot rather than a live query) →
  [`materializations.md`](materializations.md).
