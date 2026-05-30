const std = @import("std");
const author = @import("author_ir.zig");
const arena = @import("arena_ir.zig");

const NodeIndex = arena.NodeIndex;
const InlineIndex = arena.InlineIndex;

pub const LowerError = std.mem.Allocator.Error;

pub fn lower(backing: std.mem.Allocator, doc: *const author.Document) !arena.DocumentArena {
    var ar = std.heap.ArenaAllocator.init(backing);
    errdefer ar.deinit();

    const a = ar.allocator();

    var nodes = std.ArrayList(arena.NodeEntry).empty;
    var inlines = std.ArrayList(arena.InlineEntry).empty;
    var sections = std.ArrayList(arena.SectionData).empty;
    var paragraphs = std.ArrayList(arena.ParagraphData).empty;
    var lists = std.ArrayList(arena.ListData).empty;
    var list_items = std.ArrayList(arena.ListItemData).empty;
    var tables = std.ArrayList(arena.TableData).empty;
    var rows = std.ArrayList(arena.TableRowData).empty;
    var cells = std.ArrayList(arena.TableCellData).empty;
    var blocks = std.ArrayList(arena.BlockData).empty;
    var texts = std.ArrayList(arena.TextData).empty;
    var links = std.ArrayList(arena.LinkData).empty;
    var references = std.ArrayList(arena.ReferenceData).empty;
    var anchors = std.ArrayList(arena.AnchorData).empty;
    var emphases = std.ArrayList(arena.EmphasisData).empty;
    var strongs = std.ArrayList(arena.StrongData).empty;
    var diagnostics = std.ArrayList(arena.Diagnostic).empty;
    var roots = std.ArrayList(arena.NodeIndex).empty;

    const arena_meta = try lowerMetadata(a, doc.metadata);

    for (doc.blocks) |*node_ptr| {
        const root_idx = try lowerNode(&.{ .a = a, .nodes = &nodes, .inlines = &inlines, .sections = &sections, .paragraphs = &paragraphs, .lists = &lists, .list_items = &list_items, .tables = &tables, .rows = &rows, .cells = &cells, .blocks = &blocks, .texts = &texts, .links = &links, .references = &references, .anchors = &anchors, .emphases = &emphases, .strongs = &strongs, .diagnostics = &diagnostics }, node_ptr);
        try roots.append(a, root_idx);
    }

    return .{
        .arena = ar,
        .metadata = arena_meta,
        .nodes = nodes.items,
        .inlines = inlines.items,
        .sections = sections.items,
        .paragraphs = paragraphs.items,
        .lists = lists.items,
        .list_items = list_items.items,
        .tables = tables.items,
        .rows = rows.items,
        .cells = cells.items,
        .blocks = blocks.items,
        .texts = texts.items,
        .links = links.items,
        .references = references.items,
        .anchors = anchors.items,
        .emphases = emphases.items,
        .strongs = strongs.items,
        .diagnostics = diagnostics.items,
        .roots = roots.items,
    };
}

const LowerCtx = struct {
    a: std.mem.Allocator,
    nodes: *std.ArrayList(arena.NodeEntry),
    inlines: *std.ArrayList(arena.InlineEntry),
    sections: *std.ArrayList(arena.SectionData),
    paragraphs: *std.ArrayList(arena.ParagraphData),
    lists: *std.ArrayList(arena.ListData),
    list_items: *std.ArrayList(arena.ListItemData),
    tables: *std.ArrayList(arena.TableData),
    rows: *std.ArrayList(arena.TableRowData),
    cells: *std.ArrayList(arena.TableCellData),
    blocks: *std.ArrayList(arena.BlockData),
    texts: *std.ArrayList(arena.TextData),
    links: *std.ArrayList(arena.LinkData),
    references: *std.ArrayList(arena.ReferenceData),
    anchors: *std.ArrayList(arena.AnchorData),
    emphases: *std.ArrayList(arena.EmphasisData),
    strongs: *std.ArrayList(arena.StrongData),
    diagnostics: *std.ArrayList(arena.Diagnostic),
};

fn lowerNode(ctx: *const LowerCtx, node: *const author.Node) LowerError!NodeIndex {
    switch (node.*) {
        .section => |*s| return lowerSection(ctx, s),
        .paragraph => |*p| return lowerParagraph(ctx, p),
        .list => |*l| return lowerList(ctx, l),
        .table => |*t| return lowerTable(ctx, t),
        .block_node => |*b| return lowerBlock(ctx, b),
        .inline_node => |*i| {
            _ = try lowerInline(ctx, i);
            @panic("inline node at block level - caller should handle");
        },
        .diagnostic => |*d| return lowerDiagnostic(ctx, d),
    }
}

fn lowerSection(ctx: *const LowerCtx, s: *const author.Section) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (s.children) |*child| {
        _ = try lowerNode(ctx, child);
    }
    const child_count = childCount(ctx.nodes, first);

    try ctx.sections.append(ctx.a, .{
        .metadata = try lowerMetadata(ctx.a, s.metadata),
        .title = try dupeOptStr(ctx.a, s.title),
        .first_child = if (child_count > 0) first else null,
        .child_count = child_count,
    });
    return try appendNode(ctx, .section, idx(ctx.sections));
}

fn lowerParagraph(ctx: *const LowerCtx, p: *const author.Paragraph) LowerError!NodeIndex {
    const first = firstIdx(ctx.inlines);
    for (p.content) |*inline_ptr| {
        _ = try lowerInline(ctx, inline_ptr);
    }
    const inline_count = childCount(ctx.inlines, first);

    try ctx.paragraphs.append(ctx.a, .{
        .first_inline = if (inline_count > 0) first else null,
        .inline_count = inline_count,
    });
    return try appendNode(ctx, .paragraph, idx(ctx.paragraphs));
}

fn lowerList(ctx: *const LowerCtx, l: *const author.List) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (l.items) |*item| {
        _ = try lowerListItem(ctx, item);
    }
    const item_count = childCount(ctx.nodes, first);

    try ctx.lists.append(ctx.a, .{
        .kind = l.kind,
        .first_item = if (item_count > 0) first else null,
        .item_count = item_count,
    });
    return try appendNode(ctx, .list, idx(ctx.lists));
}

fn lowerListItem(ctx: *const LowerCtx, item: *const author.ListItem) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (item.children) |*child| {
        _ = try lowerNode(ctx, child);
    }
    const child_count = childCount(ctx.nodes, first);

    try ctx.list_items.append(ctx.a, .{
        .first_child = if (child_count > 0) first else null,
        .child_count = child_count,
    });
    return try appendNode(ctx, .list_item, idx(ctx.list_items));
}

fn lowerTable(ctx: *const LowerCtx, t: *const author.Table) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (t.rows) |*row| {
        _ = try lowerTableRow(ctx, row);
    }
    const row_count = childCount(ctx.nodes, first);

    try ctx.tables.append(ctx.a, .{
        .first_row = if (row_count > 0) first else null,
        .row_count = row_count,
    });
    return try appendNode(ctx, .table, idx(ctx.tables));
}

fn lowerTableRow(ctx: *const LowerCtx, row: *const author.TableRow) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (row.cells) |*cell| {
        _ = try lowerTableCell(ctx, cell);
    }
    const cell_count = childCount(ctx.nodes, first);

    try ctx.rows.append(ctx.a, .{
        .first_cell = if (cell_count > 0) first else null,
        .cell_count = cell_count,
    });
    return try appendNode(ctx, .table_row, idx(ctx.rows));
}

fn lowerTableCell(ctx: *const LowerCtx, cell: *const author.TableCell) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (cell.children) |*child| {
        _ = try lowerNode(ctx, child);
    }
    const child_count = childCount(ctx.nodes, first);

    try ctx.cells.append(ctx.a, .{
        .first_child = if (child_count > 0) first else null,
        .child_count = child_count,
    });
    return try appendNode(ctx, .table_cell, idx(ctx.cells));
}

fn lowerBlock(ctx: *const LowerCtx, b: *const author.Block) LowerError!NodeIndex {
    const first = firstIdx(ctx.nodes);
    for (b.children) |*child| {
        _ = try lowerNode(ctx, child);
    }
    const child_count = childCount(ctx.nodes, first);

    try ctx.blocks.append(ctx.a, .{
        .metadata = try lowerMetadata(ctx.a, b.metadata),
        .first_child = if (child_count > 0) first else null,
        .child_count = child_count,
    });
    return try appendNode(ctx, .block, idx(ctx.blocks));
}

fn lowerDiagnostic(ctx: *const LowerCtx, d: *const author.Diagnostic) LowerError!NodeIndex {
    try ctx.diagnostics.append(ctx.a, .{
        .message = try ctx.a.dupe(u8, d.message),
    });
    const idx_val = idx(ctx.diagnostics);
    try ctx.nodes.append(ctx.a, .{ .tag = .block, .index = idx_val });
    return @intCast(ctx.nodes.items.len - 1);
}

fn lowerInline(ctx: *const LowerCtx, inline_ptr: *const author.Inline) LowerError!InlineIndex {
    switch (inline_ptr.*) {
        .text => |t| {
            try ctx.texts.append(ctx.a, .{ .value = try ctx.a.dupe(u8, t) });
            return try appendInline(ctx, .text, idx(ctx.texts));
        },
        .link => |*l| {
            const label_idx: ?InlineIndex = if (l.label) |_| try lowerLabelInline(ctx, l.label.?) else null;
            try ctx.links.append(ctx.a, .{
                .target = try ctx.a.dupe(u8, l.target),
                .label = label_idx,
            });
            return try appendInline(ctx, .link, idx(ctx.links));
        },
        .reference => |*r| {
            const label_idx: ?InlineIndex = if (r.label) |_| try lowerLabelInline(ctx, r.label.?) else null;
            try ctx.references.append(ctx.a, .{
                .target = try ctx.a.dupe(u8, r.target),
                .label = label_idx,
            });
            return try appendInline(ctx, .reference, idx(ctx.references));
        },
        .anchor => |*a| {
            try ctx.anchors.append(ctx.a, .{ .name = try ctx.a.dupe(u8, a.name) });
            return try appendInline(ctx, .anchor, idx(ctx.anchors));
        },
        .emphasis => |content| {
            const first = firstIdx(ctx.inlines);
            for (content) |*c| {
                _ = try lowerInline(ctx, c);
            }
            const inline_count = childCount(ctx.inlines, first);
            try ctx.emphases.append(ctx.a, .{
                .first_inline = if (inline_count > 0) first else null,
                .inline_count = inline_count,
            });
            return try appendInline(ctx, .emphasis, idx(ctx.emphases));
        },
        .strong => |content| {
            const first = firstIdx(ctx.inlines);
            for (content) |*c| {
                _ = try lowerInline(ctx, c);
            }
            const inline_count = childCount(ctx.inlines, first);
            try ctx.strongs.append(ctx.a, .{
                .first_inline = if (inline_count > 0) first else null,
                .inline_count = inline_count,
            });
            return try appendInline(ctx, .strong, idx(ctx.strongs));
        },
    }
}

fn lowerLabelInline(ctx: *const LowerCtx, label: []const u8) LowerError!InlineIndex {
    try ctx.texts.append(ctx.a, .{ .value = try ctx.a.dupe(u8, label) });
    return try appendInline(ctx, .text, idx(ctx.texts));
}

fn lowerMetadata(a: std.mem.Allocator, m: author.Metadata) !arena.Metadata {
    const id: ?[]const u8 = if (m.id) |v| try a.dupe(u8, v) else null;
    const title: ?[]const u8 = if (m.title) |v| try a.dupe(u8, v) else null;

    var roles: []const []const u8 = &.{};
    if (m.roles.len > 0) {
        const r = try a.alloc([]const u8, m.roles.len);
        for (m.roles, 0..) |role, i| {
            r[i] = try a.dupe(u8, role);
        }
        roles = r;
    }

    var attrs: []const arena.KVPair = &.{};
    if (m.attrs.len > 0) {
        const at = try a.alloc(arena.KVPair, m.attrs.len);
        for (m.attrs, 0..) |attr, i| {
            at[i] = .{
                .key = try a.dupe(u8, attr.key),
                .value = try a.dupe(u8, attr.value),
            };
        }
        attrs = at;
    }

    return .{
        .id = id,
        .title = title,
        .roles = roles,
        .attrs = attrs,
    };
}

fn dupeOptStr(a: std.mem.Allocator, s: ?[]const u8) !?[]const u8 {
    if (s) |v| return try a.dupe(u8, v);
    return null;
}

fn firstIdx(list: anytype) u32 {
    return @intCast(list.items.len);
}

fn childCount(list: anytype, first: u32) u32 {
    const len: u32 = @intCast(list.items.len);
    return len - first;
}

fn idx(list: anytype) u32 {
    const len: u32 = @intCast(list.items.len);
    return len - 1;
}

fn appendNode(ctx: *const LowerCtx, tag: arena.NodeTag, index: u32) LowerError!NodeIndex {
    const node_idx: NodeIndex = @intCast(ctx.nodes.items.len);
    try ctx.nodes.append(ctx.a, .{ .tag = tag, .index = index });
    return node_idx;
}

fn appendInline(ctx: *const LowerCtx, tag: arena.InlineTag, index: u32) LowerError!InlineIndex {
    const inline_idx: InlineIndex = @intCast(ctx.inlines.items.len);
    try ctx.inlines.append(ctx.a, .{ .tag = tag, .index = index });
    return inline_idx;
}
