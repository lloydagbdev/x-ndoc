# Semantic IR Iteration 1

This directory is the first exploration pass for a low-level semantic document IR.

The point of this iteration is not to lock in a final design. It is to pressure-test a small semantic core that can later support:

- authoring operations over documents
- semantic transforms
- projection into lossy and non-lossy output formats
- richer reference structure than a pure tree can express

## Core Model

The IR in `semantic_ir.zig` treats a document as:

- a flat node table
- a root list
- a separate edge table

That means containment is still modeled through node children, but semantic relationships are modeled as graph edges.

Current top-level shape:

```zig
pub const Document = struct {
    roots: []const NodeId,
    nodes: []const Node,
    edges: []const Edge,
};
```

## Why This Shape

The main design decision in this iteration is:

- do not make the IR a recursive embedded tree
- do make node identity explicit from the start

This makes it easier to represent:

- cross references
- footnotes
- citations
- transclusion / includes
- grouped references

without forcing all semantics into parent/child structure.

## Node Kinds

Current block-oriented node kinds:

- `document`
- `section`
- `heading`
- `paragraph`
- `list`
- `list_item`
- `quote`
- `code_block`
- `include`
- `footnote_def`
- `bibliography_def`

Current inline-oriented node kinds:

- `text`
- `emphasis`
- `strong`
- `code_span`
- `reference`
- `reference_group`

This split is intentionally small but already enough to test block/inline constraints and reference semantics.

## Edge Kinds

Current edge kinds:

- `link`
- `xref`
- `cite`
- `footnote_ref`
- `include`

Edges are separate from nodes so that reference structure is explicit and can be validated independently from containment.

## Current Semantics Covered

This iteration already supports:

- named headings / anchors
- cross references
- footnote references and definitions
- citation references and bibliography definitions
- grouped citations through `reference_group`
- include / transclusion nodes

## Validation

`semantic_ir.validate(doc)` is already doing meaningful semantic work.

It checks:

- root ids and child ids are in range
- block and inline placement rules
- reference nodes actually have edges
- edge source kinds are valid for each edge kind
- edge target kinds are valid for footnotes, citations, and includes
- node names are unique
- include graphs are acyclic

The goal is to make the IR shape fail early when semantics become inconsistent.

## Builder

`semantic_ir.Builder` exists because raw node-id tables became too brittle once footnotes, citations, and includes were added.

It currently supports:

- appending text and code spans
- appending inline and block nodes
- appending edges
- adding roots
- finishing into an owned `Document`

The builder is still intentionally minimal. It is not yet a polished authoring API.

## Emitters

This iteration includes two simple projection layers:

- `semantic_ir_html.zig`
- `semantic_ir_markdown.zig`

These are not the main point of the design, but they are useful as inspection surfaces.

HTML is the richer inspection target right now.

Markdown remains useful to expose where semantics collapse into a lossy format.

## Derived Passes

This iteration already has a few operations over the IR.

### `semantic_ir_index.zig`

Derived index builder that collects:

- named nodes
- footnote definitions
- bibliography definitions
- include nodes

This gives later transforms and authoring operations a registry-like view without changing the core IR.

### `semantic_ir_ops.flattenIncludes`

Clones the document into a flattened form where internal include nodes are expanded into their target block structure.

This is useful to test whether semantic reuse can be separated from the final projected shape.

### `semantic_ir_ops.collectDefinitionsToDocumentEnd`

Normalizes footnote and bibliography definitions so they appear at the end of the document root.

This is an early example of layout-oriented normalization driven by semantic categories.

### `semantic_ir_ops.renumberReferences`

Renumbers footnotes and citations by first reference order.

This pass rewrites:

- inline reference labels
- footnote definition names
- bibliography definition names

This is the first transform in the prototype that synthesizes new semantic labels.

## What This Iteration Is Proving

This iteration is trying to answer a few design questions:

1. Is a flat node table plus semantic edge table enough for document semantics?
2. Can a small block/inline vocabulary already support useful transforms?
3. Can references, grouped references, and includes coexist without forcing a bigger type system yet?
4. Can derived passes operate on the semantic IR without immediately needing a separate semantic normalization IR?

So far the answer looks like yes, at least for the current scope.

## Current Limitations

This is still prototype code, so several things are intentionally rough.

- there is no parser
- there is no source span / provenance tracking
- there is no public transform pipeline API yet
- include resolution for external targets is only placeholder-level
- grouped references are only semantically special-cased for citation groups
- definitions are still ordinary nodes rather than being grouped in an explicit document registry structure

## Likely Next Steps

Good next exploration directions from here:

- pipeline composition for transforms
- provenance / source-span metadata
- external include resolution through a resolver interface
- richer grouped reference semantics beyond citations
- explicit definition registries or normalized document sections
- authoring helpers above the low-level builder

## Running

Current sample entrypoint:

```sh
zig run it1/main_semantic_ir.zig -- html
zig run it1/main_semantic_ir.zig -- markdown
```

To capture output:

```sh
zig run it1/main_semantic_ir.zig -- html > index.html
zig run it1/main_semantic_ir.zig -- markdown > out.md
```

Run tests:

```sh
zig test it1/main_semantic_ir.zig
```
