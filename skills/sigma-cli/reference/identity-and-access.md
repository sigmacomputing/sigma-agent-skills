# Identity and Access

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Provisioning and lifecycle for the *principals* — members (users), teams,
user attributes, account types, and SAML SPs. Load this when the user is
acting as an org admin: onboarding, deprovisioning, team membership,
attribute assignment, role permissions, or SSO setup.

> Permissions on individual resources (workbook / workspace / connection
> grants, embeds, cross-org sharing) live in
> [`permissions-and-sharing.md`](permissions-and-sharing.md). This file is
> "who exists in the org"; that file is "what they can reach."

Everything here lives under `members`, `teams`, `user-attributes`,
`account-types`, `saml`. Run `sigma api <group> --help` for the full op
list; read body shapes per `SKILL.md` *Discovery loop* step 3.

## Workflow — onboard a new user with team + attribute

```sh
# 1. Create the member. Body shape varies with the org's account types;
#    read it from the spec first (SKILL.md *Discovery loop* step 3).
sigma api members create --params '{}' --json "$(cat ./member.json)"
# → response includes the new memberId

# 2. Find the team
sigma api teams list --params '{"limit":100}' \
  | jq '.entries[] | select(.name == "Analytics") | .teamId'

# 3. Add to the team (membership writes go through teams members update).
#    `add`/`remove` are arrays of bare id strings, not objects.
sigma api teams members update \
  --params '{"teamId":"<YOUR_TEAM_ID>"}' \
  --json   '{"add":["<YOUR_MEMBER_ID>"]}'

# 4. Set a per-user attribute (e.g. region). The member is named inside the
#    body, not in --params, and values are wrapped: {val, type}.
sigma api user-attributes users create \
  --params '{"userAttributeId":"<YOUR_ATTRIBUTE_ID>"}' \
  --json   '{"assignments":[
    {"userId":"<YOUR_MEMBER_ID>","value":{"val":"us-east","type":"string"}}
  ]}'
```

Step 4 is a batch endpoint — `assignments` takes many users per call, so
seed a whole cohort in one request rather than looping.

## Workflow — move a user between teams

`teams members update` takes a single body that can `add` and `remove` in
one call:

```sh
sigma api teams members update \
  --params '{"teamId":"<OLD_TEAM_ID>"}' \
  --json   '{"remove":["<YOUR_MEMBER_ID>"]}'

sigma api teams members update \
  --params '{"teamId":"<NEW_TEAM_ID>"}' \
  --json   '{"add":["<YOUR_MEMBER_ID>"]}'
```

To check current membership before moving, read it from the member's
side: `sigma api members teams list --params '{"memberId":"<YOUR_MEMBER_ID>"}'`.

## Workflow — deactivate a member, with handoff

Before deactivating, audit anything the user owns that will silently
break:

```sh
# Scheduled deliveries owned by the user (reassign or delete)
sigma api members schedules list --params '{"memberId":"<YOUR_MEMBER_ID>"}'

# Files (workbooks etc.) in their home folder — reassign owner if needed
sigma api members files list --params '{"memberId":"<YOUR_MEMBER_ID>"}'

# Then deactivate
sigma api members delete --params '{"memberId":"<YOUR_MEMBER_ID>"}'
```

Deactivation is reversible from the admin UI; programmatic re-activation
goes through `members update` (verify the body shape per `SKILL.md`
*Discovery loop* step 3).

## Workflow — audit what a team can do

A team's effective access is the union of:

- The **account type** assigned to its members (defines the action
  vocabulary — view, explore, build, admin):
  ```sh
  sigma api account-types permissions list --params '{"accountTypeId":"<YOUR_ACCOUNT_TYPE_ID>"}'
  ```
- The **attributes** bound to the team (control row-level filters and
  embed personalization):
  ```sh
  sigma api teams user-attributes list --params '{"teamId":"<YOUR_TEAM_ID>"}'
  ```
- Per-resource **grants** — switch to
  [`permissions-and-sharing.md`](permissions-and-sharing.md).

## Workflow — bulk-assign attribute values to a team

`teams assigned-user-attributes` is the team-side mirror of step 4 above —
same `assignments` envelope and same wrapped `{val, type}` value, keyed by
`userAttributeId` instead of `userId`:

```sh
sigma api teams assigned-user-attributes \
  --params '{"teamId":"<YOUR_TEAM_ID>"}' \
  --json   '{"assignments":[
    {"userAttributeId":"<YOUR_ATTRIBUTE_ID>","value":{"val":"us-east","type":"string"}}
  ]}'
```

## Workflow — configure SAML SSO for the org

`saml service-providers` covers SP CRUD; `saml service-providers
certificates` manages signing material. Run
`sigma api saml service-providers --help` for the current shape and pair
with the Sigma admin docs for IdP-side setup. Worth handing back to the
user for the IdP half of the integration.

## Cross-references

- Granting a team access to a workbook / workspace / connection →
  [`permissions-and-sharing.md`](permissions-and-sharing.md).
- Provisioning attribute *values* into multi-tenant deployments →
  [`tenancy-and-deployments.md`](tenancy-and-deployments.md) (covers
  `user-attributes tenants` in deployment context).
