const std = @import("std");
const author = @import("author_semantic_ir.zig");
const ibig = @import("ibig_semantic_ir.zig");

const comptime_author_doc = author.Document{
    .roots = &.{.{ .node = 2 }},
    .nodes = &.{
        .{ .kind = .text, .payload = .{ .text = "Comptime authored document" } },
        .{ .kind = .paragraph, .children = &.{0} },
        .{ .kind = .document, .children = &.{1} },
    },
    .edges = &.{},
};

const ComptimePackedExample = LoweredAuthorDocument(comptime_author_doc);

pub fn main(init: std.process.Init) !void {
    _ = init;
    _ = ComptimePackedExample.document;
}

fn LoweredAuthorDocument(comptime doc: author.Document) type {
    return struct {
        const roots = lowerRoots(doc);
        const nodes = lowerNodes(doc);
        const child_ids = lowerChildIds(doc);
        const edges = lowerEdges(doc);
        const payloads = lowerPayloads(doc);
        const strings = lowerStrings(doc);

        const document = ibig.Document{
            .roots = &roots,
            .nodes = &nodes,
            .child_ids = &child_ids,
            .edges = &edges,
            .payloads = &payloads,
            .strings = &strings,
        };
    };
}

fn lowerRoots(comptime doc: author.Document) [doc.roots.len]ibig.Root {
    var out: [doc.roots.len]ibig.Root = undefined;
    for (doc.roots, 0..) |root, i| {
        out[i] = .{ .node = root.node };
    }
    return out;
}

fn lowerNodes(comptime doc: author.Document) [doc.nodes.len]ibig.Node {
    var out: [doc.nodes.len]ibig.Node = undefined;
    var child_start: u32 = 0;
    var payload_id: u32 = 0;
    for (doc.nodes, 0..) |node, i| {
        const child_len: u32 = @intCast(node.children.len);
        out[i] = .{
            .kind = node.kind,
            .children = .{ .start = child_start, .len = child_len },
            .payload = if (node.payload == null) null else payload_id,
        };
        child_start += child_len;
        if (node.payload != null) payload_id += 1;
    }
    return out;
}

fn lowerChildIds(comptime doc: author.Document) [countChildren(doc)]ibig.NodeId {
    var out: [countChildren(doc)]ibig.NodeId = undefined;
    var index: usize = 0;
    for (doc.nodes) |node| {
        for (node.children) |child| {
            out[index] = child;
            index += 1;
        }
    }
    return out;
}

fn lowerEdges(comptime doc: author.Document) [doc.edges.len]ibig.Edge {
    var out: [doc.edges.len]ibig.Edge = undefined;
    var string_start: u32 = payloadStringLen(doc);
    for (doc.edges, 0..) |edge, i| {
        out[i] = .{
            .kind = edge.kind,
            .from = edge.from,
            .to = switch (edge.to) {
                .node => |node| .{ .node = node },
                .external => |value| target: {
                    const start = string_start;
                    string_start += @intCast(value.len);
                    break :target .{ .external = .{ .start = start, .len = @intCast(value.len) } };
                },
            },
        };
    }
    return out;
}

fn lowerPayloads(comptime doc: author.Document) [countPayloads(doc)]ibig.Payload {
    var out: [countPayloads(doc)]ibig.Payload = undefined;
    var payload_index: usize = 0;
    var string_start: u32 = 0;
    for (doc.nodes) |node| {
        if (node.payload) |payload| {
            out[payload_index] = lowerPayload(payload, &string_start);
            payload_index += 1;
        }
    }
    return out;
}

fn lowerPayload(comptime payload: author.Payload, string_start: *u32) ibig.Payload {
    return switch (payload) {
        .text => |value| .{ .text = lowerStringRef(value, string_start) },
        .name => |value| .{ .name = lowerStringRef(value, string_start) },
        .code_block => |value| .{ .code_block = .{
            .text = lowerStringRef(value.text, string_start),
            .language = if (value.language) |language| lowerStringRef(language, string_start) else null,
        } },
        .table => .{ .table = .{} },
        .table_cell => |value| .{ .table_cell = .{
            .kind = value.kind,
            .colspan = value.colspan,
            .rowspan = value.rowspan,
        } },
    };
}

fn lowerStringRef(comptime value: []const u8, string_start: *u32) ibig.StringRef {
    const start = string_start.*;
    string_start.* += @intCast(value.len);
    return .{ .start = start, .len = @intCast(value.len) };
}

fn lowerStrings(comptime doc: author.Document) [totalStringLen(doc)]u8 {
    var out: [totalStringLen(doc)]u8 = undefined;
    var index: usize = 0;
    for (doc.nodes) |node| {
        if (node.payload) |payload| copyPayloadStrings(payload, &out, &index);
    }
    for (doc.edges) |edge| {
        switch (edge.to) {
            .external => |value| copyString(value, &out, &index),
            .node => {},
        }
    }
    return out;
}

fn copyPayloadStrings(comptime payload: author.Payload, out: anytype, index: *usize) void {
    switch (payload) {
        .text => |value| copyString(value, out, index),
        .name => |value| copyString(value, out, index),
        .code_block => |value| {
            copyString(value.text, out, index);
            if (value.language) |language| copyString(language, out, index);
        },
        .table, .table_cell => {},
    }
}

fn copyString(comptime value: []const u8, out: anytype, index: *usize) void {
    @memcpy(out[index.*..][0..value.len], value);
    index.* += value.len;
}

fn countChildren(comptime doc: author.Document) usize {
    var count: usize = 0;
    for (doc.nodes) |node| count += node.children.len;
    return count;
}

fn countPayloads(comptime doc: author.Document) usize {
    var count: usize = 0;
    for (doc.nodes) |node| {
        if (node.payload != null) count += 1;
    }
    return count;
}

fn payloadStringLen(comptime doc: author.Document) u32 {
    var len: u32 = 0;
    for (doc.nodes) |node| {
        if (node.payload) |payload| len += payloadStringLenOne(payload);
    }
    return len;
}

fn payloadStringLenOne(comptime payload: author.Payload) u32 {
    return switch (payload) {
        .text => |value| @intCast(value.len),
        .name => |value| @intCast(value.len),
        .code_block => |value| @intCast(value.text.len + if (value.language) |language| language.len else 0),
        .table, .table_cell => 0,
    };
}

fn totalStringLen(comptime doc: author.Document) usize {
    var len: usize = payloadStringLen(doc);
    for (doc.edges) |edge| {
        switch (edge.to) {
            .external => |value| len += value.len,
            .node => {},
        }
    }
    return len;
}

fn exampleDocument(allocator: std.mem.Allocator) !ibig.Document {
    var builder = ExampleBuilder.init(allocator);
    errdefer builder.deinit();

    const title_text = try builder.text("Iteration 2 schema example");
    const title_name = try builder.name("intro");
    const heading = try builder.node(.heading, &.{title_text}, title_name);

    const intro_text = try builder.text("This paragraph uses ");
    const emph_text = try builder.text("emphasis");
    const emph = try builder.node(.emphasis, &.{emph_text}, null);
    const middle_text = try builder.text(", ");
    const strong_text = try builder.text("strong text");
    const strong = try builder.node(.strong, &.{strong_text}, null);
    const code = try builder.codeSpan("code_span");
    const link_label = try builder.text("external link");
    const link_ref = try builder.node(.reference, &.{link_label}, null);
    const footnote_label = try builder.text("1");
    const footnote_ref = try builder.node(.reference, &.{footnote_label}, null);
    const cite_one_label = try builder.text("knuth84");
    const cite_one = try builder.node(.reference, &.{cite_one_label}, null);
    const cite_two_label = try builder.text("lamport94");
    const cite_two = try builder.node(.reference, &.{cite_two_label}, null);
    const cite_group = try builder.node(.reference_group, &.{ cite_one, cite_two }, null);
    const paragraph_tail = try builder.text(" inside one paragraph.");
    const paragraph = try builder.node(.paragraph, &.{
        intro_text,
        emph,
        middle_text,
        strong,
        middle_text,
        code,
        middle_text,
        link_ref,
        middle_text,
        footnote_ref,
        middle_text,
        cite_group,
        paragraph_tail,
    }, null);

    const list_item_one_text = try builder.text("First list item.");
    const list_item_one_para = try builder.node(.paragraph, &.{list_item_one_text}, null);
    const list_item_one = try builder.node(.list_item, &.{list_item_one_para}, null);
    const list_item_two_text = try builder.text("Second list item.");
    const list_item_two_para = try builder.node(.paragraph, &.{list_item_two_text}, null);
    const list_item_two = try builder.node(.list_item, &.{list_item_two_para}, null);
    const list = try builder.node(.list, &.{ list_item_one, list_item_two }, null);

    const quote_text = try builder.text("Reusable quoted block for include tests.");
    const quote_para = try builder.node(.paragraph, &.{quote_text}, null);
    const quote = try builder.node(.quote, &.{quote_para}, try builder.name("shared-quote"));
    const include = try builder.node(.include, &.{}, null);

    const block_code = try builder.codeBlock("const answer = 42;", "zig");
    const code_block = try builder.node(.code_block, &.{}, block_code);

    const header_cell_text = try builder.text("Feature");
    const header_cell_para = try builder.node(.paragraph, &.{header_cell_text}, null);
    const header_cell = try builder.node(.table_cell, &.{header_cell_para}, try builder.tableCell(.header, 1, 1));
    const header_row = try builder.node(.table_row, &.{header_cell}, null);
    const table_head = try builder.node(.table_head, &.{header_row}, null);

    const body_cell_text = try builder.text("Payload table");
    const body_cell_para = try builder.node(.paragraph, &.{body_cell_text}, null);
    const body_cell = try builder.node(.table_cell, &.{body_cell_para}, try builder.tableCell(.data, 1, 1));
    const body_row = try builder.node(.table_row, &.{body_cell}, null);
    const table_body = try builder.node(.table_body, &.{body_row}, null);

    const foot_cell_text = try builder.text("All table fragments are present.");
    const foot_cell_para = try builder.node(.paragraph, &.{foot_cell_text}, null);
    const foot_cell = try builder.node(.table_cell, &.{foot_cell_para}, try builder.tableCell(.data, 1, 1));
    const foot_row = try builder.node(.table_row, &.{foot_cell}, null);
    const table_foot = try builder.node(.table_foot, &.{foot_row}, null);

    const table_payload = try builder.table(&.{.{ .alignment = .left }});
    const table = try builder.node(.table, &.{ table_head, table_body, table_foot }, table_payload);

    const xref_label = try builder.text("the intro heading");
    const xref = try builder.node(.reference, &.{xref_label}, null);
    const xref_para = try builder.node(.paragraph, &.{xref}, null);

    const footnote_text = try builder.text("Footnote definition content.");
    const footnote_para = try builder.node(.paragraph, &.{footnote_text}, null);
    const footnote_def = try builder.node(.footnote_def, &.{footnote_para}, try builder.name("fn-1"));

    const bibliography_text_one = try builder.text("Donald E. Knuth. Literate Programming. 1984.");
    const bibliography_para_one = try builder.node(.paragraph, &.{bibliography_text_one}, null);
    const bibliography_def_one = try builder.node(.bibliography_def, &.{bibliography_para_one}, try builder.name("bib-knuth84"));

    const bibliography_text_two = try builder.text("Leslie Lamport. LaTeX: A Document Preparation System. 1994.");
    const bibliography_para_two = try builder.node(.paragraph, &.{bibliography_text_two}, null);
    const bibliography_def_two = try builder.node(.bibliography_def, &.{bibliography_para_two}, try builder.name("bib-lamport94"));

    const section = try builder.node(.section, &.{
        heading,
        paragraph,
        list,
        include,
        code_block,
        table,
        xref_para,
    }, null);
    const document = try builder.node(.document, &.{ section, footnote_def, bibliography_def_one, bibliography_def_two }, null);

    try builder.root(document);
    try builder.edge(.link, link_ref, .{ .external = try builder.string("https://example.com") });
    try builder.edge(.xref, xref, .{ .node = heading });
    try builder.edge(.footnote_ref, footnote_ref, .{ .node = footnote_def });
    try builder.edge(.cite, cite_one, .{ .node = bibliography_def_one });
    try builder.edge(.cite, cite_two, .{ .node = bibliography_def_two });
    try builder.edge(.include, include, .{ .node = quote });

    return try builder.finish();
}

fn deinitDocument(allocator: std.mem.Allocator, doc: ibig.Document) void {
    for (doc.payloads) |entry| {
        switch (entry) {
            .table => |table| if (table.columns.len != 0) allocator.free(table.columns),
            else => {},
        }
    }
    allocator.free(doc.roots);
    allocator.free(doc.nodes);
    allocator.free(doc.child_ids);
    allocator.free(doc.edges);
    allocator.free(doc.payloads);
    allocator.free(doc.strings);
}

const ExampleBuilder = struct {
    allocator: std.mem.Allocator,
    roots: std.ArrayListUnmanaged(ibig.Root) = .empty,
    nodes: std.ArrayListUnmanaged(ibig.Node) = .empty,
    child_ids: std.ArrayListUnmanaged(ibig.NodeId) = .empty,
    edges: std.ArrayListUnmanaged(ibig.Edge) = .empty,
    payloads: std.ArrayListUnmanaged(ibig.Payload) = .empty,
    strings: std.ArrayListUnmanaged(u8) = .empty,

    fn init(allocator: std.mem.Allocator) ExampleBuilder {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ExampleBuilder) void {
        for (self.payloads.items) |entry| {
            switch (entry) {
                .table => |table_payload| if (table_payload.columns.len != 0) self.allocator.free(table_payload.columns),
                else => {},
            }
        }
        self.roots.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.child_ids.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.payloads.deinit(self.allocator);
        self.strings.deinit(self.allocator);
    }

    fn finish(self: *ExampleBuilder) !ibig.Document {
        const roots = try self.roots.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(roots);
        const nodes = try self.nodes.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(nodes);
        const child_ids = try self.child_ids.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(child_ids);
        const edges = try self.edges.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(edges);
        const payloads = try self.payloads.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(payloads);
        const strings = try self.strings.toOwnedSlice(self.allocator);

        self.* = .{ .allocator = self.allocator };
        return .{
            .roots = roots,
            .nodes = nodes,
            .child_ids = child_ids,
            .edges = edges,
            .payloads = payloads,
            .strings = strings,
        };
    }

    fn string(self: *ExampleBuilder, value: []const u8) !ibig.StringRef {
        const start = std.math.cast(u32, self.strings.items.len) orelse return error.StringOverflow;
        const len = std.math.cast(u32, value.len) orelse return error.StringOverflow;
        try self.strings.appendSlice(self.allocator, value);
        return .{ .start = start, .len = len };
    }

    fn children(self: *ExampleBuilder, ids: []const ibig.NodeId) !ibig.NodeRange {
        if (ids.len == 0) return .{ .start = 0, .len = 0 };
        const start = std.math.cast(u32, self.child_ids.items.len) orelse return error.ChildOverflow;
        const len = std.math.cast(u32, ids.len) orelse return error.ChildOverflow;
        try self.child_ids.appendSlice(self.allocator, ids);
        return .{ .start = start, .len = len };
    }

    fn payload(self: *ExampleBuilder, value: ibig.Payload) !ibig.PayloadId {
        const id = std.math.cast(ibig.PayloadId, self.payloads.items.len) orelse return error.PayloadOverflow;
        try self.payloads.append(self.allocator, value);
        return id;
    }

    fn name(self: *ExampleBuilder, value: []const u8) !ibig.PayloadId {
        return try self.payload(.{ .name = try self.string(value) });
    }

    fn text(self: *ExampleBuilder, value: []const u8) !ibig.NodeId {
        return try self.node(.text, &.{}, try self.payload(.{ .text = try self.string(value) }));
    }

    fn codeSpan(self: *ExampleBuilder, value: []const u8) !ibig.NodeId {
        return try self.node(.code_span, &.{}, try self.payload(.{ .text = try self.string(value) }));
    }

    fn codeBlock(self: *ExampleBuilder, value: []const u8, language: []const u8) !ibig.PayloadId {
        return try self.payload(.{ .code_block = .{
            .text = try self.string(value),
            .language = try self.string(language),
        } });
    }

    fn table(self: *ExampleBuilder, columns: []const ibig.TableColumn) !ibig.PayloadId {
        return try self.payload(.{ .table = .{
            .columns = try self.allocator.dupe(ibig.TableColumn, columns),
        } });
    }

    fn tableCell(self: *ExampleBuilder, kind: ibig.TableCell.Kind, colspan: u32, rowspan: u32) !ibig.PayloadId {
        return try self.payload(.{ .table_cell = .{
            .kind = kind,
            .colspan = colspan,
            .rowspan = rowspan,
        } });
    }

    fn node(self: *ExampleBuilder, kind: ibig.Node.Kind, child_ids: []const ibig.NodeId, maybe_payload: ?ibig.PayloadId) !ibig.NodeId {
        const id = std.math.cast(ibig.NodeId, self.nodes.items.len) orelse return error.NodeOverflow;
        try self.nodes.append(self.allocator, .{
            .kind = kind,
            .children = try self.children(child_ids),
            .payload = maybe_payload,
        });
        return id;
    }

    fn edge(self: *ExampleBuilder, kind: ibig.Edge.Kind, from: ibig.NodeId, to: ibig.Target) !void {
        try self.edges.append(self.allocator, .{ .kind = kind, .from = from, .to = to });
    }

    fn root(self: *ExampleBuilder, node_id: ibig.NodeId) !void {
        try self.roots.append(self.allocator, .{ .node = node_id });
    }
};

fn countKind(doc: ibig.Document, kind: ibig.Node.Kind) usize {
    var count: usize = 0;
    for (doc.nodes) |node| {
        if (node.kind == kind) count += 1;
    }
    return count;
}

test "authoring document lowers to packed document at comptime" {
    const doc = ComptimePackedExample.document;

    try std.testing.expectEqual(@as(usize, 1), doc.roots.len);
    try std.testing.expectEqual(ibig.Node.Kind.document, doc.nodes[doc.roots[0].node].kind);
    try std.testing.expectEqualStrings("Comptime authored document", doc.strings);
    try std.testing.expectEqual(ibig.Node.Kind.text, doc.nodes[0].kind);
    try std.testing.expectEqual(ibig.Node.Kind.paragraph, doc.nodes[1].kind);
}

test "example document uses every node kind" {
    const doc = try exampleDocument(std.testing.allocator);
    defer deinitDocument(std.testing.allocator, doc);

    try std.testing.expect(countKind(doc, .document) > 0);
    try std.testing.expect(countKind(doc, .section) > 0);
    try std.testing.expect(countKind(doc, .heading) > 0);
    try std.testing.expect(countKind(doc, .paragraph) > 0);
    try std.testing.expect(countKind(doc, .list) > 0);
    try std.testing.expect(countKind(doc, .list_item) > 0);
    try std.testing.expect(countKind(doc, .quote) > 0);
    try std.testing.expect(countKind(doc, .code_block) > 0);
    try std.testing.expect(countKind(doc, .include) > 0);
    try std.testing.expect(countKind(doc, .footnote_def) > 0);
    try std.testing.expect(countKind(doc, .bibliography_def) > 0);
    try std.testing.expect(countKind(doc, .table) > 0);
    try std.testing.expect(countKind(doc, .table_head) > 0);
    try std.testing.expect(countKind(doc, .table_body) > 0);
    try std.testing.expect(countKind(doc, .table_foot) > 0);
    try std.testing.expect(countKind(doc, .table_row) > 0);
    try std.testing.expect(countKind(doc, .table_cell) > 0);
    try std.testing.expect(countKind(doc, .text) > 0);
    try std.testing.expect(countKind(doc, .emphasis) > 0);
    try std.testing.expect(countKind(doc, .strong) > 0);
    try std.testing.expect(countKind(doc, .code_span) > 0);
    try std.testing.expect(countKind(doc, .reference) > 0);
    try std.testing.expect(countKind(doc, .reference_group) > 0);
}

test "example document uses every edge kind" {
    const doc = try exampleDocument(std.testing.allocator);
    defer deinitDocument(std.testing.allocator, doc);

    var has_link = false;
    var has_xref = false;
    var has_cite = false;
    var has_footnote_ref = false;
    var has_include = false;
    for (doc.edges) |edge| {
        switch (edge.kind) {
            .link => has_link = true,
            .xref => has_xref = true,
            .cite => has_cite = true,
            .footnote_ref => has_footnote_ref = true,
            .include => has_include = true,
        }
    }

    try std.testing.expect(has_link);
    try std.testing.expect(has_xref);
    try std.testing.expect(has_cite);
    try std.testing.expect(has_footnote_ref);
    try std.testing.expect(has_include);
}

test "authoring and packed ir share semantic kinds" {
    const author_doc = author.Document{
        .roots = &.{.{ .node = 1 }},
        .nodes = &.{
            .{ .kind = .text, .payload = .{ .text = "Authoring text" } },
            .{ .kind = .paragraph, .children = &.{0} },
        },
        .edges = &.{},
    };

    const packed_doc = ibig.Document{
        .roots = &.{.{ .node = 1 }},
        .nodes = &.{
            .{ .kind = author_doc.nodes[0].kind, .payload = 0 },
            .{ .kind = author_doc.nodes[1].kind, .children = .{ .start = 0, .len = 1 } },
        },
        .child_ids = &.{0},
        .edges = &.{},
        .payloads = &.{.{ .text = .{ .start = 0, .len = 14 } }},
        .strings = "Authoring text",
    };

    try std.testing.expectEqual(author_doc.nodes[1].kind, packed_doc.nodes[1].kind);
    try std.testing.expect(author.Node.isFragment(.section));
    try std.testing.expect(ibig.Node.isFragment(.section));
}
