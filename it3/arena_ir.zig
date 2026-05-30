const std = @import("std");
const author = @import("author_ir.zig");

pub const KVPair = author.KVPair;
pub const Metadata = author.Metadata;
pub const ListKind = author.ListKind;
pub const Diagnostic = author.Diagnostic;

pub const NodeIndex = u32;
pub const InlineIndex = u32;

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

    pub fn deinit(self: *DocumentArena) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn allocator(self: *const DocumentArena) std.mem.Allocator {
        return self.arena.allocator();
    }
};

pub fn childSlice(arena: DocumentArena, first: NodeIndex, count: u32) []NodeEntry {
    return arena.nodes[first..][0..count];
}

pub fn childInlineSlice(arena: DocumentArena, first: InlineIndex, count: u32) []InlineEntry {
    return arena.inlines[first..][0..count];
}
