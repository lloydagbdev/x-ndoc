# Iteration 3 — Complete

it3 converges it1's flat-graph and it2's two-level explorations onto the semantic surface defined in `doc/elements.md`. All original goals achieved, plus three modules beyond scope: semantic hashing, privacy scanning, and binary serialization.

## Architecture

```
build → author IR → lower → arena IR → validate / traverse / emit / hash / privacy / serialize
```

| Level | Module | Purpose |
|---|---|---|
| **Author IR** | `author_ir.zig` | `union(enum)` tree with `Node` (7 variants) and `Inline` (6 variants), recursive ownership |
| **Builder** | `build_ir.zig` | Safe construction enforcing block/inline separation |
| **Lowering** | `lower.zig` | Author → arena runtime pass, string duplication |
| **Arena IR** | `arena_ir.zig` | Flat `DocumentArena` with 16 typed arrays, index spans, `roots` tracking |
| **Validation** | `validate.zig` | Structural checks, anchor/reference resolution |
| **Traversal** | `traverse.zig` | Depth-first stack-based walker, counting helpers |
| **HTML** | `emit_html.zig` | HTML emitter from arena roots, section anchors |
| **Hashing** | `hash.zig` | Blake3 semantic hashing with byte markers, length-prefixed strings |
| **Privacy** | `privacy.zig` | 5 pattern matchers, 4 redaction strategies, 4 preset policies, audit log |
| **Serialization** | `serialize.zig` | Portable binary format, zero-copy borrowed view, owned deserialization |
| **Integration** | `main.zig` | Smoke test exercising all modules, 12 unit tests |
| **Docs** | `DESIGN.md` | 16-section architecture deep-dive |

## What was deferred (and what happened to it)

| Original deferral | What happened |
|---|---|
| Semantic hashing | Done — `hash.zig`, 5 tests |
| Privacy | Done — `privacy.zig`, 11 tests, 4 preset policies |
| Serialization | Done — `serialize.zig`, 8 tests, zero-copy view |
| Parsing real AsciiDoc/Markdown | Still deferred (Phase 1) |
| Full emitter parity with it1 | Still deferred |
| Performance benchmarking | Still deferred |

## Smoke test

Exercises all modules on a representative document (4 sections, 14 paragraphs, 2 lists, 1 table, 1 anchor, 3 references, 1 block):

```bash
zig run it3/main.zig
```

## Tests

```bash
zig test it3/main.zig      # 12 core + integration tests
zig test it3/privacy.zig   # 11 privacy tests
zig test it3/serialize.zig # 8 serialization tests
```

31 total tests, all passing, zero privacy/serialize test leaks.
