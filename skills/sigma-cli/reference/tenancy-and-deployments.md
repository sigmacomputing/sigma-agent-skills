# Tenancy and Deployments

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Multi-tenant orgs, deployment policies, templates and shared templates,
organization translations. Load this when the user is operating across
tenant boundaries — promoting a workbook from a dev tenant to prod,
accepting an inbound shared template, defining a deployment policy, or
localizing the UI.

Everything here lives under `tenants`, `deployment-policies`,
`templates`, `shared-templates`, `user-attributes tenants`, and
`translations organization`. Run `sigma api tenants --help` /
`sigma api deployment-policies --help` for the current shape, and treat
a shape error as the single most likely failure on this surface.

## Mental model

- **Tenants** are sub-organizations under one parent org. An admin
  manages many; analysts work inside one.
- **Deployment policies** describe how documents propagate across
  tenants — which assets go to which tenants, on what cadence.
- **Templates** are org-internal starter workbooks. **Shared templates**
  cross org boundaries (different from `workbooks share-cross-org`,
  which targets a *specific live workbook*).
- **Tenant attributes** parameterize per-tenant deployments (brand
  color, region, default warehouse).

## Workflow — promote a workbook from dev tenant to prod tenant

Both `files` and `tenants` take **plural id arrays**, so a whole batch goes in
one call. Note the naming: it's `inodeIds` (file-tree ids, per
[`files-and-folders.md`](files-and-folders.md)) and `tenantOrganizationId`,
not `fileId`/`tenantId`.

```sh
# 1. Create the policy — only `name` is required
sigma api deployment-policies create --params '{}' --json '{"name":"dev → prod"}'
# → policyId

# 2. Add the workbook(s) that the policy governs
sigma api deployment-policies files create \
  --params '{"deploymentPolicyId":"<YOUR_POLICY_ID>"}' \
  --json   '{"inodeIds":["<YOUR_WORKBOOK_INODE_ID>"]}'

# 3. Add the target tenant(s)
sigma api deployment-policies tenants create \
  --params '{"deploymentPolicyId":"<YOUR_POLICY_ID>"}' \
  --json   '{"tenantOrganizationId":"<YOUR_PROD_TENANT_ID>"}'

# 4. Verify the deployed copies on the prod tenant. This lists what the
#    tenant received; narrow it with the optional `parentWorkbookId` query
#    parameter to find the copy of one specific source workbook.
sigma api tenants workbooks get \
  --params '{"tenantOrganizationId":"<YOUR_PROD_TENANT_ID>",
             "parentWorkbookId":"<YOUR_SOURCE_WORKBOOK_ID>"}'
```

The optional half of the policy body carries `versionTagId`, `nameInTenant`,
`copyInputTableData`, and `sourceSwapPolicies` — the last being how one
staging→prod connection mapping is reused across everything the policy
promotes ([`connections-and-sources.md`](connections-and-sources.md)). Read the
current shape per `SKILL.md` *Discovery loop* step 3.

## Workflow — bootstrap a new tenant

```sh
# 1. Create — name and slug are both required
sigma api tenants create --params '{}' \
  --json '{"tenantOrganizationName":"Acme","tenantOrganizationSlug":"acme"}'
# → tenantOrganizationId

# 2. Inspect deployable surface. `deployments` is a sub-group, not an
#    operation — it carries `list`, `batch-add`, and `batch-remove`.
sigma api tenants capabilities deployments list \
  --params '{"tenantOrganizationId":"<YOUR_TENANT_ID>"}'

# 3. Set tenant-level attribute defaults (brand, region, etc.). Same
#    `assignments` batch envelope as the per-user form in
#    identity-and-access.md — the tenant is named in the body, not --params.
sigma api user-attributes tenants create \
  --params '{"userAttributeId":"<YOUR_ATTRIBUTE_ID>"}' \
  --json   '{"assignments":[
    {"tenantOrganizationId":"<YOUR_TENANT_ID>",
     "value":{"val":"acme-default","type":"string"}}
  ]}'
```

**The tenant id is `tenantOrganizationId` everywhere in this group**, never
`tenantId`. Passing `tenantId` is the undeclared-parameter trap: it's forwarded
as a query parameter and the required path parameter is reported missing.

## Workflow — accept a workbook template shared from another org

```sh
# 1. See what was offered
sigma api shared-templates shared-with-you list

# 2. Accept (creates a local template usable by templates save-workbook).
#    Neither of these two operations declares any parameter — every id
#    travels in the body.
sigma api shared-templates accept --params '{}' \
  --json '{"shareId":"<YOUR_SHARE_ID>"}'

# 3. Materialize a real workbook from the now-local template.
#    `templateId` and `folderId` are both required; `name` is optional.
sigma api templates save-workbook --params '{}' \
  --json '{"templateId":"<YOUR_TEMPLATE_ID>","folderId":"<YOUR_FOLDER_ID>",
           "name":"My Acme Dashboard"}'
```

`accept` also takes an optional `sourceSwaps` map, for repointing the incoming
template's tables at your own warehouse as part of accepting it.

> `shared-templates` covers *cross-org templates*. To share a specific
> live workbook to another org instead, use `api workbooks
> share-cross-org` ([`permissions-and-sharing.md`](permissions-and-sharing.md)).

## Workflow — add a localized variant for the org

The locale field is `lng`, and on `create` it lives in the **body** — the
operation declares no parameters. `translations` itself is a flat
phrase → translation map.

```sh
sigma api translations organization create --params '{}' \
  --json '{"lng":"fr-FR","translations":{"Save":"Enregistrer"}}'
```

`update` and `delete` invert this: they take `lng` **and** `lng_variant` as
required *path* parameters, so a variant name is mandatory there even though
it's optional on create. Confirm with
`sigma api schema translations organization update`.

## Cross-references

- The workbook being promoted — author / inspect via
  [`workbook-authoring.md`](workbook-authoring.md).
- Per-user / per-team attributes (the underlying mechanism behind
  per-tenant attributes) →
  [`identity-and-access.md`](identity-and-access.md).
- Granting access on a deployed workbook inside the target tenant →
  [`permissions-and-sharing.md`](permissions-and-sharing.md).
- Templates' source-swap semantics →
  [`connections-and-sources.md`](connections-and-sources.md).
