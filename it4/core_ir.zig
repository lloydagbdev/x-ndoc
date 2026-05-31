const std = @import("std");
const author = @import("author_ir.zig");

pub const KVPair = author.KVPair;
pub const Metadata = author.Metadata;
pub const ListKind = author.ListKind;

pub const NodeIndex = u32;
pub const InlineIndex = u32;
pub const ChildRefIndex = u32;
pub const InlineChildRefIndex = u32;

pub const DiagnosticLevel = enum {
    info,
    warn,
    err,
};

pub const DiagnosticSubject = union(enum) {
    document,
    node: NodeIndex,
    inline_ref: InlineIndex,
};

pub const Diagnostic = struct {
    level: DiagnosticLevel,
    subject: DiagnosticSubject,
    message: []const u8,
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

pub const NodeRef = struct {
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

pub const InlineRef = struct {
    tag: InlineTag,
    index: u32,
};

pub const SectionData = struct {
    metadata: Metadata,
    title: ?[]const u8,
    first_child_ref: ?ChildRefIndex,
    child_count: u32,
};

pub const ParagraphData = struct {
    first_child_ref: ?InlineChildRefIndex,
    child_count: u32,
};

pub const ListData = struct {
    kind: ListKind,
    first_child_ref: ?ChildRefIndex,
    child_count: u32,
};

pub const ListItemData = struct {
    first_child_ref: ?ChildRefIndex,
    child_count: u32,
};

pub const TableData = struct {
    first_child_ref: ?ChildRefIndex,
    child_count: u32,
};

pub const TableRowData = struct {
    first_child_ref: ?ChildRefIndex,
    child_count: u32,
};

pub const TableCellData = struct {
    first_child_ref: ?ChildRefIndex,
    child_count: u32,
};

pub const BlockData = struct {
    metadata: Metadata,
    first_child_ref: ?ChildRefIndex,
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
    first_child_ref: ?InlineChildRefIndex,
    child_count: u32,
};

pub const StrongData = struct {
    first_child_ref: ?InlineChildRefIndex,
    child_count: u32,
};

pub const Document = struct {
    arena: *std.heap.ArenaAllocator,
    arena_owner: std.mem.Allocator,
    metadata: Metadata,
    roots: []NodeIndex,
    node_child_refs: []NodeIndex,
    inline_child_refs: []InlineIndex,
    nodes: []NodeRef,
    inlines: []InlineRef,
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

    pub fn deinit(self: *Document) void {
        self.arena.deinit();
        self.arena_owner.destroy(self.arena);
        self.* = undefined;
    }
};

pub fn nodeChildren(doc: Document, first: ChildRefIndex, count: u32) []const NodeIndex {
    return doc.node_child_refs[first..][0..count];
}

pub fn inlineChildren(doc: Document, first: InlineChildRefIndex, count: u32) []const InlineIndex {
    return doc.inline_child_refs[first..][0..count];
}
