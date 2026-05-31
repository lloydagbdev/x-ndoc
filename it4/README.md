# Iteration 4 — Core API Reset

Iteration 4 starts from iteration 3's semantic surface, but resets the runtime core around a cleaner API and safer data structures.

## Goals

1. Define a small, coherent core API for the prototype.
2. Replace iteration 3's implicit child-span layout with explicit child index lists.
3. Keep authoring, runtime IR, validation, traversal, and rendering clearly separated.
4. Resolve the structural and lifecycle problems found in iteration 3.

## Initial architecture

```
build -> author IR -> lower -> core IR -> validate / traverse / emit / hash
```

## Current modules

| Module | Purpose |
|---|---|
| `api.zig` | Public API surface with namespaced and flat exports |
| `core_ir.zig` | Canonical runtime IR with explicit child index slices |
| `author_ir.zig` | Author-facing tree IR (copied from iteration 3) |
| `build_ir.zig` | Safe construction helpers for author IR |
| `lower.zig` | Author IR to core IR lowering |
| `validate.zig` | Structural and reference validation |
| `traverse.zig` | Exact walk over nodes and inlines |
| `emit_html.zig` | HTML emitter using direct child indexes |
| `hash.zig` | Semantic hashing over the core IR |
| `serialize.zig` | Binary serialization with semantic validation |
| `transform.zig` | Safe clone-and-rewrite helpers (subtree-aware) |
| `privacy.zig` | Optional privacy scanning and policy application |
| `adapter.zig` | Parsed tree + event stream ingestion |
| `parser.zig` | Mini markdown parser front-end |
| `main.zig` | Thin wrapper + test suite (36 tests) |
| `smoke_main.zig` | Smoke executable |
| `smoke_support.zig` | Shared smoke/test helpers |
| `tests.zig` | Dedicated test entry point |
| `demo.zig` | Parsed tree adapter demo |
| `demo_events.zig` | Event stream adapter demo |
| `demo_parse.zig` | Mini markdown parser demo |

## Key design change

Iteration 3 stored parents and children in flat typed arrays and inferred children from contiguous spans in append order. That made nested structures ambiguous and caused duplicated traversal and HTML output.

Iteration 4 makes direct children explicit:

- each node container stores `first_child_ref` + `child_count`
- each inline container stores `first_child_ref` + `child_count`
- child refs point into dedicated `node_child_refs` / `inline_child_refs` arrays

This keeps typed payload arrays while making topology unambiguous.

## Implementation Status

All core features are implemented and tested:

- ✅ Core IR redesign with explicit child references
- ✅ Lowering from author IR to core IR
- ✅ Traversal with exact node/inline counting
- ✅ HTML emission
- ✅ Semantic hashing (Blake3)
- ✅ Structural validation
- ✅ Binary serialization with semantic validation
- ✅ Privacy scanning with redaction policies
- ✅ Clone-based transforms (rename, retitle, replace, retarget)
- ✅ Subtree-aware structural transforms (remove/insert sections anywhere)
- ✅ Parsed tree ingestion adapter
- ✅ Event stream ingestion adapter
- ✅ Mini markdown parser front-end
- ✅ 36 passing tests
- ✅ 3 working demos

See [DESIGN.md](DESIGN.md) for complete architecture documentation.

## Run

```bash
zig test it4/main.zig
zig test it4/tests.zig
zig run it4/main.zig
zig run it4/demo.zig
zig run it4/demo_events.zig
zig run it4/demo_parse.zig
```

## API entry point

External callers should prefer `it4/api.zig` over importing individual files directly.

The API now also exposes namespaced entry points such as:

- `api.build`
- `api.core`
- `api.validate_doc`
- `api.emit`
- `api.binary`
- `api.privacy_scan`
- `api.rewrite`
- `api.ingest`

`api.ingest` now includes both a parsed-tree adapter and a narrow event-stream adapter for parser prototypes.
