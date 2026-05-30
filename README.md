# x-ndoc

A privacy-first semantic document IR toolkit. Parse documents (Markdown, AsciiDoc, etc.) into a flat, cache-friendly intermediate representation, then validate, transform, redact, hash, and emit them.

## Core Concepts

- **Format-neutral IR** — a minimal semantic surface (sections, paragraphs, lists, tables, blocks, inlines, metadata) with no format-specific leakage.
- **Two-level IR** — author-friendly union-enum tree for construction, flat typed-array arena for bulk operations.
- **Privacy as a first-class operational concern** — scan and redact sensitive content (emails, API keys, PII) from the IR without changing the core tree.
- **Semantic hashing** — stable Blake3 digests of meaning-bearing content, useful for cache keys and equivalence checks.

## Status

| Area | Status |
|---|---|
| Core IR (author + arena) | Done (it3) |
| Builder API | Done |
| Lowering (author → arena) | Done |
| Validation | Done |
| Traversal (walker) | Done |
| HTML emission | Done |
| Semantic hashing (Blake3) | Done |
| Privacy scanning + redaction | Done |
| Binary serialization | Done |
| Markdown parser | Not started |
| AsciiDoc parser | Not started |
| build.zig | Not started |
| CLI tool | Not started |
| Library API | Not started |
| Multiple output formats | HTML only |

## Project Structure

```
x-ndoc/
├── doc/
│   ├── elements.md       ← canonical semantic surface definition
│   └── asciidoc_ref.md   ← AsciiDoc reference (extracted from earlier draft)
├── it1/                  ← exploration: flat node+edge graph, transforms
├── it2/                  ← exploration: two-level IR, comptime lowering
├── it3/                  ← current: converging on elements.md surface
│   ├── author_ir.zig     ← union(enum) author-facing tree IR
│   ├── arena_ir.zig      ← flat DocumentArena DoD IR
│   ├── build_ir.zig      ← safe construction helpers
│   ├── lower.zig         ← author → arena lowering pass
│   ├── validate.zig      ← structural validation
│   ├── traverse.zig      ← depth-first walker
│   ├── emit_html.zig     ← HTML emitter
│   ├── hash.zig          ← semantic hashing (Blake3)
│   ├── privacy.zig       ← privacy scanner, redactor, policies, audit log
│   ├── serialize.zig      ← binary format, zero-copy view, owned load
│   ├── main.zig          ← smoke test + 12 integration tests
│   ├── DESIGN.md         ← detailed architecture and design notes
│   └── README.md         ← iteration goals
├── index.html            ← it1 HTML output snapshot
├── index.md              ← it1 Markdown output snapshot
├── .gitignore
└── README.md             ← this file
```

## MVP Roadmap

### Done

- [x] Define the semantic surface (`doc/elements.md`) — block/inline separation, metadata, DoD layout
- [x] Implement author IR with recursive ownership
- [x] Implement arena IR with flat typed arrays and index spans
- [x] Implement lowering pass (author → arena)
- [x] Implement safe builder with block/inline enforcement
- [x] Implement structural validation with diagnostics
- [x] Implement depth-first walker over arena spans
- [x] Implement HTML emitter from arena roots
- [x] Implement semantic hashing with Blake3
- [x] Implement privacy scanner with pattern matchers (email, URL, API key, IPv4, phone)
- [x] Implement redaction strategies (mask, remove, hash, replace)
- [x] Implement policy system with preset policies (public, internal, confidential, strict)
- [x] Implement audit log format
- [x] Implement binary serialization: portable format, zero-copy borrowed view, owned deserialization
- [x] 31 tests across main.zig, privacy.zig, and serialize.zig, all passing

### Phase 1: Parser (next)

The biggest gap. Without a parser, documents must be hand-built in Zig code.

- [ ] Simple Markdown parser (even if incomplete) — `parseMarkdown(source) !DocumentArena`
  - Headings → sections
  - Paragraphs with inline emphasis/strong/links/code
  - Ordered/unordered lists with nesting
  - Blockquotes → generic blocks
  - Code fences → generic blocks with metadata
  - Tables (GFM)
- [ ] Source span tracking in the arena (for error messages)
- [ ] Parse error diagnostics

### Phase 2: Build system + CLI

- [ ] `build.zig` with library and executable targets
- [ ] `x-ndoc parse file.md --output html` 
- [ ] `x-ndoc parse file.md --output json`
- [ ] `x-ndoc scan file.md` (privacy audit)
- [ ] `x-ndoc hash file.md` (semantic hash)
- [ ] Library API for embedding in other Zig projects

### Phase 3: Privacy integration

- [ ] Integrate privacy scanner with emitters (auto-redact on output)
- [ ] Command-line flags for privacy policies: `--privacy public|internal|confidential|strict`
- [ ] Custom pattern definitions (pluggable matchers)
- [ ] Redacted arena cloning (produce a new `DocumentArena` with content replaced)

### Phase 4: Ecosystem

- [ ] AsciiDoc parser (at minimum: sections, paragraphs, lists, tables, admonitions)
- [ ] Additional output formats (Markdown, JSON, plain text)
- [ ] Diff tooling on the IR
- [ ] Normalization passes
- [ ] Content classification labels
- [ ] Performance benchmarks
- [ ] Documentation site / user guide

### Phase 5: Maturity

- [ ] Full AsciiDoc parser
- [ ] Provenance/spans for every node
- [ ] External include/includeonce resolution
- [ ] Conditional content (preprocessor)
- [ ] Rich metadata resolution (attribute references, counters)
- [ ] Full format round-tripping (preserve whitespace and formatting where not semantic)

## Running

### Smoke test

```bash
zig run it3/main.zig
```

Exercises all it3 modules: lowering, validation, traversal, semantic hashing, privacy scan, binary serialization round-trip, and HTML output on a representative document.

### Tests

```bash
# Core IR + integration tests (12)
zig test it3/main.zig

# Privacy module tests (11)
zig test it3/privacy.zig

# Serialization tests (8)
zig test it3/serialize.zig
```

All 31 tests pass.

### Requirements

- Zig 0.16.0 (available via zvm at `~/.zvm/bin/zig`)

## Design Decisions

- **flat arena over nested tree** — cache-friendly bulk operations, single deinit
- **block/inline separation** — validated at construction time by the builder
- **`block_node`/`inline_node` field names** — `block` and `inline` are Zig keywords
- **`roots: []NodeIndex` in DocumentArena** — needed to distinguish top-level blocks from flat-array children
- **metadata.id as anchor target** — sections and blocks with an id are resolvable by references
- **privacy as operational, not semantic** — policy logic lives in `privacy.zig`, not in the core IR types
- **arena allocator for scan results** — single `deinit()` releases all findings at once

## Privacy

Privacy is a first-class concern in x-ndoc. The IR itself is privacy-agnostic by design — it models semantic meaning, not security policy. But the operational layer provides everything tools need to handle sensitive content.

See `it3/DESIGN.md` section 12 for architecture details, and `it3/privacy.zig` for the implementation.

Quick example:

```zig
var scan_result = try privacy.scanDocument(doc_arena, allocator);
defer scan_result.deinit();

const entries = try privacy.applyPolicy(
    scan_result.findings,
    privacy.publicPolicy,  // redacts email, API keys, and phone numbers
    allocator,
);
defer allocator.free(entries);

for (entries) |entry| {
    std.debug.print("[audit] {s} found at {any}\n", .{ @tagName(entry.kind), entry.location });
}
```

## License

TBD
