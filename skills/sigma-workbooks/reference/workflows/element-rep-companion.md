# How an Agent Builds & Edits a Workbook through the Filesystem

*The workbook rep: element-level editing over Sigma's whole-spec API — with no middleware,
and a feedback loop where the agent **sees** what it built.*

---

## The idea

Sigma's spec API moves whole workbooks: `GET` and `PUT` carry the entire document. On a
multi-page workbook that means every small edit drags tens of thousands of tokens through an
agent's context, and two agents can't safely work on the same workbook at once.

The **rep** fixes this without introducing any new interface: the spec is *exploded into a
directory of small files* — one file per element — and reassembled on push. The agent edits
workbooks with the tools it is already best at: `Read`, `Edit`, `Glob`, `grep`. The element-level
abstraction lives in the file layout, not in a process.

```
<rep>/
  workbook.yaml              top-level fields (name, folderId, schemaVersion)
  pages/
    010-overview/            numeric prefix = page order (×10, insert between)
      _page.yaml             page identity & visibility
      _layout.xml            this page's <Page> block of the layout XML
      010-revenue-kpi.yaml   one element per file — ~600 bytes each
      020-sales-by-region.yaml
  renders/                   PNGs the agent looks at (see "The render loop")
  .sigma/                    plumbing: snapshot, manifest — never hand-edited
```

Nothing is a new format. Every file is a verbatim slice of the spec, so all existing spec
documentation applies unchanged to a single element file. A 20-element workbook becomes twenty
~600-byte files instead of one 20KB document; an edit touches exactly one of them.

The rep's on-disk files intentionally stay in the pre-2026-08 flat shape
(`schemaVersion`/`pages`/`layout` as plain top-level keys) even though the live
API wire body nests those same fields under a `contents` key (see
`sigma-workbooks`'s `reference/specification/schema.md`). The rep
tooling wraps/unwraps at the GET/POST/PUT boundary so this is invisible from the
file tree.

## The loop

```
pull ──▶ edit files ──▶ status ──▶ push ──▶ verify ──▶ render ──▶ look ──▶ edit …
```

**`pull <workbook-id> <dir>`** — GET the spec, explode it, store a pristine snapshot.
Reassembly is byte-exact: an untouched rep pushes back as a no-op.

**Edit** — plain file operations. Add an element = add a file (+ one line of layout XML).
Delete = delete the file. Reorder = rename the numeric prefix.

**`status`** — offline, element-level diff against the snapshot:

```
  page "Pulse":
  ~ element "Clones per day" (line-clones) [columns, yAxis, color]
  + element "Star events per month" (bar-star-months)
```

**`push`** — reassemble and write, through four gates:
1. **Drift check** — if the server spec changed since pull (someone edited in the UI), push
   aborts and shows exactly what would be overwritten. No silent clobbering, ever.
2. **Diff preview** — prints the element-level change set it is about to apply.
3. **Validation** — static formula/shape checks before any network write.
4. **Readback** — re-GETs after the PUT, refreshes the snapshot, and reports anything the
   server normalized.

The API itself still receives a full-spec PUT — the rep gives element-level semantics *on top of*
the existing endpoint, today, with no server changes.

**`verify`** — compile check: Sigma accepts specs whose formulas don't resolve and only fails
them at query time, so every element's compiled SQL is checked for embedded error literals.

## The render loop — the agent looks at its work

A spec that POSTs cleanly and compiles cleanly can still be wrong. **`render`** exports any page
or element as a PNG, and the agent *reads the image* and critiques it against the plan before
calling the work done.

```
render <dir> [--page Pulse | --element <id>]   →   renders/pulse.png
```

This loop has caught, in practice, every class of failure the other gates can't:

- a CSS gradient the API **accepted and silently dropped** — element rendered with no background
- a formula error inside `{{…}}` text templating — invisible to both POST and SQL compile,
  rendered as `Invalid Query: …` in the banner
- a chart whose data was technically correct and visually useless (one 153-unit bar crushing
  a column of zeros)
- KPI panels clipping against a gradient band at real viewport widths

Acceptance criterion: *the pixels look right* — not *the API returned 200*.

## Zoom reads — context only on demand

For orientation and authoring, two read-only commands keep context spend near zero:

```
summarize <id|dir>      pages, element kinds, sources — one screen, no spec loaded
capabilities                            every authorable element kind
capabilities --kind bar-chart           the fields that kind supports
capabilities --kind bar-chart --field color     the exact schema for one field
```

`capabilities` distils Sigma's public OpenAPI live, so it always tracks the current API. The
read side is a zoom: summarize → list a page directory → read one element file → query one
field's schema. At no point does the whole spec enter context.

## Beyond the schema: the verified-behavior catalog

The OpenAPI says what shapes parse; it can't say what the platform actually does. The rep's
companion reference (the `sigma-workbooks` skill) keeps a catalog where every entry is
**live-verified against the API** and marked ✓/✗ with the exact error and the workaround —
e.g. which typography classes stand alone vs. require an alignment, that alpha-hex
`#rrggbbaa` renders although only `#rrggbb` is documented, and which idioms are UI-only.
When a render exposes a new behavior, it lands in the catalog the same day, and every future
build inherits it.

## What the structure buys

- **Parallel builds.** Element files are independent, so a plan can fan out one sub-agent per
  element with zero merge conflicts — the orchestrator owns only the plan, the id namespace,
  and the layout; a single push lands everything atomically.
- **Create mode.** A rep authored from scratch (or exploded from any spec via `import`) POSTs a
  new workbook — same files, same gates. Plan-as-file-tree: the directory *is* the design doc.
- **Git-native.** A rep directory commits cleanly: PRs show `changed: revenue-kpi.yaml`, not a
  2,000-line spec diff. The snapshot is the merge base; workbooks-as-code falls out for free.
- **No installation, no server.** One dependency-free script (`wb-rep.rb`, Ruby stdlib) plus the
  agent's own file tools.

## Where it lives

`twells89/sigma-skills` → `sigma-workbooks/` — `scripts/wb-rep.rb`,
`reference/workflows/element-rep.md` (workflow), `reference/specification/styling.md`
(verified-behavior catalog). Built and proven on live workbooks: byte-exact round-trips,
from-scratch multi-page creates, and design iterations driven entirely by the render loop.
