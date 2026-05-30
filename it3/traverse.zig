const std = @import("std");
const arena = @import("arena_ir.zig");

pub const Walker = struct {
    allocator: std.mem.Allocator,
    doc: arena.DocumentArena,
    stack: std.ArrayList(StackFrame),

    const StackFrame = struct {
        kind: FrameKind,
        first: u32,
        count: u32,
        cursor: u32,
    };

    const FrameKind = enum { nodes, inlines };

    pub fn init(allocator: std.mem.Allocator, doc: arena.DocumentArena) Walker {
        return .{
            .allocator = allocator,
            .doc = doc,
            .stack = std.ArrayList(StackFrame).empty,
        };
    }

    pub fn deinit(self: *Walker) void {
        self.stack.deinit(self.allocator);
    }

    pub fn walkDocument(self: *Walker) !void {
        for (self.doc.roots) |root_idx| {
            const entry = self.doc.nodes[root_idx];
            try self.pushNodeChildren(entry);
        }
    }

    pub fn walkFromNode(self: *Walker, entry: arena.NodeEntry) !void {
        try self.pushNodeChildren(entry);
    }

    pub fn pushNodeChildren(self: *Walker, entry: arena.NodeEntry) !void {
        switch (entry.tag) {
            .section => {
                const s = self.doc.sections[entry.index];
                if (s.child_count > 0 and s.first_child != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = s.first_child.?,
                        .count = s.child_count,
                        .cursor = 0,
                    });
                }
            },
            .paragraph => {
                const p = self.doc.paragraphs[entry.index];
                if (p.inline_count > 0 and p.first_inline != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .inlines,
                        .first = p.first_inline.?,
                        .count = p.inline_count,
                        .cursor = 0,
                    });
                }
            },
            .list => {
                const l = self.doc.lists[entry.index];
                if (l.item_count > 0 and l.first_item != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = l.first_item.?,
                        .count = l.item_count,
                        .cursor = 0,
                    });
                }
            },
            .list_item => {
                const li = self.doc.list_items[entry.index];
                if (li.child_count > 0 and li.first_child != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = li.first_child.?,
                        .count = li.child_count,
                        .cursor = 0,
                    });
                }
            },
            .table => {
                const t = self.doc.tables[entry.index];
                if (t.row_count > 0 and t.first_row != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = t.first_row.?,
                        .count = t.row_count,
                        .cursor = 0,
                    });
                }
            },
            .table_row => {
                const r = self.doc.rows[entry.index];
                if (r.cell_count > 0 and r.first_cell != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = r.first_cell.?,
                        .count = r.cell_count,
                        .cursor = 0,
                    });
                }
            },
            .table_cell => {
                const c = self.doc.cells[entry.index];
                if (c.child_count > 0 and c.first_child != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = c.first_child.?,
                        .count = c.child_count,
                        .cursor = 0,
                    });
                }
            },
            .block => {
                const b = self.doc.blocks[entry.index];
                if (b.child_count > 0 and b.first_child != null) {
                    try self.stack.append(self.allocator, .{
                        .kind = .nodes,
                        .first = b.first_child.?,
                        .count = b.child_count,
                        .cursor = 0,
                    });
                }
            },
        }
    }

    pub fn next(self: *Walker) ?WalkEvent {
        while (self.stack.items.len > 0) {
            var frame = &self.stack.items[self.stack.items.len - 1];
            if (frame.cursor >= frame.count) {
                _ = self.stack.pop();
                continue;
            }

            const idx = frame.first + frame.cursor;
            frame.cursor += 1;

            switch (frame.kind) {
                .nodes => {
                    const entry = self.doc.nodes[idx];
                    return .{ .node = .{ .index = idx, .entry = entry } };
                },
                .inlines => {
                    const entry = self.doc.inlines[idx];
                    return .{ .inline_el = .{ .index = idx, .entry = entry } };
                },
            }
        }
        return null;
    }
};

pub const WalkEvent = union(enum) {
    node: NodeRef,
    inline_el: InlineRef,
};

pub const NodeRef = struct {
    index: arena.NodeIndex,
    entry: arena.NodeEntry,
};

pub const InlineRef = struct {
    index: arena.InlineIndex,
    entry: arena.InlineEntry,
};

pub fn collectAnchors(allocator: std.mem.Allocator, doc: arena.DocumentArena) !arena.AnchorData {
    _ = allocator;
    _ = doc;
    return undefined;
}

pub fn findUnresolvedReferences(allocator: std.mem.Allocator, doc: arena.DocumentArena) ![]arena.ReferenceData {
    _ = allocator;
    _ = doc;
    return &.{};
}

pub fn countNodesByTag(doc: arena.DocumentArena, tag: arena.NodeTag) usize {
    var count: usize = 0;
    for (doc.nodes) |entry| {
        if (entry.tag == tag) count += 1;
    }
    return count;
}

pub fn countInlinesByTag(doc: arena.DocumentArena, tag: arena.InlineTag) usize {
    var count: usize = 0;
    for (doc.inlines) |entry| {
        if (entry.tag == tag) count += 1;
    }
    return count;
}
