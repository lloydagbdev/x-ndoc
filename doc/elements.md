## Semantic IR Surface

This document defines the minimal semantic surface for the project's IR.
It is format-neutral and only includes what is needed as a source of truth.
Known document formats are referenced only as mapping aids, not as the model itself.

---

### Core nodes

| Element | Purpose | Known format references |
| --- | --- | --- |
| **Document** | The top-level semantic container for a single authored source. Holds the whole tree plus document-scoped metadata and resolution state. | AsciiDoc document, Markdown document, HTML document, DocBook article/book |
| **Section** | A hierarchical region introduced by a heading-like boundary. Used to preserve outline structure and nesting. | AsciiDoc section, Markdown heading section, HTML `section`, DocBook `section` |
| **Paragraph** | A block of flowing prose content. This is the default container for normal narrative text. | AsciiDoc paragraph, Markdown paragraph, HTML `p`, DocBook `para` |
| **List** | A grouped sequence of related items with an explicit ordering or semantic list type. | Markdown list, HTML `ul`/`ol`/`dl`, DocBook list types |
| **List item** | One semantic unit inside a list. May contain paragraphs, nested lists, or other blocks depending on list type. | Markdown list item, HTML `li`, DocBook `listitem` |
| **Table** | A grid of related rows and cells used for structured comparison or catalog data. | Markdown table, HTML `table`, DocBook `table` |
| **Table row** | One horizontal row of table cells. | HTML `tr`, DocBook row, spreadsheet row concept |
| **Table cell** | One cell within a row. May carry inline content or richer nested blocks depending on policy. | HTML `td`/`th`, DocBook `entry` |
| **Block** | Generic block container used when meaning is known but the exact subtype is not yet required. | HTML `div`, DocBook wrapper patterns, generic AST block |
| **Inline** | Generic inline container used when meaning is known but the exact subtype is not yet required. | HTML `span`, generic AST inline |

---

### Inline meaning

| Element | Purpose | Known format references |
| --- | --- | --- |
| **Text** | Literal textual content with no additional semantic decoration. | Plain text in all formats |
| **Link** | A navigable pointer to a URL, file, or internal target. May be resolved or unresolved. | Markdown link, HTML `a`, AsciiDoc link macro |
| **Reference** | A pointer to another document entity such as a section, figure, table, or anchor. | Cross-reference in AsciiDoc, internal link in HTML, reference semantics in DocBook/DITA |
| **Anchor** | A named target that other nodes can resolve against. | HTML `id`, AsciiDoc anchor, DocBook `xml:id` |
| **Emphasis** | Inline emphasis that changes meaning or rhetorical weight without changing the underlying text. | Markdown `_em_`, HTML `em`, DocBook emphasis |
| **Strong** | Strong emphasis used for importance, warning, or salience. | Markdown `**strong**`, HTML `strong`, DocBook `emphasis role="strong"` |

---

### Metadata and resolution

| Element | Purpose | Known format references |
| --- | --- | --- |
| **Metadata** | Identity and descriptive data attached to a node, typically including identifiers, labels, and bookkeeping fields. | AsciiDoc attributes/roles, HTML metadata patterns, DocBook attributes |
| **Attributes** | Key-value data carried with nodes or document scope. Used for document-wide state, block options, or resolution inputs. | AsciiDoc attributes, HTML attributes, DocBook attributes |
| **Role** | A semantic classifier or secondary label used to group meaning without inventing a new node type. | HTML class, AsciiDoc role, DocBook role |
| **Title** | Human-facing label attached to a node, usually displayed as the primary caption or heading text. | HTML heading/title text, AsciiDoc block title, DocBook title |
| **Diagnostic** | A parser or resolver message describing warnings, errors, or informational conditions. Not part of the authored content itself. | Compiler diagnostic, linter message, parser warning |

---

### Minimal semantic scope

This stage should model only the meaning required to preserve and resolve documentation correctly.

Prefer generic nodes when:

| Case | Preferred shape |
| --- | --- |
| The exact subtype does not change resolution or identity | `Block` or `Inline` |
| The data is purely descriptive | `Metadata`, `Attributes`, or `Title` |
| The data only affects later expansion or rendering | keep it out of core semantics for now |
| A format-specific feature has no cross-format meaning yet | defer it |

---

### Deferred until needed

The following are not part of the core semantic surface yet and should be added only when the IR requires them:

| Element | Reason | Known format references |
| --- | --- | --- |
| **Admonition** | Can be represented later as a specialized block subtype when warning/tip semantics matter to the core model. | AsciiDoc admonition, Markdown blockquote-admonition conventions, DITA note/caution/warning |
| **Quote** | Useful when quoted text needs provenance or attribution, but not required for the minimal tree. | HTML `blockquote`, Markdown blockquote, DocBook `blockquote` |
| **Code / Literal** | Add when code, fixed-width text, or executable examples need distinct treatment. | Markdown code fence, HTML `code`/`pre`, DocBook `programlisting` |
| **Image / Media** | Add when embedded media becomes a source-of-truth concern instead of a render concern. | Markdown image, HTML `img`, DocBook `mediaobject` |
| **Footnote** | Add when citations or note placement need explicit semantic round-tripping. | AsciiDoc footnote, Markdown footnote extensions, HTML footnote patterns |
| **Include / Conditional** | Better treated as resolution mechanics because they affect document assembly rather than authored meaning. | AsciiDoc include, preprocessor directives, DITA conref/conkeyref |
| **Passthrough** | Backend-specific or escape-hatch behavior, not core semantics. | HTML raw passthrough, AsciiDoc passthrough, template escape hatches |

---

### Hierarchy examples

#### Example 1: Basic document hierarchy

```text
Document
└── Section: Introduction
    ├── Paragraph
    │   ├── Text
    │   └── Link
    └── Section: Background
        └── Paragraph
            ├── Text
            └── Reference
```

Meaning: a document contains sections, and sections contain paragraphs plus nested sections.

---

#### Example 2: Section with metadata and emphasis

```text
Document
└── Section: Installation
    ├── Title
    ├── Metadata
    └── Paragraph
        ├── Text
        └── Strong
```

Meaning: semantic metadata is attached to the node, while inline meaning stays inside the paragraph.

---

#### Example 3: List with nested content

```text
Document
└── Section: Setup Steps
    └── List
        ├── List item
        │   └── Paragraph
        │       └── Text
        ├── List item
        │   ├── Paragraph
        │   │   └── Text
        │   └── List
        │       ├── List item
        │       └── List item
        └── List item
            └── Paragraph
                ├── Text
                └── Inline
```

Meaning: list items are containers, not flat strings.

---

#### Example 4: Table hierarchy

```text
Document
└── Section: API Summary
    └── Table
        ├── Table row
        │   ├── Table cell
        │   └── Table cell
        └── Table row
            ├── Table cell
            │   └── Paragraph
            └── Table cell
                └── List
```

Meaning: table cells may contain richer semantic content, not just text.

---

#### Example 5: Anchor and reference

```text
Document
├── Section: Overview
│   ├── Anchor
│   └── Paragraph
└── Section: Details
    └── Paragraph
        ├── Text
        └── Reference
```

Meaning: references point across the document tree and require resolvable targets such as anchors.

---

### Suggested Zig data structures

These are starter shapes for the IR, not a final API.
They keep the semantic core small and allow format-specific features to stay outside the core tree.

```zig
const std = @import("std");

pub const NodeId = u32;

pub const Document = struct {
    metadata: Metadata,
    blocks: []Node,
};

pub const Node = union(enum) {
    section: Section,
    paragraph: Paragraph,
    list: List,
    table: Table,
    block: Block,
    inline: Inline,
    diagnostic: Diagnostic,
};

pub const Section = struct {
    metadata: Metadata,
    title: ?[]const u8,
    children: []Node,
};

pub const Paragraph = struct {
    content: []Inline,
};

pub const List = struct {
    kind: ListKind,
    items: []ListItem,
};

pub const ListKind = enum {
    ordered,
    unordered,
    task,
    description,
};

pub const ListItem = struct {
    children: []Node,
};

pub const Table = struct {
    rows: []TableRow,
};

pub const TableRow = struct {
    cells: []TableCell,
};

pub const TableCell = struct {
    children: []Node,
};

pub const Block = struct {
    metadata: Metadata,
    children: []Node,
};

pub const Inline = union(enum) {
    text: []const u8,
    link: Link,
    reference: Reference,
    anchor: Anchor,
    emphasis: []Inline,
    strong: []Inline,
};

pub const Link = struct {
    target: []const u8,
    label: ?[]const u8 = null,
};

pub const Reference = struct {
    target: []const u8,
    label: ?[]const u8 = null,
};

pub const Anchor = struct {
    name: []const u8,
};

pub const Metadata = struct {
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    attrs: std.StringHashMapUnmanaged([]const u8) = .{},
};

pub const Diagnostic = struct {
    message: []const u8,
};
```

Notes:

| Choice | Why it fits |
| --- | --- |
| `union(enum)` for `Node` and `Inline` | Keeps shape explicit while staying easy to extend. |
| `[]Node` / `[]Inline` children | Lets blocks and paragraphs own ordered content naturally. |
| `Metadata` as a reusable struct | Keeps identity, labels, roles, and attributes consistent across nodes. |
| `StringHashMapUnmanaged` for attributes | Practical for a small, flexible key-value surface. Requires an external allocator for `put`, `remove`, and `deinit` operations; construction helpers should manage this. |
| `ListKind` as an enum | Covers the current list semantics without committing to format-specific subtypes. |

---

### Suggested DoD-oriented Zig structures

This variant favors flat storage, dense traversal, and index-based relationships.
It is better suited for bulk transforms, resolution passes, and cache-friendly iteration.

```zig
const std = @import("std");

pub const NodeIndex = u32;
pub const InlineIndex = u32;

pub const DocumentArena = struct {
    metadata: Metadata,
    nodes: []NodeEntry,
    inlines: []InlineEntry,
    sections: []SectionData,
    paragraphs: []ParagraphData,
    lists: []ListData,
    list_items: []ListItemData,
    tables: []TableData,
    rows: []TableRowData,
    cells: []TableCellData,
    blocks: []BlockData,
    texts: []TextData,
    links: []LinkData,
    references: []ReferenceData,
    anchors: []AnchorData,
    emphases: []EmphasisData,
    strongs: []StrongData,
    diagnostics: []Diagnostic,
};

pub const NodeTag = enum {
    section,
    paragraph,
    list,
    list_item,
    table,
    table_row,
    table_cell,
    block,
};

pub const NodeEntry = struct {
    tag: NodeTag,
    index: u32,
};

pub const InlineTag = enum {
    text,
    link,
    reference,
    anchor,
    emphasis,
    strong,
};

pub const InlineEntry = struct {
    tag: InlineTag,
    index: u32,
};

pub const SectionData = struct {
    metadata: Metadata,
    title: ?[]const u8,
    first_child: ?NodeIndex,
    child_count: u32,
};

pub const ParagraphData = struct {
    first_inline: ?InlineIndex,
    inline_count: u32,
};

pub const ListKind = enum {
    ordered,
    unordered,
    task,
    description,
};

pub const ListData = struct {
    kind: ListKind,
    first_item: ?NodeIndex,
    item_count: u32,
};

pub const ListItemData = struct {
    first_child: ?NodeIndex,
    child_count: u32,
};

pub const TableData = struct {
    first_row: ?NodeIndex,
    row_count: u32,
};

pub const TableRowData = struct {
    first_cell: ?NodeIndex,
    cell_count: u32,
};

pub const TableCellData = struct {
    first_child: ?NodeIndex,
    child_count: u32,
};

pub const BlockData = struct {
    metadata: Metadata,
    first_child: ?NodeIndex,
    child_count: u32,
};

pub const TextData = struct {
    value: []const u8,
};

pub const LinkData = struct {
    target: []const u8,
    label: ?InlineIndex,
};

pub const ReferenceData = struct {
    target: []const u8,
    label: ?InlineIndex,
};

pub const AnchorData = struct {
    name: []const u8,
};

pub const EmphasisData = struct {
    first_inline: ?InlineIndex,
    inline_count: u32,
};

pub const StrongData = struct {
    first_inline: ?InlineIndex,
    inline_count: u32,
};
```

Notes:

| Choice | Why it fits |
| --- | --- |
| Flat tables of typed payloads | Good for sequential scanning and pass-based transforms. |
| `tag` + `index` entries | Keeps a compact top-level node stream while payload lives in typed arrays. |
| `first_*` + `*_count` spans | Represents ordered children without nested ownership. |
| Index-based inline references | Avoids deep recursive structures in hot paths. |
| Inline payload arrays in `DocumentArena` | Mirrors the node pattern: `InlineEntry` tags index into typed arrays (`texts`, `links`, `references`, `anchors`, `emphases`, `strongs`). |
| Diagnostics stored separately | Diagnostics are not part of the node stream; they live in a flat `diagnostics` array outside the `NodeTag` enum. |
| Separate `DocumentArena` | Gives a single container for parsing, resolution, and render preparation. |

---

### Proposed operational layer

These are supporting capabilities that operate on the IR without being part of the core semantic tree.
They help validate, normalize, compare, and safely construct documents.

| Operation | Purpose | Notes |
| --- | --- | --- |
| **Validation** | Check structural correctness, required fields, and invariants. | Examples: section ordering, table row consistency, unresolved references. |
| **Verification** | Confirm the IR matches an expected meaning or canonical form. | Useful for round-trip checks and regression tests. |
| **Semantic hashing** | Produce stable hashes from meaning-bearing fields. | Ignore render-only or incidental data; useful for cache keys and equivalence checks. |
| **Normalization** | Convert equivalent forms into a canonical representation. | Example: merge adjacent text nodes, sort stable metadata fields, normalize list kinds. |
| **Privacy helpers** | Detect or redact sensitive content before export, logging, or diagnostics. | Example: redact secrets in text, metadata, or attributes. |
| **Construction helpers** | Provide safe builders for nodes, metadata, and relationships. | Prevent malformed trees and reduce repetitive allocation/setup code. |
| **Resolution helpers** | Connect references, anchors, includes, and derived identities. | This is operational even when the resulting relation is semantic. |
| **Traversal helpers** | Offer stable iteration, search, and query utilities over the IR. | Useful for analysis, linting, and render prep. |
| **Diff helpers** | Compare two IR instances at semantic or structural levels. | Helpful for testing and document sync workflows. |

Possible supporting APIs:

| API shape | Use |
| --- | --- |
| `validate(document)` | Return diagnostics for malformed or incomplete structure. |
| `hashSemantic(document)` | Produce a semantic digest for equivalence checks. |
| `normalize(document)` | Return a canonicalized copy or in-place normalized form. |
| `redact(document, policy)` | Produce a privacy-safe view of the IR. |
| `buildSection(...)` / `buildParagraph(...)` | Simplify construction and enforce invariants. |

### Guiding rule

Prefer the smallest node set that preserves meaning.
If a concept can be modeled as metadata or a generic block/inline, keep it generic until a concrete use case requires specialization.

When a format comparison helps, use it only to justify mapping, not to expand the IR by default.
