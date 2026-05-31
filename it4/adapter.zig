const std = @import("std");
const author = @import("author_ir.zig");
const build = @import("build_ir.zig");
const core = @import("core_ir.zig");
const lower = @import("lower.zig");

pub const ParsedKVPair = struct {
    key: []const u8,
    value: []const u8,
};

pub const ParsedMetadata = struct {
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    attrs: []const ParsedKVPair = &.{},
};

pub const ParsedInline = union(enum) {
    text: []const u8,
    link: struct { target: []const u8, label: ?[]const u8 = null },
    reference: struct { target: []const u8, label: ?[]const u8 = null },
    anchor: []const u8,
    emphasis: []const ParsedInline,
    strong: []const ParsedInline,
};

pub const ParsedListItem = struct {
    children: []const ParsedNode,
};

pub const ParsedTableCell = struct {
    children: []const ParsedNode,
};

pub const ParsedTableRow = struct {
    cells: []const ParsedTableCell,
};

pub const ParsedNode = union(enum) {
    section: struct { metadata: ParsedMetadata = .{}, title: ?[]const u8 = null, children: []const ParsedNode },
    paragraph: []const ParsedInline,
    list: struct { kind: author.ListKind, items: []const ParsedListItem },
    table: []const ParsedTableRow,
    block: struct { metadata: ParsedMetadata = .{}, children: []const ParsedNode },
};

pub const ParsedDocument = struct {
    metadata: ParsedMetadata = .{},
    blocks: []const ParsedNode,
};

pub const Event = union(enum) {
    begin_section: struct { id: ?[]const u8 = null, title: []const u8 },
    end_section,
    begin_block: ParsedMetadata,
    end_block,
    begin_list: author.ListKind,
    end_list,
    begin_list_item,
    end_list_item,
    begin_table,
    end_table,
    begin_table_row,
    end_table_row,
    begin_table_cell,
    end_table_cell,
    begin_paragraph,
    end_paragraph,
    begin_emphasis,
    end_emphasis,
    begin_strong,
    end_strong,
    text: []const u8,
    link: struct { target: []const u8, label: ?[]const u8 = null },
    reference: struct { target: []const u8, label: ?[]const u8 = null },
    anchor: []const u8,
};

pub fn toAuthorDocument(allocator: std.mem.Allocator, parsed: ParsedDocument) !author.Document {
    var temp = std.heap.ArenaAllocator.init(allocator);
    defer temp.deinit();

    var b = build.Builder.init(allocator);
    const meta = try convertMetadata(&b, parsed.metadata);
    const blocks = try convertNodes(&b, temp.allocator(), parsed.blocks);
    return try b.document(meta, blocks);
}

pub fn lowerParsedDocument(allocator: std.mem.Allocator, parsed: ParsedDocument) !core.Document {
    var temp = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer temp.deinit();

    var doc = try toAuthorDocument(temp.allocator(), parsed);
    defer doc.deinit(temp.allocator());
    return try lower.lower(allocator, &doc);
}

pub fn lowerEventStream(allocator: std.mem.Allocator, metadata: ParsedMetadata, events: []const Event) !core.Document {
    var temp = std.heap.ArenaAllocator.init(allocator);
    defer temp.deinit();
    const ta = temp.allocator();

    const SectionBuilder = struct {
        metadata: ParsedMetadata,
        title: []const u8,
        children: std.ArrayList(ParsedNode),
    };

    const BlockBuilder = struct {
        metadata: ParsedMetadata,
        children: std.ArrayList(ParsedNode),
    };

    const ListBuilder = struct {
        kind: author.ListKind,
        items: std.ArrayList(ParsedListItem),
    };

    const ListItemBuilder = struct {
        children: std.ArrayList(ParsedNode),
    };

    const TableBuilder = struct {
        rows: std.ArrayList(ParsedTableRow),
    };

    const RowBuilder = struct {
        cells: std.ArrayList(ParsedTableCell),
    };

    const CellBuilder = struct {
        children: std.ArrayList(ParsedNode),
    };

    const InlineContainer = struct {
        kind: enum { emphasis, strong },
        items: std.ArrayList(ParsedInline),
    };

    var roots = std.ArrayList(ParsedNode).empty;
    var sections = std.ArrayList(SectionBuilder).empty;
    var blocks = std.ArrayList(BlockBuilder).empty;
    var lists = std.ArrayList(ListBuilder).empty;
    var list_items = std.ArrayList(ListItemBuilder).empty;
    var tables = std.ArrayList(TableBuilder).empty;
    var rows = std.ArrayList(RowBuilder).empty;
    var cells = std.ArrayList(CellBuilder).empty;
    var paragraph_inlines = std.ArrayList(ParsedInline).empty;
    var inline_stack = std.ArrayList(InlineContainer).empty;
    var paragraph_active = false;

    const appendNode = struct {
        fn push(
            ta_alloc: std.mem.Allocator,
            node: ParsedNode,
            roots_list: *std.ArrayList(ParsedNode),
            section_list: *std.ArrayList(SectionBuilder),
            block_list: *std.ArrayList(BlockBuilder),
            list_item_list: *std.ArrayList(ListItemBuilder),
            cell_list: *std.ArrayList(CellBuilder),
        ) !void {
            if (cell_list.items.len > 0) {
                try cell_list.items[cell_list.items.len - 1].children.append(ta_alloc, node);
            } else if (list_item_list.items.len > 0) {
                try list_item_list.items[list_item_list.items.len - 1].children.append(ta_alloc, node);
            } else if (block_list.items.len > 0) {
                try block_list.items[block_list.items.len - 1].children.append(ta_alloc, node);
            } else if (section_list.items.len > 0) {
                try section_list.items[section_list.items.len - 1].children.append(ta_alloc, node);
            } else {
                try roots_list.append(ta_alloc, node);
            }
        }
    }.push;

    const appendInline = struct {
        fn push(
            ta_alloc: std.mem.Allocator,
            inline_val: ParsedInline,
            paragraph: *std.ArrayList(ParsedInline),
            stack: *std.ArrayList(InlineContainer),
            paragraph_is_active: bool,
        ) !void {
            if (!paragraph_is_active) return error.InvalidEventStream;
            if (stack.items.len > 0) {
                try stack.items[stack.items.len - 1].items.append(ta_alloc, inline_val);
            } else {
                try paragraph.append(ta_alloc, inline_val);
            }
        }
    }.push;

    for (events) |event| {
        switch (event) {
            .begin_section => |s| {
                try sections.append(ta, .{ .metadata = .{ .id = s.id }, .title = s.title, .children = .empty });
            },
            .end_section => {
                const finished = sections.pop().?;
                const child_slice = try ta.dupe(ParsedNode, finished.children.items);
                const node: ParsedNode = .{ .section = .{ .metadata = finished.metadata, .title = finished.title, .children = child_slice } };
                try appendNode(ta, node, &roots, &sections, &blocks, &list_items, &cells);
            },
            .begin_block => |meta| {
                try blocks.append(ta, .{ .metadata = meta, .children = .empty });
            },
            .end_block => {
                const finished = blocks.pop().?;
                const child_slice = try ta.dupe(ParsedNode, finished.children.items);
                const node: ParsedNode = .{ .block = .{ .metadata = finished.metadata, .children = child_slice } };
                try appendNode(ta, node, &roots, &sections, &blocks, &list_items, &cells);
            },
            .begin_list => |kind| {
                try lists.append(ta, .{ .kind = kind, .items = .empty });
            },
            .end_list => {
                const finished = lists.pop().?;
                const items = try ta.dupe(ParsedListItem, finished.items.items);
                const node: ParsedNode = .{ .list = .{ .kind = finished.kind, .items = items } };
                try appendNode(ta, node, &roots, &sections, &blocks, &list_items, &cells);
            },
            .begin_list_item => {
                try list_items.append(ta, .{ .children = .empty });
            },
            .end_list_item => {
                const finished = list_items.pop().?;
                const children = try ta.dupe(ParsedNode, finished.children.items);
                try lists.items[lists.items.len - 1].items.append(ta, .{ .children = children });
            },
            .begin_table => {
                try tables.append(ta, .{ .rows = .empty });
            },
            .end_table => {
                const finished = tables.pop().?;
                const rows_slice = try ta.dupe(ParsedTableRow, finished.rows.items);
                const node: ParsedNode = .{ .table = rows_slice };
                try appendNode(ta, node, &roots, &sections, &blocks, &list_items, &cells);
            },
            .begin_table_row => {
                try rows.append(ta, .{ .cells = .empty });
            },
            .end_table_row => {
                const finished = rows.pop().?;
                const cells_slice = try ta.dupe(ParsedTableCell, finished.cells.items);
                try tables.items[tables.items.len - 1].rows.append(ta, .{ .cells = cells_slice });
            },
            .begin_table_cell => {
                try cells.append(ta, .{ .children = .empty });
            },
            .end_table_cell => {
                const finished = cells.pop().?;
                const children = try ta.dupe(ParsedNode, finished.children.items);
                try rows.items[rows.items.len - 1].cells.append(ta, .{ .children = children });
            },
            .begin_paragraph => {
                paragraph_active = true;
                paragraph_inlines.clearRetainingCapacity();
                inline_stack.clearRetainingCapacity();
            },
            .end_paragraph => {
                if (inline_stack.items.len != 0) return error.InvalidEventStream;
                const inline_slice = try ta.dupe(ParsedInline, paragraph_inlines.items);
                const node: ParsedNode = .{ .paragraph = inline_slice };
                try appendNode(ta, node, &roots, &sections, &blocks, &list_items, &cells);
                paragraph_active = false;
            },
            .begin_emphasis => {
                if (!paragraph_active) return error.InvalidEventStream;
                try inline_stack.append(ta, .{ .kind = .emphasis, .items = .empty });
            },
            .end_emphasis => {
                const finished = inline_stack.pop().?;
                if (finished.kind != .emphasis) return error.InvalidEventStream;
                const inline_slice = try ta.dupe(ParsedInline, finished.items.items);
                try appendInline(ta, .{ .emphasis = inline_slice }, &paragraph_inlines, &inline_stack, paragraph_active);
            },
            .begin_strong => {
                if (!paragraph_active) return error.InvalidEventStream;
                try inline_stack.append(ta, .{ .kind = .strong, .items = .empty });
            },
            .end_strong => {
                const finished = inline_stack.pop().?;
                if (finished.kind != .strong) return error.InvalidEventStream;
                const inline_slice = try ta.dupe(ParsedInline, finished.items.items);
                try appendInline(ta, .{ .strong = inline_slice }, &paragraph_inlines, &inline_stack, paragraph_active);
            },
            .text => |text| {
                try appendInline(ta, .{ .text = text }, &paragraph_inlines, &inline_stack, paragraph_active);
            },
            .link => |link| {
                try appendInline(ta, .{ .link = .{ .target = link.target, .label = link.label } }, &paragraph_inlines, &inline_stack, paragraph_active);
            },
            .reference => |reference| {
                try appendInline(ta, .{ .reference = .{ .target = reference.target, .label = reference.label } }, &paragraph_inlines, &inline_stack, paragraph_active);
            },
            .anchor => |anchor| {
                try appendInline(ta, .{ .anchor = anchor }, &paragraph_inlines, &inline_stack, paragraph_active);
            },
        }
    }

    if (paragraph_active or inline_stack.items.len != 0 or sections.items.len != 0 or blocks.items.len != 0 or lists.items.len != 0 or list_items.items.len != 0 or tables.items.len != 0 or rows.items.len != 0 or cells.items.len != 0) return error.InvalidEventStream;

    const parsed = ParsedDocument{ .metadata = metadata, .blocks = try ta.dupe(ParsedNode, roots.items) };
    return try lowerParsedDocument(allocator, parsed);
}

const AdaptError = anyerror;

fn convertMetadata(b: *build.Builder, parsed: ParsedMetadata) AdaptError!author.Metadata {
    const attrs = if (parsed.attrs.len == 0) &.{} else blk: {
        const out = try b.allocator.alloc(author.KVPair, parsed.attrs.len);
        for (parsed.attrs, 0..) |attr, i| out[i] = .{ .key = attr.key, .value = attr.value };
        break :blk out;
    };
    defer if (parsed.attrs.len > 0) b.allocator.free(attrs);
    return try b.metadata(.{ .id = parsed.id, .title = parsed.title, .roles = parsed.roles, .attrs = attrs });
}

fn convertNodes(b: *build.Builder, temp: std.mem.Allocator, nodes: []const ParsedNode) AdaptError![]author.Node {
    const out = try temp.alloc(author.Node, nodes.len);
    for (nodes, 0..) |node, i| out[i] = try convertNode(b, temp, node);
    return out;
}

fn convertNode(b: *build.Builder, temp: std.mem.Allocator, node: ParsedNode) AdaptError!author.Node {
    return switch (node) {
        .section => |s| try b.section(try convertMetadata(b, s.metadata), s.title, try convertNodes(b, temp, s.children)),
        .paragraph => |content| try b.paragraph(try convertInlines(b, temp, content)),
        .list => |list| try b.list(list.kind, try convertListItems(b, temp, list.items)),
        .table => |rows| try b.table(try convertRows(b, temp, rows)),
        .block => |blk| try b.genericBlock(try convertMetadata(b, blk.metadata), try convertNodes(b, temp, blk.children)),
    };
}

fn convertInlines(b: *build.Builder, temp: std.mem.Allocator, inlines: []const ParsedInline) AdaptError![]author.Inline {
    const out = try temp.alloc(author.Inline, inlines.len);
    for (inlines, 0..) |inline_val, i| out[i] = try convertInline(b, temp, inline_val);
    return out;
}

fn convertInline(b: *build.Builder, temp: std.mem.Allocator, inline_val: ParsedInline) AdaptError!author.Inline {
    return switch (inline_val) {
        .text => |text| try b.inlineText(text),
        .link => |link| try b.inlineLink(link.target, link.label),
        .reference => |reference| try b.inlineReference(reference.target, reference.label),
        .anchor => |name| try b.inlineAnchor(name),
        .emphasis => |content| try b.inlineEmphasis(try convertInlines(b, temp, content)),
        .strong => |content| try b.inlineStrong(try convertInlines(b, temp, content)),
    };
}

fn convertListItems(b: *build.Builder, temp: std.mem.Allocator, items: []const ParsedListItem) AdaptError![]author.ListItem {
    const out = try temp.alloc(author.ListItem, items.len);
    for (items, 0..) |item, i| out[i] = try b.listItem(try convertNodes(b, temp, item.children));
    return out;
}

fn convertRows(b: *build.Builder, temp: std.mem.Allocator, rows: []const ParsedTableRow) AdaptError![]author.TableRow {
    const out = try temp.alloc(author.TableRow, rows.len);
    for (rows, 0..) |row, i| out[i] = try b.tableRow(try convertCells(b, temp, row.cells));
    return out;
}

fn convertCells(b: *build.Builder, temp: std.mem.Allocator, cells: []const ParsedTableCell) AdaptError![]author.TableCell {
    const out = try temp.alloc(author.TableCell, cells.len);
    for (cells, 0..) |cell, i| out[i] = try b.tableCell(try convertNodes(b, temp, cell.children));
    return out;
}
