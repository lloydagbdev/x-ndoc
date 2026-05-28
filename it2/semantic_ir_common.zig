pub const NodeId = u32;
pub const EdgeId = u32;

pub const NodeKind = enum {
    /// Structural root for one complete semantic document.
    document,
    /// Outline grouping that owns a heading and the content below it.
    section,
    /// Title-like block that labels a section or document region.
    heading,
    /// Prose block containing inline content.
    paragraph,
    /// Ordered or unordered collection of list items.
    list,
    /// Single item inside a list.
    list_item,
    /// Quoted block content.
    quote,
    /// Preformatted code block, usually backed by a code_block payload.
    code_block,
    /// Placeholder for content projected from another target.
    include,
    /// Definition block targeted by footnote references.
    footnote_def,
    /// Definition block targeted by citation references.
    bibliography_def,

    /// Tabular block with rows, cells, and optional table payload metadata.
    table,
    /// Structural group for table header rows.
    table_head,
    /// Structural group for table body rows.
    table_body,
    /// Structural group for table footer rows.
    table_foot,
    /// Row inside a table group or table.
    table_row,
    /// Cell inside a table row, usually backed by a table_cell payload.
    table_cell,

    /// Plain inline text backed by a text payload.
    text,
    /// Emphasized inline content.
    emphasis,
    /// Strongly emphasized inline content.
    strong,
    /// Inline code span backed by a text payload.
    code_span,
    /// Inline reference whose target is represented by an outgoing edge.
    reference,
    /// Structural inline grouping for related references.
    reference_group,

    pub fn isFragment(kind: NodeKind) bool {
        return switch (kind) {
            .document,
            .section,
            .table_head,
            .table_body,
            .table_foot,
            .reference_group,
            => true,
            else => false,
        };
    }
};

pub const EdgeKind = enum {
    /// Reference to an external URL or resource.
    link,
    /// Cross-reference to another node in the document graph.
    xref,
    /// Citation reference to a bibliography definition.
    cite,
    /// Footnote reference to a footnote definition.
    footnote_ref,
    /// Transclusion edge from an include node to included content.
    include,
};

pub const Alignment = enum {
    none,
    left,
    center,
    right,
};

pub const TableCellKind = enum {
    data,
    header,
};
