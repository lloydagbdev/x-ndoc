## Iteration 3: Converge on the elements.md Surface

### 1. Purpose

it1 explored a flat node+edge graph with emitters and transform passes.
it2 explored a two-level IR (author-friendly + packed/flat) with comptime lowering.
it3 converges both explorations onto the semantic surface defined in `doc/elements.md`.

The goal is to prove that the elements.md core tree — with its block/inline separation, dedicated `Metadata`, and `DocumentArena` DoD layout — is practical to build, lower, validate, traverse, and hash.

**Success criteria:**

1. A representative document can be built with construction helpers.
2. The author tree lowers to a valid `DocumentArena`.
3. Validation produces correct diagnostics for both valid and intentionally malformed documents.
4. Traversal can collect anchors and flag unresolved references.
5. At least one output format renders the lowered document correctly.
6. Semantic hashing produces stable, deterministic digests.
7. The elements.md surface is either validated as-is or updated with lessons learned.

---

### 2. Architecture Overview

Two-level IR with a unidirectional data flow:

```
build → author IR → lower → arena IR → validate / traverse / emit / hash
```

| Level | Representation | Purpose |
|---|---|---|
| **Author IR** | `union(enum)` tree with nested slices | Ergonomic construction, human-readable |
| **Arena IR** | Flat typed arrays with index spans | Cache-friendly traversal, bulk transforms |

The author IR owns its memory via recursive `free` methods. The arena IR owns all memory through a single `ArenaAllocator`. The lowering pass copies all data (including strings) into the arena, so the two representations are fully independent after lowering.

---

### 3. File Layout

| File | Lines | Purpose |
|---|---|---|
| `author_ir.zig` | 246 | union(enum) author-facing IR, Metadata, recursive deinit |
| `arena_ir.zig` | 152 | DocumentArena DoD IR, NodeTag, InlineTag, span helpers |
| `build_ir.zig` | 203 | Safe builder enforcing block/inline separation |
| `lower.zig` | 347 | Author → arena runtime lowering pass |
| `validate.zig` | 206 | Structural validation with anchor/reference checking |
| `traverse.zig` | 201 | Depth-first walker over arena spans |
| `emit_html.zig` | 257 | HTML emitter from arena |
| `hash.zig` | 243 | Semantic hashing with Blake3 |
| `privacy.zig` | 423 | Privacy scanning, redaction, policy, audit log |
| `serialize.zig` | — | Binary serialization, zero-copy view, owned load, author IR load |
| `main.zig` | 429 | Round-trip smoke test + 12 unit tests |
| `README.md` | 119 | Goals and plan |
| `DESIGN.md` | — | This file |

**Total: ~2800 lines of Zig across 10 files.**

---

### 4. Author IR

The author IR is a tree of `Node` values with nested `Inline` content. Every type that owns memory has a `free` method that recursively releases its slices.

**Node union:**

```zig
pub const Node = union(enum) {
    section: Section,
    paragraph: Paragraph,
    list: List,
    table: Table,
    block_node: Block,
    inline_node: Inline,
    diagnostic: Diagnostic,
};
```

`block` and `inline` are Zig keywords, so the union fields are named `block_node` and `inline_node`. The `NodeTag` enum in the arena uses the plain names since enum values are not keywords.

**Inline union:**

```zig
pub const Inline = union(enum) {
    text: []const u8,
    link: Link,
    reference: Reference,
    anchor: Anchor,
    emphasis: []Inline,
    strong: []Inline,
};
```

**Metadata:**

```zig
pub const Metadata = struct {
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    attrs: []const KVPair = &.{},
};
```

Uses a simple `[]const KVPair` slice instead of `StringHashMapUnmanaged` to avoid allocator management complexity. The `KVPair` type is `struct { key: []const u8, value: []const u8 }`.

**Ownership:** `Document.deinit(allocator)` walks the tree and frees every owned slice. Each struct has a `free` method that releases its own fields and recurses into children.

---

### 5. Arena IR (DoD Layout)

The arena stores all data in flat typed arrays. Nodes and inlines are accessed via tag+index pairs (`NodeEntry`, `InlineEntry`). Parent-child relationships use `first_*`/`*_count` spans that index into the flat arrays.

**DocumentArena:**

```zig
pub const DocumentArena = struct {
    arena: std.heap.ArenaAllocator,
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
    roots: []NodeIndex,
};
```

**Span model:**

```zig
pub const SectionData = struct {
    metadata: Metadata,
    title: ?[]const u8,
    first_child: ?NodeIndex,
    child_count: u32,
};
```

Children are a contiguous range in the `nodes` array: `doc.nodes[first_child..][0..child_count]`. Helper functions `childSlice` and `childInlineSlice` provide safe access.

**Roots:** The `roots: []NodeIndex` field tracks which nodes are document-level roots. This was not in the original elements.md spec but proved essential — without it, all nodes were treated as top-level, causing HTML emission to duplicate content.

**Ownership:** `DocumentArena.deinit()` calls `self.arena.deinit()`, which releases all memory in one operation. All strings, slices, and typed arrays live inside the arena.

---

### 6. Builder API

The builder (`build_ir.zig`) provides safe construction helpers that enforce invariants at build time.

**Invariants enforced:**

- Paragraphs only accept `[]Inline` content.
- Sections, list items, table cells, and generic blocks only accept `[]Node` children that pass `isBlock()`.
- Empty children lists return `error.EmptyChildren`.
- Metadata is consistently initialized via `MetadataSpec`.

**Error types:**

```zig
pub const BuildError = std.mem.Allocator.Error || error{
    DuplicateNode,
    EmptyChildren,
    InvalidChildType,
};
```

**Key methods:**

| Method | Returns |
|---|---|
| `document(meta, blocks)` | `Document` |
| `section(meta, title, children)` | `Node` |
| `paragraph(content)` | `Node` |
| `list(kind, items)` | `Node` |
| `listItem(children)` | `ListItem` |
| `table(rows)` | `Node` |
| `tableRow(cells)` | `TableRow` |
| `tableCell(children)` | `TableCell` |
| `genericBlock(meta, children)` | `Node` |
| `inlineText(value)` | `Inline` |
| `inlineLink(target, label)` | `Inline` |
| `inlineReference(target, label)` | `Inline` |
| `inlineAnchor(name)` | `Inline` |
| `inlineEmphasis(content)` | `Inline` |
| `inlineStrong(content)` | `Inline` |

Each method allocates and owns its returned value. The caller assembles them into slices and passes them to the next level.

---

### 7. Lowering Pass

The lowering pass (`lower.zig`) walks the author tree and populates flat arrays in the arena.

**Strategy:**

1. Create an `ArenaAllocator` backed by the caller's allocator.
2. Initialize empty `ArrayList` instances for each typed array (using `.empty` initialization per Zig 0.16).
3. Walk the author tree depth-first, appending entries to each list.
4. Record root node indices as document blocks are lowered.
5. Return a `DocumentArena` with all `.items` slices pointing into arena-owned memory.

**String handling:** All strings are duplicated into the arena via `allocator.dupe(u8, ...)`. The arena owns the copies; the author IR retains its originals.

**Index assignment:** Each typed array gets sequential indices. A `NodeEntry` stores `{ tag, index }` where `index` points into the corresponding typed array (e.g., `sections[index]`). Children reference parent arrays via `first_child`/`child_count` spans.

**Error types:** All lowering functions return `LowerError!NodeIndex` or `LowerError!InlineIndex` where `LowerError = std.mem.Allocator.Error`. Explicit error types are required to break the mutual recursion dependency loop between `lowerNode` and the type-specific lowering functions.

---

### 8. Validation

The validation pass (`validate.zig`) checks structural correctness and reference resolution on the arena.

**Structural checks:**

| Check | Severity | Condition |
|---|---|---|
| Section has no children | warn | `child_count == 0` |
| Section has no title | warn | `title == null` and `metadata.title == null` |
| Paragraph is empty | info | `inline_count == 0` |
| List has no items | warn | `item_count == 0` |
| List item has no children | warn | `child_count == 0` |
| Table has no rows | err | `row_count == 0` |
| Inconsistent cell count | warn | Row cell counts differ |
| Table cell is empty | info | `child_count == 0` |
| Block has no children | warn | `child_count == 0` |

**Reference resolution:**

Anchors are collected from two sources:
1. Inline `Anchor` nodes (explicit anchor elements in the tree).
2. `metadata.id` fields on `Section` and `Block` nodes.

References are checked against this combined anchor set. Unresolved references produce `err` diagnostics.

**Diagnostic format:**

```
[level] node N: message
```

Where `level` is `err`, `warn`, or `info`, and `N` is the node index.

---

### 9. Traversal

The traversal module (`traverse.zig`) provides a stack-based depth-first walker over the arena.

**Walker API:**

```zig
pub const Walker = struct {
    allocator: std.mem.Allocator,
    doc: arena.DocumentArena,
    stack: std.ArrayList(StackFrame),

    pub fn init(allocator, doc) Walker;
    pub fn deinit(self: *Walker) void;
    pub fn walkDocument(self: *Walker) !void;
    pub fn walkFromNode(self: *Walker, entry: NodeEntry) !void;
    pub fn pushNodeChildren(self: *Walker, entry: NodeEntry) !void;
    pub fn next(self: *Walker) ?WalkEvent;
};
```

**WalkEvent:**

```zig
pub const WalkEvent = union(enum) {
    node: NodeRef,
    inline_el: InlineRef,
};
```

The `inline` field is named `inline_el` because `inline` is a Zig keyword.

**Usage pattern:**

```zig
var walker = Walker.init(allocator, doc_arena);
defer walker.deinit();
try walker.walkDocument();
while (walker.next()) |event| {
    switch (event) {
        .node => |nr| { try walker.pushNodeChildren(nr.entry); },
        .inline_el => |ir| { /* process inline */ },
    }
}
```

**Counting helpers:**

- `countNodesByTag(doc, tag)` — count nodes with a given `NodeTag`.
- `countInlinesByTag(doc, tag)` — count inlines with a given `InlineTag`.

---

### 10. HTML Emission

The HTML emitter (`emit_html.zig`) produces a complete HTML document from the arena.

**Root-based iteration:** The emitter iterates `doc.roots` and recursively emits each root node and its children. This avoids the duplication that occurs when iterating all nodes flat.

**Section anchors:** When a section has `metadata.id`, the emitter outputs `<a id="..."></a>` before the section heading. This makes section IDs navigable targets for cross-references.

**Inline rendering:**

| Inline type | HTML output |
|---|---|
| text | Escaped text content |
| link | `<a href="target">label</a>` |
| reference | `<a href="#target">label</a>` |
| anchor | `<a id="name"></a>` |
| emphasis | `<em>content</em>` |
| strong | `<strong>content</strong>` |

**HTML escaping:** The `appendEscapedHtml` function escapes `&`, `<`, `>`, and `"` characters.

**ArrayList-based output:** The emitter uses `std.ArrayList(u8)` with `appendSlice` calls (Zig 0.16 removed the `writer()` method from unmanaged ArrayList).

---

### 11. Semantic Hashing

The hash module (`hash.zig`) produces stable Blake3 digests from meaning-bearing fields in the arena.

**API:**

```zig
pub fn hashDocument(doc: arena.DocumentArena) [32]u8;
```

**What is hashed:**

- Node tags (structural identity)
- Text content (length-prefixed)
- Link targets and labels
- Reference targets and labels
- Anchor names
- List kind (ordered, unordered, task, description)
- Metadata: id, title, roles (in order), attrs (in stored order)

**What is skipped:**

- Node indices (implementation detail)
- Inline indices (implementation detail)
- `first_child`/`child_count` spans (structural, not semantic)
- Memory addresses and allocation metadata

**Marker byte scheme:**

Each structural element gets a unique byte marker. Open/close pairs distinguish nesting:

| Marker | Value | Meaning |
|---|---|---|
| `section_open` | `0x01` | Begin section |
| `paragraph` | `0x02` | Paragraph (self-closing) |
| `list_open` | `0x03` | Begin list |
| `list_item` | `0x04` | List item |
| `table_open` | `0x05` | Begin table |
| `table_row` | `0x06` | Table row |
| `table_cell` | `0x07` | Table cell |
| `block_open` | `0x08` | Begin generic block |
| `text` | `0x10` | Text inline |
| `link` | `0x11` | Link inline |
| `reference` | `0x12` | Reference inline |
| `anchor` | `0x13` | Anchor inline |
| `emphasis_open` | `0x14` | Begin emphasis |
| `strong_open` | `0x15` | Begin strong |
| `meta_id` | `0x20` | Metadata id field |
| `meta_title` | `0x21` | Metadata title field |
| `meta_role` | `0x22` | Metadata role entry |
| `meta_attr_key` | `0x23` | Metadata attribute key |
| `meta_attr_val` | `0x24` | Metadata attribute value |
| `list_ordered` | `0x30` | List kind: ordered |
| `list_unordered` | `0x31` | List kind: unordered |
| `list_task` | `0x32` | List kind: task |
| `list_description` | `0x33` | List kind: description |
| `end` | `0xFF` | Close current container |

**String encoding:** All strings are length-prefixed with a big-endian `u32` followed by the raw bytes. This prevents boundary ambiguity (e.g., `"hello" + "world"` cannot collide with `"hell" + "oworld"`).

**Traversal order:** Depth-first, left-to-right from arena roots. This is deterministic given the same arena.

**Determinism guarantees:**

- Same author document → same arena → same hash.
- Different content → different hash.
- Different structure → different hash (markers prevent structural ambiguity).
- Different list kind → different hash.
- Different link/reference targets → different hash.

**Current limitation:** Metadata attributes are hashed in stored order. If attribute order should be irrelevant, sorting by key before hashing can be added to `sortedAttrs()`.

---

### 12. Privacy

The privacy module (`privacy.zig`) provides first-class scanning, redaction, policy enforcement, and audit logging on the arena IR. It operates as a read-only module over the flat arrays — no change to the core tree is required.

**Design principle:** Privacy is opt-in and operates at the operational layer, not the semantic layer. The arena provides all the data; the privacy module provides the policies. Downstream tools (emitters, exporters, APIs) can query privacy findings to decide what to output.

**API:**

| Function | Purpose |
|---|---|
| `scanDocument(doc, allocator) !ScanResult` | Walk the arena, detect sensitive content, return findings |
| `redactString(text, strategy, allocator, replacement) ![]const u8` | Apply redaction to a single string |
| `applyPolicy(findings, policy, allocator) ![]AuditEntry` | Filter findings against a policy, produce audit entries |

**Pattern matchers:**

| Detector | What it flags |
|---|---|
| `isEmail(text) bool` | `user@domain.tld` |
| `isUrl(text) bool` | `http://` / `https://` prefixed strings |
| `isApiKey(text) bool` | Strings starting with known key prefixes (`sk-`, `pk_`, `whsec_`, etc.) |
| `isIpv4(text) bool` | Valid dotted-decimal IPv4 addresses (validated octet range) |
| `isPhone(text) bool` | Strings with 7-15 digits and valid phone separators |

**Redaction strategies:**

| Strategy | Behavior |
|---|---|
| `mask` | Replace each character with `*`, preserving length |
| `remove` | Return empty string |
| `hash_content` | Replace with 64-char hex Blake3 digest of original content |
| `replace` | Replace with a caller-provided string |

**Scanning scope:**

The scanner walks every string-bearing field in the arena:
- Inline text (`doc.texts[].value`)
- Link targets (`doc.links[].target`)
- Reference targets (`doc.references[].target`)
- Anchor names (`doc.anchors[].name`)
- Section metadata: id, title, attrs (keys and values)
- Block metadata: id, title, attrs (keys and values)
- Document metadata: id, title, attrs (keys and values)

Each finding records the `kind`, `location` (typed to the exact field), `offset`, `length`, and a copy of the original text.

**Preset policies:**

| Policy | Redacts | Strategy |
|---|---|---|
| `publicPolicy` | email, api_key, phone | mask |
| `internalPolicy` | api_key only | mask |
| `confidentialPolicy` | email, api_key, ipv4, phone, url | remove |
| `strictPolicy` | everything | hash_content |

**Location types:**

```zig
pub const Location = union(enum) {
    text_inline: u32,
    link_target: u32,
    reference_target: u32,
    anchor_name: u32,
    metadata_id: u32,
    metadata_title: u32,
    metadata_attr: struct { node_idx: u32, entry_idx: u32, is_key: bool },
    document_metadata_id,
    document_metadata_title,
    document_metadata_attr: struct { entry_idx: u32, is_key: bool },
};
```

**Memory model:**

The scanner allocates findings into its own `ArenaAllocator` returned as part of `ScanResult`. The caller calls `scan_result.deinit()` to release everything at once. Individual string redactions allocate via the caller's allocator and must be freed separately.

**Tests:** 11 tests covering all matchers, all redaction strategies, policy filtering, and preset policy validation. All pass with no memory leaks.

**Integration pattern:**

```zig
var scan_result = try privacy.scanDocument(doc_arena, allocator);
defer scan_result.deinit();

const entries = try privacy.applyPolicy(
    scan_result.findings,
    privacy.confidentialPolicy,
    allocator,
);
defer allocator.free(entries);

for (entries) |entry| {
    // log entry for audit trail
    // use entry.original_slice + entry.kind to redact
}
```

**What's not in scope yet:**

- Custom pattern definitions (regex or pluggable matchers)
- Redacted arena cloning (producing a new `DocumentArena` with content replaced)
- Content classification labels on nodes (can ride on `Metadata.attrs` today)
- Integration with the HTML emitter for automatic output filtering
- Differential privacy or statistical privacy guarantees

---

### 13. Serialization

The serialization module (`serialize.zig`) provides a portable binary format for `DocumentArena` with three load paths: zero-copy borrowed view (read-only), owned deserialization (mutable arena), and author IR reconstruction (mutable tree).

**Design goals:**

1. Single portable binary blob — no external dependencies, no native struct dumps
2. Zero-copy borrowed view — validate once, decode records on the fly from the original bytes
3. Owned load — allocate and decode into a full `DocumentArena` for mutation
4. Author IR load — reconstruct the recursive author tree from the arena (for future authoring tools)

**Portability invariants** (from `strat_portability_invariants.md`):

| Invariant | Rule |
|---|---|
| Endianness | All multi-byte fields little-endian |
| Type widths | Fixed-width only (u8, u16, u32, u64) |
| Padding | All reserved bytes zeroed; rejected if nonzero on read |
| Field order | Declaration-ordered, no reordering |
| No native dumps | All records manually encoded/decoded field-by-field |
| No platform deps | No paths, timestamps, locale, or filesystem references |

#### Binary Layout

```
┌──────────────────────────────────────────┐
│ Header (fixed size, ~80 bytes)            │
│   magic: "XNDOC\0" (6 bytes)             │
│   format_version: u16 LE (currently 1)   │
│   ir_version: u16 LE      (currently 1)  │
│   flags: u32 LE                          │
│   ── typed array counts (u32 each) ──    │
│   node_entries, inline_entries, sections, │
│   paragraphs, lists, list_items, tables,  │
│   rows, cells, blocks, texts, links,      │
│   references, anchors, emphases, strongs, │
│   diagnostics, roots, string_refs,        │
│   kv_pairs                               │
│   bytes_len: u64 LE                      │
│   ── document metadata refs ──           │
│   doc_meta_id, doc_meta_title (u32)      │
│   doc_meta_roles{first_ref,count} (8)    │
│   doc_meta_attrs{first_kv,count} (8)     │
├──────────────────────────────────────────┤
│ NodeEntry records      (5 bytes each)     │
│ InlineEntry records    (5 bytes each)     │
│ SectionData records    (28 bytes each)    │
│ ParagraphData records  (8 bytes each)     │
│ ListData records       (9 bytes each)     │
│ ListItemData records   (8 bytes each)     │
│ TableData records      (8 bytes each)     │
│ TableRowData records   (8 bytes each)     │
│ TableCellData records  (8 bytes each)     │
│ BlockData records      (24 bytes each)    │
│ TextData records       (4 bytes each)     │
│ LinkData records       (8 bytes each)     │
│ ReferenceData records  (8 bytes each)     │
│ AnchorData records     (4 bytes each)     │
│ EmphasisData records   (8 bytes each)     │
│ StrongData records     (8 bytes each)     │
│ Diagnostic records     (4 bytes each)     │
│ Root indices           (u32 each)         │
│ StringRef records      (8 bytes each)     │
│ KVPair records         (8 bytes each)     │
├──────────────────────────────────────────┤
│ Byte arena (packed UTF-8 string data)    │
└──────────────────────────────────────────┘
```

Sections are laid out sequentially after the header. Reader computes each section's offset from header → count × record_size → accumulated offset. No TOC table needed since all counts are known up front and record sizes are constant.

#### Disk Record Types

All nullable `u32` fields use `0xFFFFFFFF` as the null sentinel.

| In-memory | Disk record | Bytes |
|---|---|---|
| `NodeEntry` | `{ tag: u8, index: u32 }` | 5 |
| `InlineEntry` | `{ tag: u8, index: u32 }` | 5 |
| `SectionData` | `{ meta: MetadataDisk, title_ref: u32, first_child: u32, child_count: u32 }` | 28 |
| `ParagraphData` | `{ first_inline: u32, inline_count: u32 }` | 8 |
| `ListData` | `{ kind: u8, first_item: u32, item_count: u32 }` | 9 |
| `ListItemData` | `{ first_child: u32, child_count: u32 }` | 8 |
| `TableData` | `{ first_row: u32, row_count: u32 }` | 8 |
| `TableRowData` | `{ first_cell: u32, cell_count: u32 }` | 8 |
| `TableCellData` | `{ first_child: u32, child_count: u32 }` | 8 |
| `BlockData` | `{ meta: MetadataDisk, first_child: u32, child_count: u32 }` | 24 |
| `TextData` | `{ value_ref: u32 }` | 4 |
| `LinkData` | `{ target_ref: u32, label: u32 }` | 8 |
| `ReferenceData` | `{ target_ref: u32, label: u32 }` | 8 |
| `AnchorData` | `{ name_ref: u32 }` | 4 |
| `EmphasisData` | `{ first_inline: u32, inline_count: u32 }` | 8 |
| `StrongData` | `{ first_inline: u32, inline_count: u32 }` | 8 |
| `DiagnosticDisk` | `{ message_ref: u32 }` | 4 |
| `StringRef` | `{ start: u32, len: u32 }` | 8 |
| `KVPairDisk` | `{ key_ref: u32, value_ref: u32 }` | 8 |
| `MetadataDisk` | `{ id_ref: u32, title_ref: u32, roles_first: u32, roles_count: u32, attrs_first: u32, attrs_count: u32 }` | 24 |

**MetadataDisk format:**

All string fields reference the string_refs table. `roles` is a contiguous span of role string refs. `attrs` is a contiguous span of KVPair entries.

**StringRef format:**

```
{ start: u32, len: u32 }
```
Points into the packed byte arena at the end of the file. `start + len` must not exceed `bytes_len`.

#### String Storage

All strings are collected into a single packed byte arena at the end of the file. Strings are referenced by index into the string_refs table. No deduplication — each occurrence gets its own StringRef entry and its own bytes in the arena.

During serialization, all arena strings (text values, metadata ids/titles, link targets, anchor names, etc.) are iterated in declaration order and appended to the byte arena. Each string gets a `StringRef { start, len }`.

#### API

```zig
// Write
pub fn serialize(writer, doc: DocumentArena) !void;

// Validate only (no allocation)
pub fn validate(bytes: []const u8) !ValidationReport;

// Owned load → full DocumentArena (for mutation)
pub fn deserialize(allocator, bytes: []const u8) !DocumentArena;

// Zero-copy borrowed view (for read-only operations)
pub fn view(bytes: []const u8) !BorrowedArenaView;

// Author IR load (reconstruct recursive tree)
pub fn deserializeToAuthorIr(allocator, bytes: []const u8) !author.Document;
```

#### Three Load Paths

| Path | Speed | Mutation | Use case |
|---|---|---|---|
| `view()` | Fastest (zero-copy) | No | Emit, hash, validate, privacy scan |
| `deserialize()` | Medium (allocate + decode) | Yes (arena) | Transforms, bulk operations |
| `deserializeToAuthorIr()` | Slowest (reconstruct tree) | Yes (full) | Future authoring tools |

#### BorrowedArenaView

```zig
pub const BorrowedArenaView = struct {
    raw: []const u8,           // original bytes (caller must keep alive)
    header: HeaderDisk,
    node_entries:   []const u8,  // raw record bytes
    inline_entries: []const u8,
    sections:       []const u8,
    paragraphs:     []const u8,
    lists:          []const u8,
    list_items:     []const u8,
    tables:         []const u8,
    rows:           []const u8,
    cells:          []const u8,
    blocks:         []const u8,
    texts:          []const u8,
    links:          []const u8,
    references_:    []const u8,
    anchors:        []const u8,
    emphases:       []const u8,
    strongs:        []const u8,
    diagnostics:    []const u8,
    roots:          []const u8,
    string_refs:    []const u8,
    kv_pairs:       []const u8,
    bytes_arena:    []const u8,

    pub fn getNodeEntry(self, idx: u32) NodeEntry;
    pub fn getInlineEntry(self, idx: u32) InlineEntry;
    pub fn getSection(self, idx: u32) SectionData;
    pub fn getString(self, ref_idx: u32) []const u8;
    pub fn getMetadata(self, meta: MetadataDisk) Metadata;
    pub fn nodeCount(self, tag: NodeTag) usize;
    pub fn inlineCount(self, tag: InlineTag) usize;
};
```

Each `get*` method decodes the disk record from raw bytes. No allocation. The caller must keep the original `raw` byte slice alive.

#### Owned Load Path

`deserialize()` validates, allocates typed arrays via an inner ArenaAllocator, decodes all disk records into native structs, and returns a `DocumentArena`. The caller calls `doc.deinit()` to release all memory at once. There is no intermediate allocation that the caller needs to track — the arena owns everything.

#### Author IR Load

`deserializeToAuthorIr()` first deserializes into a `DocumentArena`, then walks the arena roots and reconstructs the recursive `author.Document` tree. Each author node allocates its children from the caller's allocator. The caller calls `doc.deinit()` to release. This path is intentionally slower but enables the full mutation surface of the author IR.

#### Validation

The validator checks:
- Magic bytes match `"XNDOC\0"`
- Format version is supported
- All record offsets are within bounds
- All string refs are within the byte arena
- Null sentinels are `0xFFFFFFFF` (no other null value accepted)
- No nonzero bytes in reserved fields
- Count fields are consistent (e.g., `node_entries_count` matches the actual binary)

#### What This Enables

- **Cache parsed documents** as `.xndoc` binary files
- **Fast reload** for CI pipelines, build tools, preview servers
- **Zero-copy emission** from stored documents (no re-parse)
- **Privacy scanning** on stored documents without full deserialization
- **Future authoring tools** can load as mutable author IR via `deserializeToAuthorIr()`

---

### 14. Zig 0.16 Migration Notes

it3 targets Zig 0.16.0. Several standard library APIs changed from earlier versions:

**ArrayList is now unmanaged:**

`std.ArrayList(T)` returns an unmanaged type (previously `ArrayListUnmanaged`). All methods require an explicit allocator parameter:

```zig
var list: std.ArrayList(T) = .empty;          // no .init(allocator)
try list.append(allocator, item);              // allocator is first arg
try list.appendSlice(allocator, items);
list.deinit(allocator);
const slice = try list.toOwnedSlice(allocator);
```

**GeneralPurposeAllocator removed:**

Use `std.heap.ArenaAllocator` or `std.heap.SmpAllocator` instead. The smoke test uses an outer `ArenaAllocator` backed by `page_allocator`.

**std.io renamed to std.Io:**

The IO subsystem was reorganized. `std.io.getStdOut()` is no longer available. The smoke test uses `std.debug.print` for output instead.

**StringHashMap API:**

`std.StringHashMap` (managed) still uses `init(allocator)` and `deinit()` without an allocator parameter. The `keys()` method was removed; use `keyIterator()` instead:

```zig
var it = map.keyIterator();
while (it.next()) |key_ptr| {
    // key_ptr is *[]const u8
}
```

**@intCast requires known result type:**

When the result type cannot be inferred from context, use `@as`:

```zig
const idx: u32 = @intCast(value);
// or
const idx = @as(u32, @intCast(value));
```

**Mutual recursion requires explicit error types:**

Functions that call each other recursively cannot use inferred error sets (`!T`). Define an explicit error type:

```zig
pub const LowerError = std.mem.Allocator.Error;
fn lowerNode(...) LowerError!NodeIndex { ... }
```

**Keywords as field names:**

`inline` and `block` are Zig keywords. Union fields must use alternative names (`inline_node`, `block_node`). Enum values are not affected.

---

### 15. Lessons Learned

**Roots tracking was needed:** The original elements.md spec did not include a `roots` field in `DocumentArena`. Without it, all nodes in the flat array were treated as top-level, causing HTML emission to duplicate content (parent nodes emitted their children, and children were also emitted independently). Adding `roots: []NodeIndex` resolved this cleanly.

**metadata.id acts as anchor target:** References in the smoke test point to section IDs (e.g., `"overview"`, `"tables"`), not to inline anchor elements. The validation pass was updated to collect anchors from both inline `Anchor` nodes and `metadata.id` fields on `Section` and `Block` nodes. The HTML emitter outputs `<a id="..."></a>` for section metadata IDs.

**Builder ergonomics:** The builder pattern works well for small documents but becomes verbose for larger ones due to the need to allocate each node individually and assemble slices manually. A higher-level DSL or macro system could reduce boilerplate. The `MetadataSpec` struct with default fields helps.

**Arena ownership is clean:** Using a single `ArenaAllocator` for the entire arena makes cleanup trivial — one `deinit()` call releases everything. The tradeoff is that individual nodes cannot be freed independently, which is acceptable for a document-level IR.

**Zig 0.16 API changes are pervasive:** The unmanaged ArrayList, removed `GeneralPurposeAllocator`, renamed IO module, and changed HashMap API required updates across all files. The migration is straightforward but touches every module.

**Semantic hashing is straightforward with markers:** The marker byte scheme with length-prefixed strings produces stable, collision-resistant hashes. The main design decision was whether to hash metadata attributes in stored order or sorted order. Stored order was chosen for simplicity; sorting can be added later if needed.

---

### 16. Running

**Smoke test:**

```bash
zig run main.zig
```

Produces output showing:
- Arena statistics (node/inline counts by type)
- Validation diagnostics (0 for the example document)
- Tree walk summary (nodes and inlines visited)
- Semantic hash (32-byte Blake3 digest in hex)
- Full HTML output

**Unit tests:**

```bash
zig test main.zig
```

Runs 12 tests:

1. Builder enforces block/inline separation
2. Round trip: author to arena to HTML
3. Validation passes on valid document
4. Validation warns on empty section
5. Traverse counts match expected
6. HTML output is non-empty and contains expected elements
7. Metadata round-trips through lowering
8. Semantic hash is deterministic
9. Semantic hash detects structural difference
10. Semantic hash detects content difference
11. Semantic hash detects list kind difference
12. Semantic hash includes link target

**Privacy tests:**

```bash
zig test privacy.zig
```

Runs 11 tests: email/url/api_key/ipv4/phone detection, all four redaction strategies, policy filtering, and preset policy validation.

**Integration tests (main.zig):**

```bash
zig test main.zig
```

Runs 12 tests covering the builder, round-trip, validation, traversal, HTML output, metadata, and 5 semantic hash tests.

**Note:** Two tests report memory leaks from `std.testing.allocator` (the debug allocator). These are test cleanup issues in the builder and validation modules, not production bugs. The builder test creates nodes without freeing them, and the validation test's `seen_refs` HashMap does not free its duplicated keys.
