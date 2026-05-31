const std = @import("std");
const core = @import("core_ir.zig");

pub const AddRootSectionSpec = struct {
    id: ?[]const u8 = null,
    title: []const u8,
    text: []const u8,
};

pub const AddChildSectionSpec = struct {
    parent_id: []const u8,
    id: ?[]const u8 = null,
    title: []const u8,
    text: []const u8,
    position: ?usize = null,
};

pub fn cloneDocument(backing: std.mem.Allocator, doc: core.Document) !core.Document {
    const arena_state = try backing.create(std.heap.ArenaAllocator);
    errdefer backing.destroy(arena_state);
    arena_state.* = std.heap.ArenaAllocator.init(backing);
    errdefer arena_state.deinit();
    const a = arena_state.allocator();

    return .{
        .arena = arena_state,
        .arena_owner = backing,
        .metadata = try cloneMetadata(a, doc.metadata),
        .roots = try a.dupe(u32, doc.roots),
        .node_child_refs = try a.dupe(u32, doc.node_child_refs),
        .inline_child_refs = try a.dupe(u32, doc.inline_child_refs),
        .nodes = try a.dupe(core.NodeRef, doc.nodes),
        .inlines = try a.dupe(core.InlineRef, doc.inlines),
        .sections = try cloneSections(a, doc.sections),
        .paragraphs = try a.dupe(core.ParagraphData, doc.paragraphs),
        .lists = try a.dupe(core.ListData, doc.lists),
        .list_items = try a.dupe(core.ListItemData, doc.list_items),
        .tables = try a.dupe(core.TableData, doc.tables),
        .rows = try a.dupe(core.TableRowData, doc.rows),
        .cells = try a.dupe(core.TableCellData, doc.cells),
        .blocks = try cloneBlocks(a, doc.blocks),
        .texts = try cloneTexts(a, doc.texts),
        .links = try cloneLinks(a, doc.links),
        .references = try cloneReferences(a, doc.references),
        .anchors = try cloneAnchors(a, doc.anchors),
        .emphases = try a.dupe(core.EmphasisData, doc.emphases),
        .strongs = try a.dupe(core.StrongData, doc.strongs),
    };
}

pub fn renameIdentifier(backing: std.mem.Allocator, doc: core.Document, from: []const u8, to: []const u8) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();

    for (out.sections) |*section| {
        if (section.metadata.id != null and std.mem.eql(u8, section.metadata.id.?, from)) {
            section.metadata.id = try out.arena.allocator().dupe(u8, to);
        }
    }
    for (out.blocks) |*block| {
        if (block.metadata.id != null and std.mem.eql(u8, block.metadata.id.?, from)) {
            block.metadata.id = try out.arena.allocator().dupe(u8, to);
        }
    }
    for (out.anchors) |*anchor| {
        if (std.mem.eql(u8, anchor.name, from)) {
            anchor.name = try out.arena.allocator().dupe(u8, to);
        }
    }
    for (out.references) |*reference| {
        if (std.mem.eql(u8, reference.target, from)) {
            reference.target = try out.arena.allocator().dupe(u8, to);
        }
    }
    return out;
}

pub fn retitleSection(backing: std.mem.Allocator, doc: core.Document, section_id: []const u8, new_title: []const u8) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();

    for (out.sections) |*section| {
        if (section.metadata.id != null and std.mem.eql(u8, section.metadata.id.?, section_id)) {
            section.title = try out.arena.allocator().dupe(u8, new_title);
            return out;
        }
    }
    return out;
}

pub fn replaceText(backing: std.mem.Allocator, doc: core.Document, from: []const u8, to: []const u8) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();

    for (out.texts) |*text| {
        if (std.mem.eql(u8, text.value, from)) {
            text.value = try out.arena.allocator().dupe(u8, to);
        }
    }
    return out;
}

pub fn updateLinkTarget(backing: std.mem.Allocator, doc: core.Document, from: []const u8, to: []const u8) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();

    for (out.links) |*link| {
        if (std.mem.eql(u8, link.target, from)) {
            link.target = try out.arena.allocator().dupe(u8, to);
        }
    }
    return out;
}

pub fn retargetReference(backing: std.mem.Allocator, doc: core.Document, from: []const u8, to: []const u8) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();

    for (out.references) |*reference| {
        if (std.mem.eql(u8, reference.target, from)) {
            reference.target = try out.arena.allocator().dupe(u8, to);
        }
    }
    return out;
}

pub fn addRootSection(backing: std.mem.Allocator, doc: core.Document, spec: AddRootSectionSpec) !core.Document {
    return insertRootSectionAt(backing, doc, doc.roots.len, spec);
}

pub fn insertRootSectionAt(backing: std.mem.Allocator, doc: core.Document, position: usize, spec: AddRootSectionSpec) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();
    const a = out.arena.allocator();
    const insert_at = @min(position, out.roots.len);

    const text_idx: core.InlineIndex = @intCast(out.inlines.len);
    const new_texts = try a.alloc(core.TextData, out.texts.len + 1);
    @memcpy(new_texts[0..out.texts.len], out.texts);
    new_texts[out.texts.len] = .{ .value = try a.dupe(u8, spec.text) };
    out.texts = new_texts;

    const new_inlines = try a.alloc(core.InlineRef, out.inlines.len + 1);
    @memcpy(new_inlines[0..out.inlines.len], out.inlines);
    new_inlines[out.inlines.len] = .{ .tag = .text, .index = @intCast(out.texts.len - 1) };
    out.inlines = new_inlines;

    const para_child_first: core.InlineChildRefIndex = @intCast(out.inline_child_refs.len);
    const new_inline_child_refs = try a.alloc(core.InlineIndex, out.inline_child_refs.len + 1);
    @memcpy(new_inline_child_refs[0..out.inline_child_refs.len], out.inline_child_refs);
    new_inline_child_refs[out.inline_child_refs.len] = text_idx;
    out.inline_child_refs = new_inline_child_refs;

    const para_payload_idx: u32 = @intCast(out.paragraphs.len);
    const new_paragraphs = try a.alloc(core.ParagraphData, out.paragraphs.len + 1);
    @memcpy(new_paragraphs[0..out.paragraphs.len], out.paragraphs);
    new_paragraphs[out.paragraphs.len] = .{ .first_child_ref = para_child_first, .child_count = 1 };
    out.paragraphs = new_paragraphs;

    const para_node_idx: core.NodeIndex = @intCast(out.nodes.len);
    const new_nodes_after_para = try a.alloc(core.NodeRef, out.nodes.len + 1);
    @memcpy(new_nodes_after_para[0..out.nodes.len], out.nodes);
    new_nodes_after_para[out.nodes.len] = .{ .tag = .paragraph, .index = para_payload_idx };
    out.nodes = new_nodes_after_para;

    const section_child_first: core.ChildRefIndex = @intCast(out.node_child_refs.len);
    const new_node_child_refs = try a.alloc(core.NodeIndex, out.node_child_refs.len + 1);
    @memcpy(new_node_child_refs[0..out.node_child_refs.len], out.node_child_refs);
    new_node_child_refs[out.node_child_refs.len] = para_node_idx;
    out.node_child_refs = new_node_child_refs;

    const section_payload_idx: u32 = @intCast(out.sections.len);
    const new_sections = try a.alloc(core.SectionData, out.sections.len + 1);
    @memcpy(new_sections[0..out.sections.len], out.sections);
    new_sections[out.sections.len] = .{
        .metadata = .{
            .id = if (spec.id) |id| try a.dupe(u8, id) else null,
            .title = null,
            .roles = &.{},
            .attrs = &.{},
        },
        .title = try a.dupe(u8, spec.title),
        .first_child_ref = section_child_first,
        .child_count = 1,
    };
    out.sections = new_sections;

    const section_node_idx: core.NodeIndex = @intCast(out.nodes.len);
    const new_nodes = try a.alloc(core.NodeRef, out.nodes.len + 1);
    @memcpy(new_nodes[0..out.nodes.len], out.nodes);
    new_nodes[out.nodes.len] = .{ .tag = .section, .index = section_payload_idx };
    out.nodes = new_nodes;

    const new_roots = try a.alloc(core.NodeIndex, out.roots.len + 1);
    @memcpy(new_roots[0..insert_at], out.roots[0..insert_at]);
    new_roots[insert_at] = section_node_idx;
    @memcpy(new_roots[insert_at + 1 ..], out.roots[insert_at..]);
    out.roots = new_roots;

    return out;
}

pub fn removeRootSectionById(backing: std.mem.Allocator, doc: core.Document, section_id: []const u8) !core.Document {
    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();
    const a = out.arena.allocator();

    var kept: usize = 0;
    for (out.roots) |root_idx| {
        const entry = out.nodes[root_idx];
        if (entry.tag == .section) {
            const section = out.sections[entry.index];
            if (section.metadata.id != null and std.mem.eql(u8, section.metadata.id.?, section_id)) continue;
        }
        kept += 1;
    }

    const new_roots = try a.alloc(core.NodeIndex, kept);
    var write_idx: usize = 0;
    for (out.roots) |root_idx| {
        const entry = out.nodes[root_idx];
        if (entry.tag == .section) {
            const section = out.sections[entry.index];
            if (section.metadata.id != null and std.mem.eql(u8, section.metadata.id.?, section_id)) continue;
        }
        new_roots[write_idx] = root_idx;
        write_idx += 1;
    }
    out.roots = new_roots;
    return out;
}

pub fn reorderRoots(backing: std.mem.Allocator, doc: core.Document, order: []const usize) !core.Document {
    if (order.len != doc.roots.len) return error.InvalidRootOrder;

    var seen = try backing.alloc(bool, order.len);
    defer backing.free(seen);
    @memset(seen, false);

    for (order) |idx| {
        if (idx >= order.len or seen[idx]) return error.InvalidRootOrder;
        seen[idx] = true;
    }

    var out = try cloneDocument(backing, doc);
    errdefer out.deinit();
    const a = out.arena.allocator();
    const new_roots = try a.alloc(core.NodeIndex, out.roots.len);
    for (order, 0..) |src_idx, i| new_roots[i] = out.roots[src_idx];
    out.roots = new_roots;
    return out;
}

pub fn removeSectionById(backing: std.mem.Allocator, doc: core.Document, section_id: []const u8) !core.Document {
    var rewrite = Rewriter.init(backing, doc) catch unreachable;
    defer rewrite.deinit();
    rewrite.remove_section_id = section_id;
    return rewrite.finish();
}

pub fn appendChildSection(backing: std.mem.Allocator, doc: core.Document, spec: AddChildSectionSpec) !core.Document {
    var rewrite = Rewriter.init(backing, doc) catch unreachable;
    defer rewrite.deinit();
    rewrite.append_child_spec = spec;
    return rewrite.finish();
}

pub fn insertChildSectionAt(backing: std.mem.Allocator, doc: core.Document, spec: AddChildSectionSpec) !core.Document {
    return appendChildSection(backing, doc, spec);
}

const Rewriter = struct {
    source: core.Document,
    arena_state: ?*std.heap.ArenaAllocator,
    arena_owner: std.mem.Allocator,
    a: std.mem.Allocator,
    remove_section_id: ?[]const u8 = null,
    append_child_spec: ?AddChildSectionSpec = null,

    roots: std.ArrayList(core.NodeIndex),
    node_child_refs: std.ArrayList(core.NodeIndex),
    inline_child_refs: std.ArrayList(core.InlineIndex),
    nodes: std.ArrayList(core.NodeRef),
    inlines: std.ArrayList(core.InlineRef),
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

    fn init(backing: std.mem.Allocator, source: core.Document) !Rewriter {
        const arena_state = try backing.create(std.heap.ArenaAllocator);
        errdefer backing.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(backing);
        return .{
            .source = source,
            .arena_state = arena_state,
            .arena_owner = backing,
            .a = arena_state.allocator(),
            .roots = .empty,
            .node_child_refs = .empty,
            .inline_child_refs = .empty,
            .nodes = .empty,
            .inlines = .empty,
            .sections = .empty,
            .paragraphs = .empty,
            .lists = .empty,
            .list_items = .empty,
            .tables = .empty,
            .rows = .empty,
            .cells = .empty,
            .blocks = .empty,
            .texts = .empty,
            .links = .empty,
            .references = .empty,
            .anchors = .empty,
            .emphases = .empty,
            .strongs = .empty,
        };
    }

    fn deinit(self: *Rewriter) void {
        if (self.arena_state) |arena_state| {
            arena_state.deinit();
            self.arena_owner.destroy(arena_state);
        }
        self.* = undefined;
    }

    const RewriteError = anyerror;

    fn finish(self: *Rewriter) RewriteError!core.Document {
        const metadata = try cloneMetadata(self.a, self.source.metadata);
        for (self.source.roots) |root_idx| {
            if (try self.copyNode(root_idx)) |new_idx| try self.roots.append(self.a, new_idx);
        }

        const arena_state = self.arena_state.?;
        self.arena_state = null;
        return .{
            .arena = arena_state,
            .arena_owner = self.arena_owner,
            .metadata = metadata,
            .roots = self.roots.items,
            .node_child_refs = self.node_child_refs.items,
            .inline_child_refs = self.inline_child_refs.items,
            .nodes = self.nodes.items,
            .inlines = self.inlines.items,
            .sections = self.sections.items,
            .paragraphs = self.paragraphs.items,
            .lists = self.lists.items,
            .list_items = self.list_items.items,
            .tables = self.tables.items,
            .rows = self.rows.items,
            .cells = self.cells.items,
            .blocks = self.blocks.items,
            .texts = self.texts.items,
            .links = self.links.items,
            .references = self.references.items,
            .anchors = self.anchors.items,
            .emphases = self.emphases.items,
            .strongs = self.strongs.items,
        };
    }

    fn copyNode(self: *Rewriter, node_idx: core.NodeIndex) RewriteError!?core.NodeIndex {
        const entry = self.source.nodes[node_idx];
        return switch (entry.tag) {
            .section => self.copySection(entry.index),
            .paragraph => self.copyParagraph(entry.index),
            .list => self.copyList(entry.index),
            .list_item => self.copyListItem(entry.index),
            .table => self.copyTable(entry.index),
            .table_row => self.copyTableRow(entry.index),
            .table_cell => self.copyTableCell(entry.index),
            .block => self.copyBlock(entry.index),
        };
    }

    fn copySection(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.sections[idx];
        if (self.remove_section_id) |target| {
            if (src.metadata.id != null and std.mem.eql(u8, src.metadata.id.?, target)) return null;
        }

        const child_first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var child_count: u32 = 0;
        if (src.first_child_ref) |first| {
            for (core.nodeChildren(self.source, first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    child_count += 1;
                }
            }
        }
        if (self.append_child_spec) |spec| {
            if (src.metadata.id != null and std.mem.eql(u8, src.metadata.id.?, spec.parent_id)) {
                const new_child = try self.makeSimpleSection(spec.id, spec.title, spec.text);
                const insert_at = if (spec.position) |pos| @min(pos, child_count) else child_count;
                const start: usize = child_first;
                if (insert_at < child_count) {
                    try self.node_child_refs.insert(self.a, start + insert_at, new_child);
                } else {
                    try self.node_child_refs.append(self.a, new_child);
                }
                child_count += 1;
            }
        }
        try self.sections.append(self.a, .{
            .metadata = try cloneMetadata(self.a, src.metadata),
            .title = if (src.title) |title| try self.a.dupe(u8, title) else null,
            .first_child_ref = if (child_count == 0) null else child_first,
            .child_count = child_count,
        });
        return try self.appendNode(.section, @intCast(self.sections.items.len - 1));
    }

    fn copyParagraph(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.paragraphs[idx];
        const first: core.InlineChildRefIndex = @intCast(self.inline_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.inlineChildren(self.source, child_first, src.child_count)) |inline_idx| {
                try self.inline_child_refs.append(self.a, try self.copyInline(inline_idx));
                count += 1;
            }
        }
        try self.paragraphs.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.paragraph, @intCast(self.paragraphs.items.len - 1));
    }

    fn copyList(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.lists[idx];
        const first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.nodeChildren(self.source, child_first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    count += 1;
                }
            }
        }
        try self.lists.append(self.a, .{ .kind = src.kind, .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.list, @intCast(self.lists.items.len - 1));
    }

    fn copyListItem(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.list_items[idx];
        const first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.nodeChildren(self.source, child_first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    count += 1;
                }
            }
        }
        try self.list_items.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.list_item, @intCast(self.list_items.items.len - 1));
    }

    fn copyTable(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.tables[idx];
        const first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.nodeChildren(self.source, child_first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    count += 1;
                }
            }
        }
        try self.tables.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.table, @intCast(self.tables.items.len - 1));
    }

    fn copyTableRow(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.rows[idx];
        const first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.nodeChildren(self.source, child_first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    count += 1;
                }
            }
        }
        try self.rows.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.table_row, @intCast(self.rows.items.len - 1));
    }

    fn copyTableCell(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.cells[idx];
        const first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.nodeChildren(self.source, child_first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    count += 1;
                }
            }
        }
        try self.cells.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.table_cell, @intCast(self.cells.items.len - 1));
    }

    fn copyBlock(self: *Rewriter, idx: u32) RewriteError!?core.NodeIndex {
        const src = self.source.blocks[idx];
        const first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        var count: u32 = 0;
        if (src.first_child_ref) |child_first| {
            for (core.nodeChildren(self.source, child_first, src.child_count)) |child_idx| {
                if (try self.copyNode(child_idx)) |new_child| {
                    try self.node_child_refs.append(self.a, new_child);
                    count += 1;
                }
            }
        }
        try self.blocks.append(self.a, .{ .metadata = try cloneMetadata(self.a, src.metadata), .first_child_ref = if (count == 0) null else first, .child_count = count });
        return try self.appendNode(.block, @intCast(self.blocks.items.len - 1));
    }

    fn copyInline(self: *Rewriter, inline_idx: core.InlineIndex) RewriteError!core.InlineIndex {
        const entry = self.source.inlines[inline_idx];
        switch (entry.tag) {
            .text => {
                try self.texts.append(self.a, .{ .value = try self.a.dupe(u8, self.source.texts[entry.index].value) });
                return try self.appendInline(.text, @intCast(self.texts.items.len - 1));
            },
            .link => {
                const src = self.source.links[entry.index];
                const label = if (src.label) |label_idx| try self.copyInline(label_idx) else null;
                try self.links.append(self.a, .{ .target = try self.a.dupe(u8, src.target), .label = label });
                return try self.appendInline(.link, @intCast(self.links.items.len - 1));
            },
            .reference => {
                const src = self.source.references[entry.index];
                const label = if (src.label) |label_idx| try self.copyInline(label_idx) else null;
                try self.references.append(self.a, .{ .target = try self.a.dupe(u8, src.target), .label = label });
                return try self.appendInline(.reference, @intCast(self.references.items.len - 1));
            },
            .anchor => {
                try self.anchors.append(self.a, .{ .name = try self.a.dupe(u8, self.source.anchors[entry.index].name) });
                return try self.appendInline(.anchor, @intCast(self.anchors.items.len - 1));
            },
            .emphasis => {
                const src = self.source.emphases[entry.index];
                const first: core.InlineChildRefIndex = @intCast(self.inline_child_refs.items.len);
                var count: u32 = 0;
                if (src.first_child_ref) |child_first| {
                    for (core.inlineChildren(self.source, child_first, src.child_count)) |child_idx| {
                        try self.inline_child_refs.append(self.a, try self.copyInline(child_idx));
                        count += 1;
                    }
                }
                try self.emphases.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
                return try self.appendInline(.emphasis, @intCast(self.emphases.items.len - 1));
            },
            .strong => {
                const src = self.source.strongs[entry.index];
                const first: core.InlineChildRefIndex = @intCast(self.inline_child_refs.items.len);
                var count: u32 = 0;
                if (src.first_child_ref) |child_first| {
                    for (core.inlineChildren(self.source, child_first, src.child_count)) |child_idx| {
                        try self.inline_child_refs.append(self.a, try self.copyInline(child_idx));
                        count += 1;
                    }
                }
                try self.strongs.append(self.a, .{ .first_child_ref = if (count == 0) null else first, .child_count = count });
                return try self.appendInline(.strong, @intCast(self.strongs.items.len - 1));
            },
        }
    }

    fn makeSimpleSection(self: *Rewriter, id: ?[]const u8, title: []const u8, text: []const u8) RewriteError!core.NodeIndex {
        try self.texts.append(self.a, .{ .value = try self.a.dupe(u8, text) });
        const text_inline = try self.appendInline(.text, @intCast(self.texts.items.len - 1));
        const para_inline_first: core.InlineChildRefIndex = @intCast(self.inline_child_refs.items.len);
        try self.inline_child_refs.append(self.a, text_inline);
        try self.paragraphs.append(self.a, .{ .first_child_ref = para_inline_first, .child_count = 1 });
        const para_node = try self.appendNode(.paragraph, @intCast(self.paragraphs.items.len - 1));
        const section_child_first: core.ChildRefIndex = @intCast(self.node_child_refs.items.len);
        try self.node_child_refs.append(self.a, para_node);
        try self.sections.append(self.a, .{
            .metadata = .{ .id = if (id) |value| try self.a.dupe(u8, value) else null, .title = null, .roles = &.{}, .attrs = &.{} },
            .title = try self.a.dupe(u8, title),
            .first_child_ref = section_child_first,
            .child_count = 1,
        });
        return try self.appendNode(.section, @intCast(self.sections.items.len - 1));
    }

    fn appendNode(self: *Rewriter, tag: core.NodeTag, index: u32) RewriteError!core.NodeIndex {
        const node_idx: core.NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(self.a, .{ .tag = tag, .index = index });
        return node_idx;
    }

    fn appendInline(self: *Rewriter, tag: core.InlineTag, index: u32) RewriteError!core.InlineIndex {
        const inline_idx: core.InlineIndex = @intCast(self.inlines.items.len);
        try self.inlines.append(self.a, .{ .tag = tag, .index = index });
        return inline_idx;
    }
};

fn cloneMetadata(a: std.mem.Allocator, meta: core.Metadata) !core.Metadata {
    const roles = if (meta.roles.len == 0) &.{} else blk: {
        const out = try a.alloc([]const u8, meta.roles.len);
        for (meta.roles, 0..) |role, i| out[i] = try a.dupe(u8, role);
        break :blk out;
    };
    const attrs = if (meta.attrs.len == 0) &.{} else blk: {
        const out = try a.alloc(core.KVPair, meta.attrs.len);
        for (meta.attrs, 0..) |attr, i| out[i] = .{ .key = try a.dupe(u8, attr.key), .value = try a.dupe(u8, attr.value) };
        break :blk out;
    };
    return .{
        .id = if (meta.id) |id| try a.dupe(u8, id) else null,
        .title = if (meta.title) |title| try a.dupe(u8, title) else null,
        .roles = roles,
        .attrs = attrs,
    };
}

fn cloneSections(a: std.mem.Allocator, items: []const core.SectionData) ![]core.SectionData {
    const out = try a.alloc(core.SectionData, items.len);
    for (items, 0..) |item, i| {
        out[i] = .{
            .metadata = try cloneMetadata(a, item.metadata),
            .title = if (item.title) |title| try a.dupe(u8, title) else null,
            .first_child_ref = item.first_child_ref,
            .child_count = item.child_count,
        };
    }
    return out;
}

fn cloneBlocks(a: std.mem.Allocator, items: []const core.BlockData) ![]core.BlockData {
    const out = try a.alloc(core.BlockData, items.len);
    for (items, 0..) |item, i| {
        out[i] = .{
            .metadata = try cloneMetadata(a, item.metadata),
            .first_child_ref = item.first_child_ref,
            .child_count = item.child_count,
        };
    }
    return out;
}

fn cloneTexts(a: std.mem.Allocator, items: []const core.TextData) ![]core.TextData {
    const out = try a.alloc(core.TextData, items.len);
    for (items, 0..) |item, i| out[i] = .{ .value = try a.dupe(u8, item.value) };
    return out;
}

fn cloneLinks(a: std.mem.Allocator, items: []const core.LinkData) ![]core.LinkData {
    const out = try a.alloc(core.LinkData, items.len);
    for (items, 0..) |item, i| out[i] = .{ .target = try a.dupe(u8, item.target), .label = item.label };
    return out;
}

fn cloneReferences(a: std.mem.Allocator, items: []const core.ReferenceData) ![]core.ReferenceData {
    const out = try a.alloc(core.ReferenceData, items.len);
    for (items, 0..) |item, i| out[i] = .{ .target = try a.dupe(u8, item.target), .label = item.label };
    return out;
}

fn cloneAnchors(a: std.mem.Allocator, items: []const core.AnchorData) ![]core.AnchorData {
    const out = try a.alloc(core.AnchorData, items.len);
    for (items, 0..) |item, i| out[i] = .{ .name = try a.dupe(u8, item.name) };
    return out;
}
