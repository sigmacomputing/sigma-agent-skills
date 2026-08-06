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

## Workflow — build a workbook from a spec file

Always study a reference spec first — the spec body shape evolves and
real workbooks are the best documentation. If the org has none to
study, make one — see *No reference workbook on the org?* below.

```sh
# 1. Find a workbook to use as a reference, by name
sigma api workbooks list \
  | jq -r '.entries[] | select(.name == "<REFERENCE_WORKBOOK_NAME>") | .workbookId'

# 2. Pull its spec to study structure
sigma api workbooks spec get --params '{"workbookId":"<YOUR_TEMPLATE_ID>"}' \
  > ./reference-spec.json

# 3. Author ./workbook-spec.json — formula rules, layout XML, sources.

# 4. Create
sigma api workbooks spec create \
  --params '{}' \
  --json "$(cat ./workbook-spec.json)" \
  > ./create-response.json

WORKBOOK_ID=$(jq -r '.workbookId' ./create-response.json)
```

> **IDs you submit survive `spec create`.** Pages, elements, and
> columns keep the `id` values you sent, and the `layout` XML's
> `elementId` attributes stay valid against them — so the file you
> POSTed remains an accurate base for a later `spec update`.

### No reference workbook on the org?

Manufacture one rather than hand-authoring blind.

**Materialize a template.** `templates list` and `shared-templates
shared-with-you list` are separate surfaces from `workbooks list`;
either can yield a workbook to study.

```sh
sigma api templates list

sigma api templates save-workbook --params '{}' \
  --json '{"templateId":"<YOUR_TEMPLATE_ID>","folderId":"<YOUR_FOLDER_ID>"}'
# then spec get the workbook it created
```

**Or seed one and read it back.** Author the smallest spec the API
accepts — a `name`, a `folderId`, a `schemaVersion`, and one `table`
element over any table you can discover
([`connections-and-sources.md`](connections-and-sources.md)) — then
create it and pull the readback. What comes back is a reference spec
written by the server in its current idiom, which is what step 2 was
after.

```sh
# spec verify runs the same validation as create without persisting
# anything, so iterating on the seed costs nothing.
sigma api workbooks spec verify --params '{}' \
  --json "$(cat ./seed.json)"

sigma api workbooks spec create --params '{}' \
  --json "$(cat ./seed.json)" > ./create-response.json

sigma api workbooks spec get \
  --params "$(jq '{workbookId}' ./create-response.json)" \
  > ./reference-spec.json
```

Put **two** elements on one page if you want a `layout` XML sample to
study — a single-element page can be arranged automatically, so a
one-element seed gives you less to work from. Keep the seed as the org's
reference workbook, or remove it with `files delete`
([`files-and-folders.md`](files-and-folders.md)).

## Workflow — iterate on an existing workbook's spec

```sh
sigma api workbooks spec get --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  > ./current-spec.json

# Edit ./current-spec.json, then:
sigma api workbooks spec update \
  --params '{"workbookId":"<YOUR_WORKBOOK_ID>"}' \
  --json "$(cat ./current-spec.json)"
```

`spec update` is full-replacement, not patch.

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
