# Workbook Authoring

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Build, inspect, and update workbooks programmatically. Load this when the
user wants to author a dashboard from a spec, edit one in place, or
introspect what's inside one.

> This file covers the `sigma api …` calls that drive workbook workflows.
> Spec-body content — formula syntax, layout XML, source shapes, validation
> — is not covered here.

Everything here lives under `sigma api workbooks …`. Run
`sigma api workbooks --help` for its current sub-groups.

## Content endpoints

A workbook's code representation goes through the workbook resource itself:

| Step | Command |
|------|---------|
| Read | `sigma api workbooks get` with `"includeContents":true` in `--params` |
| Validate without saving | `sigma api workbooks create` with `"dryRun":true` in the `--json` body |
| Create | `sigma api workbooks create` with `contents` in the `--json` body |
| Replace contents | `PUT /v2/workbooks/{workbookId}/contents` (see *iterate* below) |

The body wraps the representation as `{"name", "folderId", "contents": {…}}`.
A body keyed `document` instead of `contents` is the shape of the older
`workbooks spec …` commands; don't send it to `workbooks create`. Use the
commands above rather than `workbooks spec …`.

`includeContents`, `dryRun`, and `contents` may not show up in
`sigma api schema` or `--help` yet. The CLI still sends them: `--params` keys
the operation doesn't declare go out as query parameters, and `--json` is sent
as written.

## Workflow — build a workbook from a spec file

Always study a reference spec first — the spec body shape evolves and
real workbooks are the best documentation. If the org has none to
study, make one — see *No reference workbook on the org?* below.

```sh
# 1. Find a workbook to use as a reference, by name
sigma api workbooks list \
  | jq -r '.entries[] | select(.name == "<REFERENCE_WORKBOOK_NAME>") | .workbookId'

# 2. Pull its contents to study structure
sigma api workbooks get \
  --params '{"workbookId":"<YOUR_TEMPLATE_ID>","includeContents":true}' \
  > ./reference-spec.json

# 3. Author ./workbook-spec.json — {"name","folderId","contents":{…}}.
#    Formula rules, layout XML, and sources: see the sigma-workbooks skill.

# 4. Validate without saving, then create
sigma api workbooks create --params '{}' \
  --json "$(jq -c '. + {dryRun: true}' ./workbook-spec.json)"

sigma api workbooks create --params '{}' \
  --json "$(cat ./workbook-spec.json)" \
  > ./create-response.json

WORKBOOK_ID=$(jq -r '.workbookId' ./create-response.json)
```

A dry run that passes returns `"dryRun": true` and a null `workbookId`. A
failing one exits 1 and prints the server's validation errors.

> **IDs you submit survive create.** Pages, elements, and
> columns keep the `id` values you sent, and the `layout` XML's
> `elementId` attributes stay valid against them — so the file you
> POSTed remains an accurate base for a later contents update.

### No reference workbook on the org?

Manufacture one rather than hand-authoring blind.

**Materialize a template.** `templates list` and `shared-templates
shared-with-you list` are separate surfaces from `workbooks list`;
either can yield a workbook to study.

```sh
sigma api templates list

sigma api templates save-workbook --params '{}' \
  --json '{"templateId":"<YOUR_TEMPLATE_ID>","folderId":"<YOUR_FOLDER_ID>"}'
# then read the workbook it created with "includeContents":true
```

**Or seed one and read it back.** Author the smallest spec the API
accepts — a `name`, a `folderId`, and `contents` holding a `schemaVersion`
and one `table` element over any table you can discover
([`connections-and-sources.md`](connections-and-sources.md)) — then
create it and pull the readback. What comes back is a reference spec
written by the server in its current idiom, which is what step 2 was
after.

```sh
# dryRun runs the same validation as create without persisting
# anything, so iterating on the seed costs nothing.
sigma api workbooks create --params '{}' \
  --json "$(jq -c '. + {dryRun: true}' ./seed.json)"

sigma api workbooks create --params '{}' \
  --json "$(cat ./seed.json)" > ./create-response.json

sigma api workbooks get \
  --params "$(jq -c '{workbookId, includeContents: true}' ./create-response.json)" \
  > ./reference-spec.json
```

Put **two** elements on one page if you want a `layout` XML sample to
study — a single-element page can be arranged automatically, so a
one-element seed gives you less to work from. Keep the seed as the org's
reference workbook, or remove it with `files delete`
([`files-and-folders.md`](files-and-folders.md)).

## Workflow — iterate on an existing workbook's spec

```sh
sigma api workbooks get \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>","includeContents":true}' \
  > ./current-spec.json

# Edit .contents in ./current-spec.json, then build the PUT body:
# just `contents`, plus `documentVersion` so the update fails if someone
# else saved the workbook since you read it.
jq '{documentVersion, contents}' ./current-spec.json > ./put-body.json
```

Send the update with `PUT /v2/workbooks/{workbookId}/contents`. If
`sigma api workbooks --help` doesn't list a command for it, call it with
`curl`, reusing the CLI's token. `SIGMA_BASE_URL` is your API host, which
`sigma auth status` prints for the active profile; the `sigma-api` skill lists
the hosts.

```sh
curl -sS -X PUT \
  -H "Authorization: Bearer $(sigma auth token)" \
  -H "Content-Type: application/json" \
  --data @./put-body.json \
  "$SIGMA_BASE_URL/v2/workbooks/<YOUR_WORKBOOK_ID>/contents"
```

The contents update is full-replacement, not patch. A stale
`documentVersion` returns HTTP 400 telling you the document changed since
you read it: read again, reapply the edit, and retry. Sending `name` or
`folderId` in this body doesn't rename or move the workbook.

**If the read warns that some content could not be represented, tell the
user that some content is affected before any contents update to this same workbook —
the update writes back only what the read returned, so that content is lost —
and get their explicit confirmation first when the warning covers a large
amount of content.**

## Workflow — find the SQL behind a chart

```sh
# 1. Find the element by name
sigma api workbooks elements list --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  | jq '.entries[] | {elementId, name, type}'

# 2. Pull its rendered SQL
sigma api workbooks elements query get \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>","elementId":"<YOUR_ELEMENT_ID>"}'
```

## Workflow — trace lineage

```sh
sigma api workbooks lineage list --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}'
```

Per-element breakdown is under `workbooks lineage elements`. Useful
before a source swap or after a warehouse migration to confirm which
workbooks are affected.

## Tagging and reverse-lookup

`workbooks tag` attaches a tag; `tags workbooks list` answers "which
workbooks carry this tag." Read both bodies per `SKILL.md` *Discovery loop* step 3.

## Cross-references

- Granting access on a workbook, embeds, cross-org sharing →
  [`permissions-and-sharing.md`](permissions-and-sharing.md).
- Scheduled exports of a workbook →
  [`delivery-and-schedules.md`](delivery-and-schedules.md).
- Materializations on workbook elements →
  [`materializations.md`](materializations.md).
- Swapping a workbook's data sources →
  [`connections-and-sources.md`](connections-and-sources.md).
