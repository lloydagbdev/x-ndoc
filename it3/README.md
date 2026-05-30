## Iteration 3: Converge on the elements.md surface

### Purpose

it1 explored a flat node+edge graph with emitters and transform passes.
it2 explored a two-level IR (author-friendly + packed/flat) with comptime lowering.
it3 converges both explorations onto the semantic surface defined in `doc/elements.md`.

The goal is to prove that the elements.md core tree — with its block/inline separation, dedicated `Metadata`, and `DocumentArena` DoD layout — is practical to build, lower, validate, and traverse.

---

### Goals

#### 1. Implement the elements.md core tree

Build both IR levels as specified in `doc/elements.md`:

- **Author IR** — `union(enum)`-based tree with `Node` (section, paragraph, list, table, block, inline, diagnostic) and `Inline` (text, link, reference, anchor, emphasis, strong). `Metadata` as a reusable struct carrying id, title, roles, and attributes.
- **DoD IR** — `DocumentArena` with flat typed arrays (`sections`, `paragraphs`, `lists`, `list_items`, `tables`, `rows`, `cells`, `blocks`, `texts`, `links`, `references`, `anchors`, `emphases`, `strongs`, `diagnostics`), `NodeEntry`/`InlineEntry` tag+index pairs, and `first_*`/`*_count` spans.

Deferred elements (admonition, quote, code/literal, image/media, footnote, include/conditional, passthrough) remain excluded.

#### 2. Lowering pass: author → arena

A runtime pass that walks the author tree and populates a `DocumentArena`. This replaces it2's comptime lowering and validates that:

- Both representations express the same document.
- Arena indexing (spans, inline references) is practical to construct.
- String interning or buffer management is handled cleanly.

#### 3. Construction helpers

Safe builders for the author IR that enforce invariants at construction time:

- Paragraphs only contain inlines.
- Sections contain blocks (not raw inlines).
- List items contain blocks.
- Table cells contain blocks.
- Metadata is consistently initialized.

These helpers reveal whether the `Metadata`/`Attributes` model is ergonomic or needs adjustment.

#### 4. Validation pass

Structural correctness checks on the arena, producing `Diagnostic` entries:

- Child-type constraints (e.g., no inline where a block is expected).
- Required fields present (e.g., sections have titles or at least metadata).
- Reference/anchor consistency (every reference has a resolvable anchor target).
- Table row/cell count consistency.

Tests prove the error surface and diagnostic output.

#### 5. Traversal + minimal query

A walker/visitor over the arena that supports:

- Depth-first and breadth-first iteration.
- Collecting all anchors into a lookup table.
- Finding all unresolved references.
- Querying by node tag or metadata role.

This proves the `first_child`/`child_count` span model is navigable without recursive structures.

#### 6. Round-trip smoke test

Build a representative document using the construction helpers, lower it to the arena, validate, traverse, and emit at least one output format (HTML or debug text). The document should exercise:

- Nested sections
- Paragraphs with mixed inline content (text, emphasis, strong, links)
- Ordered and unordered lists with nesting
- A table with multi-cell rows
- Anchors and cross-references
- Metadata with roles and attributes

This proves the pipeline end-to-end and surfaces integration issues early.

---

### Deferred

These are explicitly out of scope for it3:

- **Semantic hashing, normalization, diff** — need a stable tree first.
- **Parsing real AsciiDoc or Markdown** — the IR shape isn't settled enough to commit to a parser.
- **Full emitter parity with it1** — one output format is sufficient to prove the pipeline.
- **Performance benchmarking** — the arena layout is designed for cache-friendliness, but measuring it is premature at this stage.

---

### File plan

```
it3/
├── README.md              ← this file
├── author_ir.zig          ← union(enum) author-facing IR + Metadata
├── arena_ir.zig           ← DocumentArena DoD IR
├── lower.zig              ← author → arena lowering pass
├── build_ir.zig           ← construction helpers / safe builders
├── validate.zig           ← structural validation → diagnostics
├── traverse.zig           ← walker, visitor, query helpers
├── emit_html.zig          ← minimal HTML emitter (smoke test)
├── hash.zig               ← semantic hashing with Blake3
└── main.zig               ← round-trip smoke test entry point
```

---

### Success criteria

it3 is done when:

1. A representative document can be built with construction helpers.
2. The author tree lowers to a valid `DocumentArena`.
3. Validation produces correct diagnostics for both valid and intentionally malformed documents.
4. Traversal can collect anchors and flag unresolved references.
5. At least one output format renders the lowered document correctly.
6. The elements.md surface is either validated as-is or updated with lessons learned.
