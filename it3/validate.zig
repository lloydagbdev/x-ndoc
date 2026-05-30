const std = @import("std");
const arena = @import("arena_ir.zig");

pub fn validate(allocator: std.mem.Allocator, doc: arena.DocumentArena) ![]arena.Diagnostic {
    var diags: std.ArrayList(arena.Diagnostic) = .empty;
    errdefer {
        for (diags.items) |d| allocator.free(d.message);
        diags.deinit(allocator);
    }

    var anchors = try collectAnchors(allocator, doc);
    defer {
        var it = anchors.keyIterator();
        while (it.next()) |key_ptr| {
            allocator.free(key_ptr.*);
        }
        anchors.deinit();
    }

    for (doc.nodes, 0..) |entry, node_idx| {
        const ni: arena.NodeIndex = @intCast(node_idx);
        switch (entry.tag) {
            .section => {
                const s = doc.sections[entry.index];
                if (s.child_count == 0) {
                    try pushDiag(&diags, allocator, "warn", ni, "Section has no children");
                }
                if (s.title == null and s.metadata.title == null) {
                    try pushDiag(&diags, allocator, "warn", ni, "Section has no title");
                }
            },
            .paragraph => {
                const p = doc.paragraphs[entry.index];
                if (p.inline_count == 0) {
                    try pushDiag(&diags, allocator, "info", ni, "Paragraph is empty");
                }
            },
            .list => {
                const l = doc.lists[entry.index];
                if (l.item_count == 0) {
                    try pushDiag(&diags, allocator, "warn", ni, "List has no items");
                }
            },
            .list_item => {
                const li = doc.list_items[entry.index];
                if (li.child_count == 0) {
                    try pushDiag(&diags, allocator, "warn", ni, "List item has no children");
                }
            },
            .table => {
                const t = doc.tables[entry.index];
                if (t.row_count == 0) {
                    try pushDiag(&diags, allocator, "err", ni, "Table has no rows");
                } else if (t.row_count > 0) {
                    _ = try validateTableConsistency(&diags, allocator, doc, ni, &t);
                }
            },
            .table_row => {},
            .table_cell => {
                const tc = doc.cells[entry.index];
                if (tc.child_count == 0) {
                    try pushDiag(&diags, allocator, "info", ni, "Table cell is empty");
                }
            },
            .block => {
                const b = doc.blocks[entry.index];
                if (b.child_count == 0) {
                    try pushDiag(&diags, allocator, "warn", ni, "Block has no children");
                }
            },
        }

        try validateInlineReferences(&diags, allocator, doc, &anchors, ni, entry);
    }

    return diags.toOwnedSlice(allocator);
}

fn collectAnchors(allocator: std.mem.Allocator, doc: arena.DocumentArena) !std.StringHashMap(void) {
    var map = std.StringHashMap(void).init(allocator);
    errdefer map.deinit();

    for (doc.inlines) |entry| {
        if (entry.tag == .anchor) {
            const a = doc.anchors[entry.index];
            const name = try allocator.dupe(u8, a.name);
            try map.put(name, {});
        }
    }

    for (doc.nodes) |entry| {
        switch (entry.tag) {
            .section => {
                if (doc.sections[entry.index].metadata.id) |id| {
                    const name = try allocator.dupe(u8, id);
                    try map.put(name, {});
                }
            },
            .block => {
                if (doc.blocks[entry.index].metadata.id) |id| {
                    const name = try allocator.dupe(u8, id);
                    try map.put(name, {});
                }
            },
            else => {},
        }
    }

    return map;
}

fn validateTableConsistency(
    diags: *std.ArrayList(arena.Diagnostic),
    allocator: std.mem.Allocator,
    doc: arena.DocumentArena,
    table_idx: arena.NodeIndex,
    tbl: *const arena.TableData,
) !void {
    _ = table_idx;
    const rows = arena.childSlice(doc, tbl.first_row.?, tbl.row_count);

    var expected_cells: ?u32 = null;
    for (rows) |row_entry| {
        if (row_entry.tag != .table_row) continue;
        const row = doc.rows[row_entry.index];
        if (expected_cells == null) {
            expected_cells = row.cell_count;
        } else if (row.cell_count != expected_cells.?) {
            try pushDiag(diags, allocator, "warn", 0, "Inconsistent cell count in table row");
        }
    }
}

fn validateInlineReferences(
    diags: *std.ArrayList(arena.Diagnostic),
    allocator: std.mem.Allocator,
    doc: arena.DocumentArena,
    anchors: *const std.StringHashMap(void),
    node_idx: arena.NodeIndex,
    node_entry: arena.NodeEntry,
) !void {
    var seen_refs = std.StringHashMap(void).init(allocator);
    defer seen_refs.deinit();

    switch (node_entry.tag) {
        .paragraph => {
            const p = doc.paragraphs[node_entry.index];
            try checkRefsInInlines(diags, allocator, doc, anchors, &seen_refs, node_idx, p.first_inline, p.inline_count);
        },
        .block => {}, // block children are nodes, not inlines
        .list_item => {}, // list item children are nodes
        .table_cell => {}, // table cell children are nodes
        .section => {}, // section children are nodes
        else => {},
    }
}

fn checkRefsInInlines(
    diags: *std.ArrayList(arena.Diagnostic),
    allocator: std.mem.Allocator,
    doc: arena.DocumentArena,
    anchors: *const std.StringHashMap(void),
    seen_refs: *std.StringHashMap(void),
    node_idx: arena.NodeIndex,
    first: ?arena.InlineIndex,
    count: u32,
) !void {
    if (count == 0 or first == null) return;
    const inline_slice = arena.childInlineSlice(doc, first.?, count);

    for (inline_slice) |entry| {
        switch (entry.tag) {
            .reference => {
                const r = doc.references[entry.index];
                if (!anchors.contains(r.target)) {
                    const unresolved_msg = try std.fmt.allocPrint(allocator, "Unresolved reference '{s}'", .{r.target});
                    try pushDiag(diags, allocator, "err", node_idx, unresolved_msg);
                    allocator.free(unresolved_msg);
                } else {
                    try seen_refs.put(try allocator.dupe(u8, r.target), {});
                }
            },
            .emphasis => {
                const e = doc.emphases[entry.index];
                try checkRefsInInlines(diags, allocator, doc, anchors, seen_refs, node_idx, e.first_inline, e.inline_count);
            },
            .strong => {
                const s = doc.strongs[entry.index];
                try checkRefsInInlines(diags, allocator, doc, anchors, seen_refs, node_idx, s.first_inline, s.inline_count);
            },
            else => {},
        }
    }
}

fn pushDiag(
    diags: *std.ArrayList(arena.Diagnostic),
    allocator: std.mem.Allocator,
    level: []const u8,
    node_idx: arena.NodeIndex,
    msg_root: []const u8,
) !void {
    const msg = try std.fmt.allocPrint(allocator, "[{s}] node {d}: {s}", .{ level, node_idx, msg_root });
    errdefer allocator.free(msg);
    try diags.append(allocator, .{ .message = msg });
}
