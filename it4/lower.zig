const std = @import("std");
const author = @import("author_ir.zig");
const core = @import("core_ir.zig");

pub const LowerError = std.mem.Allocator.Error || error{InvalidChildType};

pub fn lower(backing: std.mem.Allocator, doc: *const author.Document) LowerError!core.Document {
    const arena_state = try backing.create(std.heap.ArenaAllocator);
    errdefer backing.destroy(arena_state);
    arena_state.* = std.heap.ArenaAllocator.init(backing);
    errdefer arena_state.deinit();
    const a = arena_state.allocator();

    var ctx = LowerCtx{
        .a = a,
        .nodes = std.ArrayList(core.NodeRef).empty,
        .inlines = std.ArrayList(core.InlineRef).empty,
        .node_child_refs = std.ArrayList(core.NodeIndex).empty,
        .inline_child_refs = std.ArrayList(core.InlineIndex).empty,
        .sections = std.ArrayList(core.SectionData).empty,
        .paragraphs = std.ArrayList(core.ParagraphData).empty,
        .lists = std.ArrayList(core.ListData).empty,
        .list_items = std.ArrayList(core.ListItemData).empty,
        .tables = std.ArrayList(core.TableData).empty,
        .rows = std.ArrayList(core.TableRowData).empty,
        .cells = std.ArrayList(core.TableCellData).empty,
        .blocks = std.ArrayList(core.BlockData).empty,
        .texts = std.ArrayList(core.TextData).empty,
        .links = std.ArrayList(core.LinkData).empty,
        .references = std.ArrayList(core.ReferenceData).empty,
        .anchors = std.ArrayList(core.AnchorData).empty,
        .emphases = std.ArrayList(core.EmphasisData).empty,
        .strongs = std.ArrayList(core.StrongData).empty,
        .roots = std.ArrayList(core.NodeIndex).empty,
    };

    for (doc.blocks) |*node| try ctx.roots.append(a, try lowerNode(&ctx, node));

    return .{
        .arena = arena_state,
        .arena_owner = backing,
        .metadata = try lowerMetadata(a, doc.metadata),
        .roots = ctx.roots.items,
        .node_child_refs = ctx.node_child_refs.items,
        .inline_child_refs = ctx.inline_child_refs.items,
        .nodes = ctx.nodes.items,
        .inlines = ctx.inlines.items,
        .sections = ctx.sections.items,
        .paragraphs = ctx.paragraphs.items,
        .lists = ctx.lists.items,
        .list_items = ctx.list_items.items,
        .tables = ctx.tables.items,
        .rows = ctx.rows.items,
        .cells = ctx.cells.items,
        .blocks = ctx.blocks.items,
        .texts = ctx.texts.items,
        .links = ctx.links.items,
        .references = ctx.references.items,
        .anchors = ctx.anchors.items,
        .emphases = ctx.emphases.items,
        .strongs = ctx.strongs.items,
    };
}

const LowerCtx = struct {
    a: std.mem.Allocator,
    nodes: std.ArrayList(core.NodeRef),
    inlines: std.ArrayList(core.InlineRef),
    node_child_refs: std.ArrayList(core.NodeIndex),
    inline_child_refs: std.ArrayList(core.InlineIndex),
    sections: std.ArrayList(core.SectionData),
    paragraphs: std.ArrayList(core.ParagraphData),
    lists: std.ArrayList(core.ListData),
    list_items: std.ArrayList(core.ListItemData),
    tables: std.ArrayList(core.TableData),
    rows: std.ArrayList(core.TableRowData),
    cells: std.ArrayList(core.TableCellData),
    blocks: std.ArrayList(core.BlockData),
    texts: std.ArrayList(core.TextData),
    links: std.ArrayList(core.LinkData),
    references: std.ArrayList(core.ReferenceData),
    anchors: std.ArrayList(core.AnchorData),
    emphases: std.ArrayList(core.EmphasisData),
    strongs: std.ArrayList(core.StrongData),
    roots: std.ArrayList(core.NodeIndex),
};

fn lowerNode(ctx: *LowerCtx, node: *const author.Node) LowerError!core.NodeIndex {
    return switch (node.*) {
        .section => |*s| lowerSection(ctx, s),
        .paragraph => |*p| lowerParagraph(ctx, p),
        .list => |*l| lowerList(ctx, l),
        .table => |*t| lowerTable(ctx, t),
        .block_node => |*b| lowerBlock(ctx, b),
        .inline_node => error.InvalidChildType,
        .diagnostic => error.InvalidChildType,
    };
}

fn lowerSection(ctx: *LowerCtx, s: *const author.Section) LowerError!core.NodeIndex {
    const span = try lowerNodeChildren(ctx, s.children);
    try ctx.sections.append(ctx.a, .{
        .metadata = try lowerMetadata(ctx.a, s.metadata),
        .title = try dupeOptStr(ctx.a, s.title),
        .first_child_ref = span.first,
        .child_count = span.count,
    });
    return appendNode(ctx, .section, idx(ctx.sections.items.len));
}

fn lowerParagraph(ctx: *LowerCtx, p: *const author.Paragraph) LowerError!core.NodeIndex {
    const span = try lowerInlineChildren(ctx, p.content);
    try ctx.paragraphs.append(ctx.a, .{ .first_child_ref = span.first, .child_count = span.count });
    return appendNode(ctx, .paragraph, idx(ctx.paragraphs.items.len));
}

fn lowerList(ctx: *LowerCtx, l: *const author.List) LowerError!core.NodeIndex {
    var item_refs = std.ArrayList(core.NodeIndex).empty;
    defer item_refs.deinit(ctx.a);
    for (l.items) |*item| try item_refs.append(ctx.a, try lowerListItem(ctx, item));

    const first = if (item_refs.items.len > 0) @as(?core.ChildRefIndex, @intCast(ctx.node_child_refs.items.len)) else null;
    try ctx.node_child_refs.appendSlice(ctx.a, item_refs.items);
    try ctx.lists.append(ctx.a, .{ .kind = l.kind, .first_child_ref = first, .child_count = @intCast(item_refs.items.len) });
    return appendNode(ctx, .list, idx(ctx.lists.items.len));
}

fn lowerListItem(ctx: *LowerCtx, item: *const author.ListItem) LowerError!core.NodeIndex {
    const span = try lowerNodeChildren(ctx, item.children);
    try ctx.list_items.append(ctx.a, .{ .first_child_ref = span.first, .child_count = span.count });
    return appendNode(ctx, .list_item, idx(ctx.list_items.items.len));
}

fn lowerTable(ctx: *LowerCtx, t: *const author.Table) LowerError!core.NodeIndex {
    var row_refs = std.ArrayList(core.NodeIndex).empty;
    defer row_refs.deinit(ctx.a);
    for (t.rows) |*row| try row_refs.append(ctx.a, try lowerTableRow(ctx, row));

    const first = if (row_refs.items.len > 0) @as(?core.ChildRefIndex, @intCast(ctx.node_child_refs.items.len)) else null;
    try ctx.node_child_refs.appendSlice(ctx.a, row_refs.items);
    try ctx.tables.append(ctx.a, .{ .first_child_ref = first, .child_count = @intCast(row_refs.items.len) });
    return appendNode(ctx, .table, idx(ctx.tables.items.len));
}

fn lowerTableRow(ctx: *LowerCtx, row: *const author.TableRow) LowerError!core.NodeIndex {
    var cell_refs = std.ArrayList(core.NodeIndex).empty;
    defer cell_refs.deinit(ctx.a);
    for (row.cells) |*cell| try cell_refs.append(ctx.a, try lowerTableCell(ctx, cell));

    const first = if (cell_refs.items.len > 0) @as(?core.ChildRefIndex, @intCast(ctx.node_child_refs.items.len)) else null;
    try ctx.node_child_refs.appendSlice(ctx.a, cell_refs.items);
    try ctx.rows.append(ctx.a, .{ .first_child_ref = first, .child_count = @intCast(cell_refs.items.len) });
    return appendNode(ctx, .table_row, idx(ctx.rows.items.len));
}

fn lowerTableCell(ctx: *LowerCtx, cell: *const author.TableCell) LowerError!core.NodeIndex {
    const span = try lowerNodeChildren(ctx, cell.children);
    try ctx.cells.append(ctx.a, .{ .first_child_ref = span.first, .child_count = span.count });
    return appendNode(ctx, .table_cell, idx(ctx.cells.items.len));
}

fn lowerBlock(ctx: *LowerCtx, b: *const author.Block) LowerError!core.NodeIndex {
    const span = try lowerNodeChildren(ctx, b.children);
    try ctx.blocks.append(ctx.a, .{
        .metadata = try lowerMetadata(ctx.a, b.metadata),
        .first_child_ref = span.first,
        .child_count = span.count,
    });
    return appendNode(ctx, .block, idx(ctx.blocks.items.len));
}

fn lowerInline(ctx: *LowerCtx, inline_ptr: *const author.Inline) LowerError!core.InlineIndex {
    switch (inline_ptr.*) {
        .text => |t| {
            try ctx.texts.append(ctx.a, .{ .value = try ctx.a.dupe(u8, t) });
            return appendInline(ctx, .text, idx(ctx.texts.items.len));
        },
        .link => |*l| {
            const label_idx = if (l.label) |label| try lowerInline(ctx, &.{ .text = label }) else null;
            try ctx.links.append(ctx.a, .{ .target = try ctx.a.dupe(u8, l.target), .label = label_idx });
            return appendInline(ctx, .link, idx(ctx.links.items.len));
        },
        .reference => |*r| {
            const label_idx = if (r.label) |label| try lowerInline(ctx, &.{ .text = label }) else null;
            try ctx.references.append(ctx.a, .{ .target = try ctx.a.dupe(u8, r.target), .label = label_idx });
            return appendInline(ctx, .reference, idx(ctx.references.items.len));
        },
        .anchor => |*a| {
            try ctx.anchors.append(ctx.a, .{ .name = try ctx.a.dupe(u8, a.name) });
            return appendInline(ctx, .anchor, idx(ctx.anchors.items.len));
        },
        .emphasis => |children| {
            const span = try lowerInlineChildren(ctx, children);
            try ctx.emphases.append(ctx.a, .{ .first_child_ref = span.first, .child_count = span.count });
            return appendInline(ctx, .emphasis, idx(ctx.emphases.items.len));
        },
        .strong => |children| {
            const span = try lowerInlineChildren(ctx, children);
            try ctx.strongs.append(ctx.a, .{ .first_child_ref = span.first, .child_count = span.count });
            return appendInline(ctx, .strong, idx(ctx.strongs.items.len));
        },
    }
}

fn lowerNodeChildren(ctx: *LowerCtx, children: []const author.Node) LowerError!struct { first: ?core.ChildRefIndex, count: u32 } {
    if (children.len == 0) return .{ .first = null, .count = 0 };
    var child_refs = std.ArrayList(core.NodeIndex).empty;
    defer child_refs.deinit(ctx.a);
    for (children) |*child| try child_refs.append(ctx.a, try lowerNode(ctx, child));

    const first: core.ChildRefIndex = @intCast(ctx.node_child_refs.items.len);
    try ctx.node_child_refs.appendSlice(ctx.a, child_refs.items);
    return .{ .first = first, .count = @intCast(child_refs.items.len) };
}

fn lowerInlineChildren(ctx: *LowerCtx, children: []const author.Inline) LowerError!struct { first: ?core.InlineChildRefIndex, count: u32 } {
    if (children.len == 0) return .{ .first = null, .count = 0 };
    var child_refs = std.ArrayList(core.InlineIndex).empty;
    defer child_refs.deinit(ctx.a);
    for (children) |*child| try child_refs.append(ctx.a, try lowerInline(ctx, child));

    const first: core.InlineChildRefIndex = @intCast(ctx.inline_child_refs.items.len);
    try ctx.inline_child_refs.appendSlice(ctx.a, child_refs.items);
    return .{ .first = first, .count = @intCast(child_refs.items.len) };
}

fn appendNode(ctx: *LowerCtx, tag: core.NodeTag, index: u32) LowerError!core.NodeIndex {
    const out: core.NodeIndex = @intCast(ctx.nodes.items.len);
    try ctx.nodes.append(ctx.a, .{ .tag = tag, .index = index });
    return out;
}

fn appendInline(ctx: *LowerCtx, tag: core.InlineTag, index: u32) LowerError!core.InlineIndex {
    const out: core.InlineIndex = @intCast(ctx.inlines.items.len);
    try ctx.inlines.append(ctx.a, .{ .tag = tag, .index = index });
    return out;
}

fn lowerMetadata(a: std.mem.Allocator, m: author.Metadata) LowerError!core.Metadata {
    const id = if (m.id) |v| try a.dupe(u8, v) else null;
    const title = if (m.title) |v| try a.dupe(u8, v) else null;

    var roles: []const []const u8 = &.{};
    if (m.roles.len > 0) {
        const out = try a.alloc([]const u8, m.roles.len);
        for (m.roles, 0..) |role, i| out[i] = try a.dupe(u8, role);
        roles = out;
    }

    var attrs: []const core.KVPair = &.{};
    if (m.attrs.len > 0) {
        const out = try a.alloc(core.KVPair, m.attrs.len);
        for (m.attrs, 0..) |attr, i| {
            out[i] = .{ .key = try a.dupe(u8, attr.key), .value = try a.dupe(u8, attr.value) };
        }
        attrs = out;
    }

    return .{ .id = id, .title = title, .roles = roles, .attrs = attrs };
}

fn dupeOptStr(a: std.mem.Allocator, s: ?[]const u8) LowerError!?[]const u8 {
    if (s) |v| return try a.dupe(u8, v);
    return null;
}

fn idx(len: usize) u32 {
    return @intCast(len - 1);
}
