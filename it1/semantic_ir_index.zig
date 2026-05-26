const std = @import("std");
const semantic_ir = @import("semantic_ir.zig");

const Document = semantic_ir.Document;
const Node = semantic_ir.Node;
const NodeId = semantic_ir.NodeId;

pub const Index = struct {
    names: std.StringHashMapUnmanaged(NodeId) = .empty,
    footnotes: []const NodeId,
    bibliography: []const NodeId,
    includes: []const NodeId,

    pub fn deinit(self: *Index, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
        allocator.free(self.footnotes);
        allocator.free(self.bibliography);
        allocator.free(self.includes);
        self.* = undefined;
    }

    pub fn lookup(self: *const Index, name: []const u8) ?NodeId {
        return self.names.get(name);
    }
};

pub fn build(allocator: std.mem.Allocator, doc: Document) !Index {
    try semantic_ir.validate(doc);

    var names: std.StringHashMapUnmanaged(NodeId) = .empty;
    errdefer names.deinit(allocator);

    var footnotes = std.ArrayListUnmanaged(NodeId).empty;
    errdefer footnotes.deinit(allocator);

    var bibliography = std.ArrayListUnmanaged(NodeId).empty;
    errdefer bibliography.deinit(allocator);

    var includes = std.ArrayListUnmanaged(NodeId).empty;
    errdefer includes.deinit(allocator);

    for (doc.nodes, 0..) |node, i| {
        const id: NodeId = @intCast(i);

        if (node.name) |name| {
            try names.put(allocator, name, id);
        }

        switch (node.kind) {
            .footnote_def => try footnotes.append(allocator, id),
            .bibliography_def => try bibliography.append(allocator, id),
            .include => try includes.append(allocator, id),
            else => {},
        }
    }

    return .{
        .names = names,
        .footnotes = try footnotes.toOwnedSlice(allocator),
        .bibliography = try bibliography.toOwnedSlice(allocator),
        .includes = try includes.toOwnedSlice(allocator),
    };
}

pub fn firstTextChild(doc: Document, id: NodeId) ?[]const u8 {
    const node = doc.nodes[id];
    for (node.children) |child| {
        const child_node = doc.nodes[child];
        if (child_node.kind == .text and child_node.text != null) return child_node.text.?;
    }
    return null;
}

pub fn isDefinitionNode(kind: Node.Kind) bool {
    return switch (kind) {
        .footnote_def, .bibliography_def => true,
        else => false,
    };
}

test "build index collects names and semantic definitions" {
    var builder = semantic_ir.Builder.init(std.testing.allocator);
    defer builder.deinit();

    const heading_text = try builder.text("Indexed doc");
    const heading = try builder.block(.heading, &.{heading_text}, "intro");
    const foot_text = try builder.text("Footnote body");
    const foot_para = try builder.block(.paragraph, &.{foot_text}, null);
    const foot_def = try builder.block(.footnote_def, &.{foot_para}, "fn-1");
    const bib_text = try builder.text("Knuth");
    const bib_para = try builder.block(.paragraph, &.{bib_text}, null);
    const bib_def = try builder.block(.bibliography_def, &.{bib_para}, "bib-knuth84");
    const include = try builder.block(.include, &.{}, null);
    const doc_node = try builder.block(.document, &.{ heading, foot_def, bib_def, include }, null);

    try builder.edge(.include, include, .{ .node = foot_def });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    var index = try build(std.testing.allocator, doc);
    defer index.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?NodeId, heading), index.lookup("intro"));
    try std.testing.expectEqual(@as(?NodeId, foot_def), index.lookup("fn-1"));
    try std.testing.expectEqual(@as(usize, 1), index.footnotes.len);
    try std.testing.expectEqual(@as(usize, 1), index.bibliography.len);
    try std.testing.expectEqual(@as(usize, 1), index.includes.len);
    try std.testing.expectEqualStrings("Indexed doc", firstTextChild(doc, heading).?);
    try std.testing.expect(isDefinitionNode(doc.nodes[foot_def].kind));
    try std.testing.expect(isDefinitionNode(doc.nodes[bib_def].kind));
}
