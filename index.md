## Low level document IR

See [the title above](#intro), and note this footnote[^1], plus these citations [@knuth84; @lamport94], before the list.

- Containment stays tree-shaped.
- References live in edges.

```
fn main() {
    std.debug.print("hello\n", .{});
}
```

## Going Deeper

Inline markup like *emphasis* and `code_span` is supported, as are [external links](https://example.com).

- Nesting works
- Level two
- Also level two

- Flat too

> A reusable transcluded block can stay outside the main tree and still be projected where needed.


## Iteration 1 Feature Overview

This IR prototype defines a low-level semantic document graph built on **nodes** and *edges*. See [the introduction](#intro) for context.

- Block kinds group structural content: document, section, heading, paragraph, list, list_item, quote, code_block, include, footnote_def, bibliography_def.
- Inline kinds carry phrasing: text, emphasis, strong, code_span, reference, reference_group. References use outgoing edges to point at targets.
- Edge kinds define relationships: link, xref, cite, footnote_ref, include. Targets are either nodes or external URLs.
- Transform passes mutate the graph after validation: flattenIncludes, collectDefinitionsToDocumentEnd, renumberReferences.

Emitters (HTML, Markdown) are lossy projections for inspection. The IR is the source of truth.

[^1]: A footnote definition can carry **full block content**, not just plain text.

[@knuth84]: Donald E. Knuth. Literate Programming. 1984.

[@lamport94]: Leslie Lamport. LaTeX: A Document Preparation System. 1994.
