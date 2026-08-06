# Files and Folders

Illustrative, not exhaustive — the live spec wins, and an unrecognized value is
an addition, not an error (`SKILL.md` *Sources of truth*).

Browse the document tree — find things by folder or path, move and rename
them, and answer "what lives in here." Load this when the user talks about
folders, workspaces-as-locations, "my documents", the file tree, or wants a
list scoped to a location rather than to a resource type.

Everything here lives under `sigma api files …` (`list`, `get`, `create`,
`update`, `delete`). Run `sigma api files --help` for the current set.

## Folder scoping lives here

**"The workbooks in this folder" is a `files list` call, not a `workbooks
list` call.** Location filtering lives on the file tree; the resource-type
lists filter on properties of the resource. Before assuming a resource
group can scope by folder, check `sigma api schema <group> list` for a
location parameter.

```sh
sigma api files list \
  --params '{"parentId":"<YOUR_FOLDER_ID>","typeFilters":"workbook","directChildFilter":true,"limit":500}'
```

This matters more than a missing feature usually would, because passing
`parentId` to `workbooks list` **does not error**. Undeclared keys are
forwarded as query parameters (`SKILL.md` *Calling convention*), so you get the whole
accessible set at exit 0, looking scoped without being scoped. Read the
current selectors from `sigma api schema files list` before trusting a
filtered count.

**`parentId` alone is recursive.** It returns everything beneath the folder,
including nested subfolders' contents. `directChildFilter: true` is what makes
"in this folder" strict. Report which one you used — the two counts differ, and
silently picking the recursive one over-reports.

## `parentId` is authoritative; `path` is not

Entries carry both a `parentId` and a display `path`. Verifying scope by
string-matching `path` is wrong: `path` is not unique. Every member has a
folder displaying as `My Documents`, so one query can return many entries
sharing that `path` under different parents — including folders belonging to
*other* members that happen to be shared with your credential.

Two related traps:

- The all-zeros id `00000000-0000-0000-0000-000000000000` is a **real inode**
  (the org root), not a null or a sentinel. It's a poor negative control —
  filtering on it returns rows. Use a random UUID if you want an empty result.
- To find the current user's home folder, read it rather than guessing by name:
  `sigma api members get --params '{"memberId":"<YOUR_MEMBER_ID>"}'` returns
  `homeFolderId`.

## `files get` takes `inodeId`

```sh
sigma api files get --params '{"inodeId":"<YOUR_INODE_ID>"}'
```

Not `fileId` — that's a local validation error (exit 3), which is the
*friendly* failure. The unfriendly version: piping a failed call through `jq`
swallows the CLI's error and prints nulls, which reads as "empty result"
rather than "rejected request." When a `files` call returns unexpectedly
empty, re-run it without the `jq` pipe before believing the emptiness.

Entries returned by `list`/`get` identify the resource as `id` plus a `urlId`
and a `type` (`workbook`, `folder`, `dataset`, …), not as `workbookId`. Feed
`id` to the resource-specific groups.

Grants scoped to a connection *path* come back with an `inodeType` of `scope`,
and those ids have no reverse lookup exposed through `files get` today — see
[`permissions-and-sharing.md`](permissions-and-sharing.md).

## Listing the whole tree

`files list` is paginated with a cursor, and the entry count can be large.
Follow `nextPage`; don't increment an integer. See `SKILL.md` *Paginating list
results* for the loop and for why `total` and `hasMore` can't be relied on
uniformly.

Results are permission-scoped — `files list` returns what the active
credential can see. When you report a count as "everything in the org," say
that it's everything visible to this credential instead; the two differ, and
the difference is invisible in the response.

## Not here

- Grants on a file or folder → [`permissions-and-sharing.md`](permissions-and-sharing.md).
- Workbook contents (pages, elements, spec) → [`workbook-authoring.md`](workbook-authoring.md).
- Warehouse schema/table paths under a connection, which are a different
  "path" concept entirely → [`connections-and-sources.md`](connections-and-sources.md).
