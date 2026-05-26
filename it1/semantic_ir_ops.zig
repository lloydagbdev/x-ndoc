const std = @import("std");
const semantic_ir = @import("semantic_ir.zig");

const Builder = semantic_ir.Builder;
const Document = semantic_ir.Document;
const Node = semantic_ir.Node;
const NodeId = semantic_ir.NodeId;

pub fn flattenIncludes(allocator: std.mem.Allocator, doc: Document) !Document {
    try semantic_ir.validate(doc);

    var builder = Builder.init(allocator);
    errdefer builder.deinit();

    var mapping = std.AutoHashMap(NodeId, NodeId).init(allocator);
    defer mapping.deinit();

    var pending_edges = std.ArrayListUnmanaged(PendingEdge).empty;
    defer pending_edges.deinit(allocator);

    for (doc.roots) |root| {
        const cloned = try cloneExpandedNode(&builder, &mapping, &pending_edges, doc, root);
        try builder.addRoot(cloned);
    }

    for (pending_edges.items) |pending| {
        const resolved = switch (pending.to) {
            .external => |value| semantic_ir.Target{ .external = value },
            .node => |target| semantic_ir.Target{ .node = mapping.get(target) orelse target },
        };
        try builder.edge(pending.kind, pending.from, resolved);
    }

    const out = try builder.finish();
    errdefer semantic_ir.owned.deinitDocument(allocator, out);
    try semantic_ir.validate(out);
    return out;
}

pub fn collectDefinitionsToDocumentEnd(allocator: std.mem.Allocator, doc: Document) !Document {
    try semantic_ir.validate(doc);

    var builder = Builder.init(allocator);
    errdefer builder.deinit();

    var mapping = std.AutoHashMap(NodeId, NodeId).init(allocator);
    defer mapping.deinit();

    var pending_edges = std.ArrayListUnmanaged(PendingEdge).empty;
    defer pending_edges.deinit(allocator);

    var collected_footnotes = std.ArrayListUnmanaged(NodeId).empty;
    defer collected_footnotes.deinit(allocator);
    var collected_bibliography = std.ArrayListUnmanaged(NodeId).empty;
    defer collected_bibliography.deinit(allocator);

    var root_clones = std.ArrayListUnmanaged(NodeId).empty;
    defer root_clones.deinit(allocator);

    for (doc.roots) |root| {
        if (try cloneWithoutDefinitions(&builder, &mapping, &pending_edges, &collected_footnotes, &collected_bibliography, doc, root)) |cloned| {
            try root_clones.append(allocator, cloned);
        }
    }

    for (doc.nodes, 0..) |node, i| {
        if (node.kind != .footnote_def and node.kind != .bibliography_def) continue;
        _ = try cloneExpandedNode(&builder, &mapping, &pending_edges, doc, @intCast(i));
    }

    const has_single_document_root = root_clones.items.len == 1 and docNodeKind(&builder, root_clones.items[0]) == .document;
    if (has_single_document_root) {
        const doc_root = root_clones.items[0];
        const existing = builder.nodes.items[doc_root].children;
        var merged = std.ArrayListUnmanaged(NodeId).empty;
        defer merged.deinit(allocator);
        try merged.appendSlice(allocator, existing);
        for (collected_footnotes.items) |old_id| try merged.append(allocator, mapping.get(old_id).?);
        for (collected_bibliography.items) |old_id| try merged.append(allocator, mapping.get(old_id).?);
        try builder.replaceChildren(doc_root, merged.items);
    } else {
        for (root_clones.items) |root| try builder.addRoot(root);
        for (collected_footnotes.items) |old_id| try builder.addRoot(mapping.get(old_id).?);
        for (collected_bibliography.items) |old_id| try builder.addRoot(mapping.get(old_id).?);
        return try finishPending(&builder, &mapping, &pending_edges, allocator);
    }

    for (root_clones.items) |root| try builder.addRoot(root);
    return try finishPending(&builder, &mapping, &pending_edges, allocator);
}

pub fn renumberReferences(allocator: std.mem.Allocator, doc: Document) !Document {
    try semantic_ir.validate(doc);

    var footnote_numbers = std.AutoHashMap(NodeId, u32).init(allocator);
    defer footnote_numbers.deinit();
    var citation_numbers = std.AutoHashMap(NodeId, u32).init(allocator);
    defer citation_numbers.deinit();

    var next_footnote: u32 = 1;
    var next_citation: u32 = 1;
    for (doc.roots) |root| {
        try assignReferenceNumbers(doc, root, &footnote_numbers, &citation_numbers, &next_footnote, &next_citation);
    }

    var builder = Builder.init(allocator);
    errdefer builder.deinit();
    var mapping = std.AutoHashMap(NodeId, NodeId).init(allocator);
    defer mapping.deinit();
    var pending_edges = std.ArrayListUnmanaged(PendingEdge).empty;
    defer pending_edges.deinit(allocator);

    for (doc.roots) |root| {
        const cloned = try cloneRenumberedNode(&builder, &mapping, &pending_edges, doc, root, &footnote_numbers, &citation_numbers);
        try builder.addRoot(cloned);
    }

    return try finishPending(&builder, &mapping, &pending_edges, allocator);
}

const PendingEdge = struct {
    kind: semantic_ir.Edge.Kind,
    from: NodeId,
    to: semantic_ir.Target,
};

fn finishPending(
    builder: *Builder,
    mapping: *std.AutoHashMap(NodeId, NodeId),
    pending_edges: *std.ArrayListUnmanaged(PendingEdge),
    allocator: std.mem.Allocator,
) !Document {
    for (pending_edges.items) |pending| {
        const resolved = switch (pending.to) {
            .external => |value| semantic_ir.Target{ .external = value },
            .node => |target| semantic_ir.Target{ .node = mapping.get(target) orelse target },
        };
        try builder.edge(pending.kind, pending.from, resolved);
    }

    const out = try builder.finish();
    errdefer semantic_ir.owned.deinitDocument(allocator, out);
    try semantic_ir.validate(out);
    return out;
}

fn assignReferenceNumbers(
    doc: Document,
    id: NodeId,
    footnote_numbers: *std.AutoHashMap(NodeId, u32),
    citation_numbers: *std.AutoHashMap(NodeId, u32),
    next_footnote: *u32,
    next_citation: *u32,
) !void {
    const node = doc.nodes[id];

    if (node.kind == .reference) {
        if (semantic_ir.outgoingEdge(doc, id)) |edge| {
            switch (edge.kind) {
                .footnote_ref => switch (edge.to) {
                    .node => |target| if (!footnote_numbers.contains(target)) {
                        try footnote_numbers.put(target, next_footnote.*);
                        next_footnote.* += 1;
                    },
                    .external => {},
                },
                .cite => switch (edge.to) {
                    .node => |target| if (!citation_numbers.contains(target)) {
                        try citation_numbers.put(target, next_citation.*);
                        next_citation.* += 1;
                    },
                    .external => {},
                },
                else => {},
            }
        }
    }

    if (node.kind == .include) {
        const edge = semantic_ir.outgoingEdge(doc, id) orelse return;
        switch (edge.to) {
            .node => |target| try assignReferenceNumbers(doc, target, footnote_numbers, citation_numbers, next_footnote, next_citation),
            .external => {},
        }
        return;
    }

    for (node.children) |child| {
        try assignReferenceNumbers(doc, child, footnote_numbers, citation_numbers, next_footnote, next_citation);
    }
}

fn cloneWithoutDefinitions(
    builder: *Builder,
    mapping: *std.AutoHashMap(NodeId, NodeId),
    pending_edges: *std.ArrayListUnmanaged(PendingEdge),
    collected_footnotes: *std.ArrayListUnmanaged(NodeId),
    collected_bibliography: *std.ArrayListUnmanaged(NodeId),
    doc: Document,
    id: NodeId,
) !?NodeId {
    const node = doc.nodes[id];
    switch (node.kind) {
        .footnote_def => {
            try collected_footnotes.append(builder.allocator, id);
            return null;
        },
        .bibliography_def => {
            try collected_bibliography.append(builder.allocator, id);
            return null;
        },
        else => {},
    }

    if (mapping.get(id)) |existing| return existing;

    var cloned_children = std.ArrayListUnmanaged(NodeId).empty;
    defer cloned_children.deinit(builder.allocator);
    for (node.children) |child| {
        if (try cloneWithoutDefinitions(builder, mapping, pending_edges, collected_footnotes, collected_bibliography, doc, child)) |cloned| {
            try cloned_children.append(builder.allocator, cloned);
        }
    }

    const clone = if (node.kind == .text or (node.kind == .code_span and node.text != null))
        try builderTextLike(builder, node)
    else if (Node.isInline(node.kind))
        try builder.inlineNode(node.kind, cloned_children.items)
    else
        try builderBlockLike(builder, node, cloned_children.items);

    try mapping.put(id, clone);
    for (doc.edges) |edge| {
        if (edge.from != id) continue;
        try pending_edges.append(builder.allocator, .{ .kind = edge.kind, .from = clone, .to = edge.to });
    }
    return clone;
}

fn cloneRenumberedNode(
    builder: *Builder,
    mapping: *std.AutoHashMap(NodeId, NodeId),
    pending_edges: *std.ArrayListUnmanaged(PendingEdge),
    doc: Document,
    id: NodeId,
    footnote_numbers: *const std.AutoHashMap(NodeId, u32),
    citation_numbers: *const std.AutoHashMap(NodeId, u32),
) !NodeId {
    if (mapping.get(id)) |existing| return existing;

    const node = doc.nodes[id];

    if (node.kind == .reference) {
        if (semantic_ir.outgoingEdge(doc, id)) |edge| {
            switch (edge.kind) {
                .footnote_ref, .cite => {
                    const label_number = switch (edge.kind) {
                        .footnote_ref => switch (edge.to) {
                            .node => |target| footnote_numbers.get(target),
                            .external => null,
                        },
                        .cite => switch (edge.to) {
                            .node => |target| citation_numbers.get(target),
                            .external => null,
                        },
                        else => unreachable,
                    };

                    if (label_number) |number| {
                        var buffer: [32]u8 = undefined;
                        const label = try std.fmt.bufPrint(&buffer, "{d}", .{number});
                        const text = try builder.ownedText(label);
                        const clone = try builder.inlineNode(.reference, &.{text});
                        try mapping.put(id, clone);
                        try pending_edges.append(builder.allocator, .{ .kind = edge.kind, .from = clone, .to = edge.to });
                        return clone;
                    }
                },
                else => {},
            }
        }
    }

    var cloned_children = std.ArrayListUnmanaged(NodeId).empty;
    defer cloned_children.deinit(builder.allocator);
    for (node.children) |child| {
        try cloned_children.append(builder.allocator, try cloneRenumberedNode(builder, mapping, pending_edges, doc, child, footnote_numbers, citation_numbers));
    }

    const clone = if (node.kind == .text or (node.kind == .code_span and node.text != null))
        try builderTextLike(builder, node)
    else if (Node.isInline(node.kind))
        try builder.inlineNode(node.kind, cloned_children.items)
    else
        try cloneRenumberedBlock(builder, node, cloned_children.items, footnote_numbers, citation_numbers, id);

    try mapping.put(id, clone);
    for (doc.edges) |edge| {
        if (edge.from != id) continue;
        try pending_edges.append(builder.allocator, .{ .kind = edge.kind, .from = clone, .to = edge.to });
    }
    return clone;
}

fn cloneRenumberedBlock(
    builder: *Builder,
    node: Node,
    children: []const NodeId,
    footnote_numbers: *const std.AutoHashMap(NodeId, u32),
    citation_numbers: *const std.AutoHashMap(NodeId, u32),
    original_id: NodeId,
) !NodeId {
    switch (node.kind) {
        .footnote_def => if (footnote_numbers.get(original_id)) |number| {
            var buffer: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&buffer, "fn-{d}", .{number});
            return try builder.blockOwnedName(.footnote_def, children, name);
        },
        .bibliography_def => if (citation_numbers.get(original_id)) |number| {
            var buffer: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&buffer, "bib-{d}", .{number});
            return try builder.blockOwnedName(.bibliography_def, children, name);
        },
        else => {},
    }
    return try builderBlockLike(builder, node, children);
}

fn docNodeKind(builder: *Builder, id: NodeId) Node.Kind {
    return builder.nodes.items[id].kind;
}

fn cloneExpandedNode(
    builder: *Builder,
    mapping: *std.AutoHashMap(NodeId, NodeId),
    pending_edges: *std.ArrayListUnmanaged(PendingEdge),
    doc: Document,
    id: NodeId,
) !NodeId {
    if (mapping.get(id)) |existing| return existing;

    const node = doc.nodes[id];

    if (node.kind == .include) {
        const edge = semantic_ir.outgoingEdge(doc, id) orelse return error.IncludeRequiresEdge;
        return switch (edge.to) {
            .node => |target| try cloneExpandedNode(builder, mapping, pending_edges, doc, target),
            .external => blk: {
                const clone = try builder.block(.include, &.{}, node.name);
                try mapping.put(id, clone);
                try pending_edges.append(builder.allocator, .{ .kind = .include, .from = clone, .to = edge.to });
                break :blk clone;
            },
        };
    }

    var cloned_children = std.ArrayListUnmanaged(NodeId).empty;
    defer cloned_children.deinit(builder.allocator);
    for (node.children) |child| {
        try cloned_children.append(builder.allocator, try cloneExpandedNode(builder, mapping, pending_edges, doc, child));
    }

    const clone = if (node.kind == .text or (node.kind == .code_span and node.text != null))
        try builderTextLike(builder, node)
    else if (Node.isInline(node.kind))
        try builder.inlineNode(node.kind, cloned_children.items)
    else
        try builderBlockLike(builder, node, cloned_children.items);

    try mapping.put(id, clone);

    for (doc.edges) |edge| {
        if (edge.from != id or edge.kind == .include) continue;
        try pending_edges.append(builder.allocator, .{ .kind = edge.kind, .from = clone, .to = edge.to });
    }

    return clone;
}

fn builderTextLike(builder: *Builder, node: Node) !NodeId {
    return switch (node.kind) {
        .text => if (node.owns_text) try builder.ownedText(node.text orelse "") else try builder.text(node.text orelse ""),
        .code_span => if (node.owns_text) try builder.ownedCodeSpan(node.text orelse "") else try builder.codeSpan(node.text orelse ""),
        else => unreachable,
    };
}

fn builderBlockLike(builder: *Builder, node: Node, children: []const NodeId) !NodeId {
    if (node.name) |name| {
        if (node.owns_name) return try builder.blockOwnedName(node.kind, children, name);
    }
    return try builder.block(node.kind, children, node.name);
}

test "flatten includes preserves emitted html" {
    const html = @import("semantic_ir_html.zig");

    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const quote_text = try builder.text("Shared quote");
    const quote_para = try builder.block(.paragraph, &.{quote_text}, null);
    const quote = try builder.block(.quote, &.{quote_para}, "shared");
    const include = try builder.block(.include, &.{}, null);
    const section = try builder.block(.section, &.{include}, null);
    const doc_node = try builder.block(.document, &.{section}, null);

    try builder.edge(.include, include, .{ .node = quote });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    const flat = try flattenIncludes(std.testing.allocator, doc);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, flat);

    var expected: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer expected.deinit();
    var actual: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer actual.deinit();

    try html.emit(&expected.writer, doc);
    try html.emit(&actual.writer, flat);

    try std.testing.expectEqualStrings(expected.written(), actual.written());
}

test "collect definitions moves scattered definitions to document end" {
    const markdown = @import("semantic_ir_markdown.zig");

    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const foot_label = try builder.text("1");
    const foot_ref = try builder.inlineNode(.reference, &.{foot_label});
    const cite_label = try builder.text("knuth84");
    const cite_ref = try builder.inlineNode(.reference, &.{cite_label});
    const para_text = try builder.text("Body");
    const para = try builder.block(.paragraph, &.{ para_text, foot_ref, cite_ref }, null);

    const foot_body_text = try builder.text("Footnote body");
    const foot_body = try builder.block(.paragraph, &.{foot_body_text}, null);
    const foot_def = try builder.block(.footnote_def, &.{foot_body}, "fn-1");

    const bib_text = try builder.text("Knuth");
    const bib_para = try builder.block(.paragraph, &.{bib_text}, null);
    const bib_def = try builder.block(.bibliography_def, &.{bib_para}, "bib-knuth84");

    const doc_node = try builder.block(.document, &.{ foot_def, para, bib_def }, null);
    try builder.edge(.footnote_ref, foot_ref, .{ .node = foot_def });
    try builder.edge(.cite, cite_ref, .{ .node = bib_def });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    const normalized = try collectDefinitionsToDocumentEnd(std.testing.allocator, doc);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, normalized);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try markdown.emit(&out.writer, normalized);

    try std.testing.expectEqualStrings(
        "Body[^1][@knuth84]\n\n[^1]: Footnote body\n\n[@knuth84]: Knuth\n",
        out.written(),
    );
}

test "renumber references rewrites labels by first occurrence" {
    const markdown = @import("semantic_ir_markdown.zig");

    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const foot_ref_label = try builder.text("alpha");
    const foot_ref = try builder.inlineNode(.reference, &.{foot_ref_label});
    const cite_ref_label = try builder.text("knuth84");
    const cite_ref = try builder.inlineNode(.reference, &.{cite_ref_label});
    const cite_ref_two_label = try builder.text("lamport94");
    const cite_ref_two = try builder.inlineNode(.reference, &.{cite_ref_two_label});
    const cite_group = try builder.inlineNode(.reference_group, &.{ cite_ref, cite_ref_two });
    const body = try builder.text("Body");
    const para = try builder.block(.paragraph, &.{ body, foot_ref, cite_group }, null);

    const foot_text = try builder.text("Footnote");
    const foot_para = try builder.block(.paragraph, &.{foot_text}, null);
    const foot_def = try builder.block(.footnote_def, &.{foot_para}, "fn-alpha");

    const bib_one_text = try builder.text("Knuth");
    const bib_one_para = try builder.block(.paragraph, &.{bib_one_text}, null);
    const bib_one = try builder.block(.bibliography_def, &.{bib_one_para}, "bib-knuth84");
    const bib_two_text = try builder.text("Lamport");
    const bib_two_para = try builder.block(.paragraph, &.{bib_two_text}, null);
    const bib_two = try builder.block(.bibliography_def, &.{bib_two_para}, "bib-lamport94");

    const doc_node = try builder.block(.document, &.{ para, foot_def, bib_one, bib_two }, null);
    try builder.edge(.footnote_ref, foot_ref, .{ .node = foot_def });
    try builder.edge(.cite, cite_ref, .{ .node = bib_one });
    try builder.edge(.cite, cite_ref_two, .{ .node = bib_two });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    const renumbered = try renumberReferences(std.testing.allocator, doc);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, renumbered);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try markdown.emit(&out.writer, renumbered);

    try std.testing.expectEqualStrings(
        "Body[^1][@1; @2]\n\n[^1]: Footnote\n\n[@1]: Knuth\n\n[@2]: Lamport\n",
        out.written(),
    );
}
