const std = @import("std");
const core = @import("core_ir.zig");

pub const WalkEvent = union(enum) {
    node: struct { index: core.NodeIndex, entry: core.NodeRef },
    inline_el: struct { index: core.InlineIndex, entry: core.InlineRef },
};

pub const Walker = struct {
    allocator: std.mem.Allocator,
    doc: core.Document,
    stack: std.ArrayList(Frame),

    const Frame = union(enum) {
        node_list: struct { children: []const core.NodeIndex, cursor: usize },
        inline_list: struct { children: []const core.InlineIndex, cursor: usize },
        single_inline: core.InlineIndex,
    };

    pub fn init(allocator: std.mem.Allocator, doc: core.Document) Walker {
        return .{ .allocator = allocator, .doc = doc, .stack = std.ArrayList(Frame).empty };
    }

    pub fn deinit(self: *Walker) void {
        self.stack.deinit(self.allocator);
    }

    pub fn walkDocument(self: *Walker) !void {
        try self.stack.append(self.allocator, .{ .node_list = .{ .children = self.doc.roots, .cursor = 0 } });
    }

    pub fn pushNodeChildren(self: *Walker, entry: core.NodeRef) !void {
        switch (entry.tag) {
            .section => try pushNodeSpan(self, self.doc.sections[entry.index].first_child_ref, self.doc.sections[entry.index].child_count),
            .paragraph => try pushInlineSpan(self, self.doc.paragraphs[entry.index].first_child_ref, self.doc.paragraphs[entry.index].child_count),
            .list => try pushNodeSpan(self, self.doc.lists[entry.index].first_child_ref, self.doc.lists[entry.index].child_count),
            .list_item => try pushNodeSpan(self, self.doc.list_items[entry.index].first_child_ref, self.doc.list_items[entry.index].child_count),
            .table => try pushNodeSpan(self, self.doc.tables[entry.index].first_child_ref, self.doc.tables[entry.index].child_count),
            .table_row => try pushNodeSpan(self, self.doc.rows[entry.index].first_child_ref, self.doc.rows[entry.index].child_count),
            .table_cell => try pushNodeSpan(self, self.doc.cells[entry.index].first_child_ref, self.doc.cells[entry.index].child_count),
            .block => try pushNodeSpan(self, self.doc.blocks[entry.index].first_child_ref, self.doc.blocks[entry.index].child_count),
        }
    }

    pub fn pushInlineChildren(self: *Walker, entry: core.InlineRef) !void {
        switch (entry.tag) {
            .text, .anchor => {},
            .link => {
                const l = self.doc.links[entry.index];
                if (l.label) |label_idx| try self.stack.append(self.allocator, .{ .single_inline = label_idx });
            },
            .reference => {
                const r = self.doc.references[entry.index];
                if (r.label) |label_idx| try self.stack.append(self.allocator, .{ .single_inline = label_idx });
            },
            .emphasis => try pushInlineSpan(self, self.doc.emphases[entry.index].first_child_ref, self.doc.emphases[entry.index].child_count),
            .strong => try pushInlineSpan(self, self.doc.strongs[entry.index].first_child_ref, self.doc.strongs[entry.index].child_count),
        }
    }

    fn pushNodeSpan(self: *Walker, first: ?core.ChildRefIndex, count: u32) !void {
        if (first == null or count == 0) return;
        try self.stack.append(self.allocator, .{ .node_list = .{ .children = core.nodeChildren(self.doc, first.?, count), .cursor = 0 } });
    }

    fn pushInlineSpan(self: *Walker, first: ?core.InlineChildRefIndex, count: u32) !void {
        if (first == null or count == 0) return;
        try self.stack.append(self.allocator, .{ .inline_list = .{ .children = core.inlineChildren(self.doc, first.?, count), .cursor = 0 } });
    }

    pub fn next(self: *Walker) ?WalkEvent {
        while (self.stack.items.len > 0) {
            const top_idx = self.stack.items.len - 1;
            switch (self.stack.items[top_idx]) {
                .node_list => |*frame| {
                    if (frame.cursor >= frame.children.len) {
                        _ = self.stack.pop();
                        continue;
                    }
                    const idx = frame.children[frame.cursor];
                    frame.cursor += 1;
                    return .{ .node = .{ .index = idx, .entry = self.doc.nodes[idx] } };
                },
                .inline_list => |*frame| {
                    if (frame.cursor >= frame.children.len) {
                        _ = self.stack.pop();
                        continue;
                    }
                    const idx = frame.children[frame.cursor];
                    frame.cursor += 1;
                    return .{ .inline_el = .{ .index = idx, .entry = self.doc.inlines[idx] } };
                },
                .single_inline => |idx| {
                    _ = self.stack.pop();
                    return .{ .inline_el = .{ .index = idx, .entry = self.doc.inlines[idx] } };
                },
            }
        }
        return null;
    }
};

pub fn countNodesByTag(doc: core.Document, tag: core.NodeTag) usize {
    var n: usize = 0;
    for (doc.nodes) |entry| {
        if (entry.tag == tag) n += 1;
    }
    return n;
}

pub fn countInlinesByTag(doc: core.Document, tag: core.InlineTag) usize {
    var n: usize = 0;
    for (doc.inlines) |entry| {
        if (entry.tag == tag) n += 1;
    }
    return n;
}
