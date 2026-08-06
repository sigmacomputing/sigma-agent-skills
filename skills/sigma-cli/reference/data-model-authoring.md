# Data Model Authoring

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Build, inspect, and update Sigma data models — the semantic-layer assets
workbooks read from. Load this when the user is authoring a data model
from a spec, maintaining one, or migrating off a legacy dataset.

> Datasets are deprecated; new code targets data models. Datasets appear
> only in the migration workflow below.

Everything here lives under `sigma api data-models …` (plus `datasets`
for migration). Run `sigma api data-models --help` for its current
sub-groups.

## Workflow — author a data model from a spec file

```sh
# 1. Find a reference model by name
sigma api data-models list \
  | jq -r '.entries[] | select(.name == "<REFERENCE_MODEL_NAME>") | .dataModelId'

# 2. Study its spec
sigma api data-models spec get --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}' \
  > ./reference-model.json

# 3. Author ./data-model.json — sources, joins, columns, semantics.
#    Read the body shape, don't guess it — see SKILL.md *Discovery loop* step 3.

# 4. Create
sigma api data-models spec create \
  --params '{}' \
  --json "$(cat ./data-model.json)" \
  > ./create-response.json

DM_ID=$(jq -r '.dataModelId' ./create-response.json)
```

## Workflow — update a data model

```sh
sigma api data-models spec get --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}' \
  > ./current-model.json

# Edit, then:
sigma api data-models spec update \
  --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}' \
  --json "$(cat ./current-model.json)"
```

`spec update` is full-replacement, not patch.

## Workflow — migrate a legacy dataset

```sh
# 1. Identify
sigma api datasets list

# 2. Migrate — confirm parameters with `sigma api schema datasets migrate`;
#    read any body shape per SKILL.md *Discovery loop* step 3.
sigma api datasets migrate --params '{"datasetId":"<YOUR_DATASET_ID>"}'

# 3. Verify the result is now a data model
sigma api data-models list --params '{"limit":50}' \
  | jq '.entries[] | select(.name == "<original-dataset-name>")'
```

The migration repoints downstream workbooks; verify with `lineage` (next
workflow) **before** deleting the legacy dataset.

## Workflow — trace what a data model is built from / who consumes it

```sh
sigma api data-models lineage list --params '{"dataModelId":"<YOUR_DATA_MODEL_ID>"}'
```

Element- and source-level breakdowns live under `data-models elements`
and `data-models sources`. Combine with workbook lineage
([`workbook-authoring.md`](workbook-authoring.md)) to answer "which
workbooks read from this data model."

## Cross-references

- Granting access — data-model access derives from the underlying
  connection's grants
  ([`connections-and-sources.md`](connections-and-sources.md)), plus any
  grants carried over from a migrated dataset
  ([`permissions-and-sharing.md`](permissions-and-sharing.md)). Check
  `sigma api data-models --help` for a direct grants path before
  assuming there isn't one.
- Materializations →
  [`materializations.md`](materializations.md).
- Swapping a data model's sources →
  [`connections-and-sources.md`](connections-and-sources.md).
