const std = @import("std");

pub const NodeId = u32;
pub const EdgeId = u32;

pub const Document = struct {
    roots: []const NodeId,
    nodes: []const Node,
    edges: []const Edge,
};

pub const BuildError = std.mem.Allocator.Error || error{
    NodeOverflow,
};

pub const Node = struct {
    kind: Kind,
    text: ?[]const u8 = null,
    owns_text: bool = false,
    children: []const NodeId = &.{},
    name: ?[]const u8 = null,
    owns_name: bool = false,

    pub const Kind = enum {
        document,
        section,
        heading,
        paragraph,
        list,
        list_item,
        quote,
        code_block,
        include,
        footnote_def,
        bibliography_def,

        text,
        emphasis,
        strong,
        code_span,
        reference,
        reference_group,
    };

    pub fn isBlock(kind: Kind) bool {
        return switch (kind) {
            .document, .section, .heading, .paragraph, .list, .list_item, .quote, .code_block, .include, .footnote_def, .bibliography_def => true,
            else => false,
        };
    }

    pub fn isInline(kind: Kind) bool {
        return switch (kind) {
            .text, .emphasis, .strong, .code_span, .reference, .reference_group => true,
            else => false,
        };
    }
};

pub const Edge = struct {
    kind: Kind,
    from: NodeId,
    to: Target,

    pub const Kind = enum {
        link,
        xref,
        cite,
        footnote_ref,
        include,
    };
};

pub const Target = union(enum) {
    node: NodeId,
    external: []const u8,
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    roots: std.ArrayListUnmanaged(NodeId) = .empty,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    edges: std.ArrayListUnmanaged(Edge) = .empty,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Builder) void {
        for (self.nodes.items) |node| {
            if (node.children.len != 0) self.allocator.free(node.children);
            if (node.owns_text and node.text != null) self.allocator.free(node.text.?);
            if (node.owns_name and node.name != null) self.allocator.free(node.name.?);
        }
        self.roots.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.edges.deinit(self.allocator);
    }

    pub fn text(self: *Builder, value: []const u8) BuildError!NodeId {
        return try self.append(.{ .kind = .text, .text = value });
    }

    pub fn ownedText(self: *Builder, value: []const u8) BuildError!NodeId {
        return try self.append(.{
            .kind = .text,
            .text = try self.allocator.dupe(u8, value),
            .owns_text = true,
        });
    }

    pub fn codeSpan(self: *Builder, value: []const u8) BuildError!NodeId {
        return try self.append(.{ .kind = .code_span, .text = value });
    }

    pub fn ownedCodeSpan(self: *Builder, value: []const u8) BuildError!NodeId {
        return try self.append(.{
            .kind = .code_span,
            .text = try self.allocator.dupe(u8, value),
            .owns_text = true,
        });
    }

    pub fn inlineNode(self: *Builder, kind: Node.Kind, children: []const NodeId) BuildError!NodeId {
        return try self.append(.{ .kind = kind, .children = try self.dupeChildren(children) });
    }

    pub fn block(self: *Builder, kind: Node.Kind, children: []const NodeId, name: ?[]const u8) BuildError!NodeId {
        return try self.append(.{ .kind = kind, .children = try self.dupeChildren(children), .name = name });
    }

    pub fn blockOwnedName(self: *Builder, kind: Node.Kind, children: []const NodeId, name: []const u8) BuildError!NodeId {
        return try self.append(.{
            .kind = kind,
            .children = try self.dupeChildren(children),
            .name = try self.allocator.dupe(u8, name),
            .owns_name = true,
        });
    }

    pub fn edge(self: *Builder, kind: Edge.Kind, from: NodeId, to: Target) std.mem.Allocator.Error!void {
        try self.edges.append(self.allocator, .{ .kind = kind, .from = from, .to = to });
    }

    pub fn addRoot(self: *Builder, root: NodeId) std.mem.Allocator.Error!void {
        try self.roots.append(self.allocator, root);
    }

    pub fn replaceChildren(self: *Builder, id: NodeId, children: []const NodeId) std.mem.Allocator.Error!void {
        const node = &self.nodes.items[id];
        if (node.children.len != 0) self.allocator.free(node.children);
        node.children = try self.dupeChildren(children);
    }

    pub fn finish(self: *Builder) std.mem.Allocator.Error!Document {
        const roots = try self.roots.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(roots);

        const nodes = try self.nodes.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(nodes);

        const edges = try self.edges.toOwnedSlice(self.allocator);

        self.* = .{ .allocator = self.allocator };
        return .{
            .roots = roots,
            .nodes = nodes,
            .edges = edges,
        };
    }

    fn append(self: *Builder, node: Node) BuildError!NodeId {
        const id = std.math.cast(NodeId, self.nodes.items.len) orelse return error.NodeOverflow;
        try self.nodes.append(self.allocator, node);
        return id;
    }

    fn dupeChildren(self: *Builder, children: []const NodeId) std.mem.Allocator.Error![]const NodeId {
        if (children.len == 0) return &.{};
        return try self.allocator.dupe(NodeId, children);
    }
};

pub const owned = struct {
    pub fn deinitDocument(allocator: std.mem.Allocator, doc: Document) void {
        for (doc.nodes) |node| {
            if (node.children.len != 0) allocator.free(node.children);
            if (node.owns_text and node.text != null) allocator.free(node.text.?);
            if (node.owns_name and node.name != null) allocator.free(node.name.?);
        }
        allocator.free(doc.roots);
        allocator.free(doc.nodes);
        allocator.free(doc.edges);
    }
};

pub const ValidationError = std.mem.Allocator.Error || error{
    RootOutOfRange,
    ChildOutOfRange,
    EdgeSourceOutOfRange,
    EdgeTargetOutOfRange,
    DuplicateNodeName,
    IncludeCycle,
    RootMustBeBlock,
    BlockChildrenMustBeBlock,
    HeadingChildrenMustBeInline,
    ParagraphChildrenMustBeInline,
    QuoteChildrenMustBeBlock,
    CodeBlockChildrenMustBeInline,
    IncludeChildrenMustBeEmpty,
    FootnoteDefChildrenMustBeBlock,
    BibliographyDefChildrenMustBeBlock,
    ListChildrenMustBeListItem,
    ListItemChildrenMustBeBlock,
    InlineChildrenMustBeInline,
    ReferenceGroupChildrenMustBeReference,
    ReferenceRequiresEdge,
    IncludeRequiresEdge,
    LinkSourceMustBeReference,
    XrefSourceMustBeReference,
    CiteSourceMustBeReference,
    FootnoteRefSourceMustBeReference,
    IncludeSourceMustBeInclude,
    FootnoteRefTargetMustBeFootnoteDef,
    CiteTargetMustBeBibliographyDef,
    IncludeTargetMustBeBlock,
    IncludeCannotTargetSelf,
};

pub fn validate(doc: Document) ValidationError!void {
    for (doc.nodes, 0..) |node, i| {
        if (node.name) |name| {
            if (lookupNodeByName(doc, name)) |existing| {
                if (existing != i) return error.DuplicateNodeName;
            }
        }
    }

    for (doc.roots) |root| {
        if (root >= doc.nodes.len) return error.RootOutOfRange;
        if (!Node.isBlock(doc.nodes[root].kind)) return error.RootMustBeBlock;
    }

    for (doc.nodes, 0..) |node, i| {
        for (node.children) |child| {
            if (child >= doc.nodes.len) return error.ChildOutOfRange;
        }

        switch (node.kind) {
            .document, .section => try validateChildren(doc, node.children, Node.isBlock, error.BlockChildrenMustBeBlock),
            .heading => try validateChildren(doc, node.children, Node.isInline, error.HeadingChildrenMustBeInline),
            .paragraph => try validateChildren(doc, node.children, Node.isInline, error.ParagraphChildrenMustBeInline),
            .quote => try validateChildren(doc, node.children, Node.isBlock, error.QuoteChildrenMustBeBlock),
            .code_block => try validateChildren(doc, node.children, Node.isInline, error.CodeBlockChildrenMustBeInline),
            .include => {
                if (node.children.len != 0) return error.IncludeChildrenMustBeEmpty;
                if (outgoingEdge(doc, @intCast(i)) == null) return error.IncludeRequiresEdge;
            },
            .footnote_def => try validateChildren(doc, node.children, Node.isBlock, error.FootnoteDefChildrenMustBeBlock),
            .bibliography_def => try validateChildren(doc, node.children, Node.isBlock, error.BibliographyDefChildrenMustBeBlock),
            .list => {
                for (node.children) |child| {
                    if (doc.nodes[child].kind != .list_item) return error.ListChildrenMustBeListItem;
                }
            },
            .list_item => try validateChildren(doc, node.children, Node.isBlock, error.ListItemChildrenMustBeBlock),
            .text, .emphasis, .strong, .code_span => try validateChildren(doc, node.children, Node.isInline, error.InlineChildrenMustBeInline),
            .reference => {
                try validateChildren(doc, node.children, Node.isInline, error.InlineChildrenMustBeInline);
                if (outgoingEdge(doc, @intCast(i)) == null) return error.ReferenceRequiresEdge;
            },
            .reference_group => {
                for (node.children) |child| {
                    if (doc.nodes[child].kind != .reference) return error.ReferenceGroupChildrenMustBeReference;
                }
            },
        }
    }

    for (doc.edges) |edge| {
        if (edge.from >= doc.nodes.len) return error.EdgeSourceOutOfRange;
        const source_kind = doc.nodes[edge.from].kind;

        switch (edge.kind) {
            .link => if (source_kind != .reference) return error.LinkSourceMustBeReference,
            .xref => if (source_kind != .reference) return error.XrefSourceMustBeReference,
            .cite => if (source_kind != .reference) return error.CiteSourceMustBeReference,
            .footnote_ref => if (source_kind != .reference) return error.FootnoteRefSourceMustBeReference,
            .include => if (source_kind != .include) return error.IncludeSourceMustBeInclude,
        }

        switch (edge.to) {
            .node => |target| {
                if (target >= doc.nodes.len) return error.EdgeTargetOutOfRange;
                if (edge.kind == .footnote_ref and doc.nodes[target].kind != .footnote_def) {
                    return error.FootnoteRefTargetMustBeFootnoteDef;
                }
                if (edge.kind == .cite and doc.nodes[target].kind != .bibliography_def) {
                    return error.CiteTargetMustBeBibliographyDef;
                }
                if (edge.kind == .include and !Node.isBlock(doc.nodes[target].kind)) {
                    return error.IncludeTargetMustBeBlock;
                }
                if (edge.kind == .include and target == edge.from) {
                    return error.IncludeCannotTargetSelf;
                }
            },
            .external => {},
        }
    }

    try validateIncludeAcyclic(doc);
}

pub fn validateChildren(doc: Document, children: []const NodeId, predicate: fn (Node.Kind) bool, err: ValidationError) ValidationError!void {
    for (children) |child| {
        if (!predicate(doc.nodes[child].kind)) return err;
    }
}

pub fn outgoingEdge(doc: Document, from: NodeId) ?Edge {
    for (doc.edges) |edge| {
        if (edge.from == from) return edge;
    }
    return null;
}

pub fn lookupNodeByName(doc: Document, name: []const u8) ?usize {
    for (doc.nodes, 0..) |node, i| {
        if (node.name) |candidate| {
            if (std.mem.eql(u8, candidate, name)) return i;
        }
    }
    return null;
}

pub fn edgesFrom(doc: Document, from: NodeId) []const Edge {
    var start: ?usize = null;
    var end: usize = 0;

    for (doc.edges, 0..) |edge, i| {
        if (edge.from != from) continue;
        if (start == null) start = i;
        end = i + 1;
    }

    if (start) |index| return doc.edges[index..end];
    return &.{};
}

fn validateIncludeAcyclic(doc: Document) ValidationError!void {
    const allocator = std.heap.page_allocator;
    const states = try allocator.alloc(u8, doc.nodes.len);
    defer allocator.free(states);
    @memset(states, 0);

    for (doc.nodes, 0..) |_, i| {
        try visitIncludeCycle(doc, states, @intCast(i));
    }
}

fn visitIncludeCycle(doc: Document, states: []u8, id: NodeId) ValidationError!void {
    switch (states[id]) {
        1 => return error.IncludeCycle,
        2 => return,
        else => {},
    }

    states[id] = 1;
    const node = doc.nodes[id];

    if (node.kind == .include) {
        const edge = outgoingEdge(doc, id) orelse return error.IncludeRequiresEdge;
        switch (edge.to) {
            .node => |target| try visitIncludeCycle(doc, states, target),
            .external => {},
        }
    }

    for (node.children) |child| {
        try visitIncludeCycle(doc, states, child);
    }

    states[id] = 2;
}

test "minimal document scaffold supports graph edges" {
    const doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1} },
            .{ .kind = .section, .children = &.{ 2, 4 } },
            .{ .kind = .heading, .children = &.{3}, .name = "intro" },
            .{ .kind = .text, .text = "Low level document IR" },
            .{ .kind = .paragraph, .children = &.{ 5, 6, 8 } },
            .{ .kind = .text, .text = "See " },
            .{ .kind = .reference, .children = &.{7} },
            .{ .kind = .text, .text = "the title above" },
            .{ .kind = .text, .text = "." },
        },
        .edges = &.{
            .{ .kind = .xref, .from = 6, .to = .{ .node = 2 } },
        },
    };

    try validate(doc);
    try std.testing.expectEqual(@as(usize, 1), doc.roots.len);
    try std.testing.expectEqual(Node.Kind.document, doc.nodes[doc.roots[0]].kind);
    try std.testing.expectEqual(Node.Kind.heading, doc.nodes[2].kind);
    try std.testing.expectEqualStrings("Low level document IR", doc.nodes[3].text.?);
    try std.testing.expectEqual(@as(usize, 1), doc.edges.len);
    try std.testing.expectEqual(Edge.Kind.xref, doc.edges[0].kind);
    try std.testing.expectEqual(@as(NodeId, 6), doc.edges[0].from);
    try std.testing.expectEqual(@as(NodeId, 2), doc.edges[0].to.node);
}

test "validate rejects missing reference edge" {
    const doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1} },
            .{ .kind = .paragraph, .children = &.{2} },
            .{ .kind = .reference, .children = &.{3} },
            .{ .kind = .text, .text = "dangling" },
        },
        .edges = &.{},
    };

    try std.testing.expectError(error.ReferenceRequiresEdge, validate(doc));
}

test "validate footnote refs target footnote defs" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1, 4} },
            .{ .kind = .paragraph, .children = &.{2} },
            .{ .kind = .reference, .children = &.{3} },
            .{ .kind = .text, .text = "1" },
            .{ .kind = .paragraph, .children = &.{5} },
            .{ .kind = .text, .text = "not a footnote definition" },
        },
        .edges = &.{
            .{ .kind = .footnote_ref, .from = 2, .to = .{ .node = 4 } },
        },
    };

    try std.testing.expectError(error.FootnoteRefTargetMustBeFootnoteDef, validate(bad_doc));
}

test "validate citations target bibliography defs" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1, 4} },
            .{ .kind = .paragraph, .children = &.{2} },
            .{ .kind = .reference, .children = &.{3} },
            .{ .kind = .text, .text = "knuth84" },
            .{ .kind = .paragraph, .children = &.{5} },
            .{ .kind = .text, .text = "not a bibliography entry" },
        },
        .edges = &.{
            .{ .kind = .cite, .from = 2, .to = .{ .node = 4 } },
        },
    };

    try std.testing.expectError(error.CiteTargetMustBeBibliographyDef, validate(bad_doc));
}

test "validate include targets block nodes" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1} },
            .{ .kind = .include },
            .{ .kind = .text, .text = "not a block" },
        },
        .edges = &.{
            .{ .kind = .include, .from = 1, .to = .{ .node = 2 } },
        },
    };

    try std.testing.expectError(error.IncludeTargetMustBeBlock, validate(bad_doc));
}

test "validate include requires edge" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1} },
            .{ .kind = .include },
        },
        .edges = &.{},
    };

    try std.testing.expectError(error.IncludeRequiresEdge, validate(bad_doc));
}

test "validate rejects include cycles" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1, 2} },
            .{ .kind = .include },
            .{ .kind = .include },
        },
        .edges = &.{
            .{ .kind = .include, .from = 1, .to = .{ .node = 2 } },
            .{ .kind = .include, .from = 2, .to = .{ .node = 1 } },
        },
    };

    try std.testing.expectError(error.IncludeCycle, validate(bad_doc));
}

test "validate rejects invalid edge source kind" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1, 3} },
            .{ .kind = .paragraph, .children = &.{2} },
            .{ .kind = .text, .text = "plain text cannot source xrefs" },
            .{ .kind = .heading, .children = &.{4}, .name = "target" },
            .{ .kind = .text, .text = "Target" },
        },
        .edges = &.{
            .{ .kind = .xref, .from = 2, .to = .{ .node = 3 } },
        },
    };

    try std.testing.expectError(error.XrefSourceMustBeReference, validate(bad_doc));
}

test "validate rejects duplicate node names" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{ 1, 3 } },
            .{ .kind = .heading, .children = &.{2}, .name = "dup" },
            .{ .kind = .text, .text = "One" },
            .{ .kind = .heading, .children = &.{4}, .name = "dup" },
            .{ .kind = .text, .text = "Two" },
        },
        .edges = &.{},
    };

    try std.testing.expectError(error.DuplicateNodeName, validate(bad_doc));
}

test "builder assembles document with edges" {
    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const title_text = try builder.text("Builder doc");
    const heading = try builder.block(.heading, &.{title_text}, "builder-doc");
    const label_text = try builder.text("the heading");
    const xref = try builder.inlineNode(.reference, &.{label_text});
    const para_text = try builder.text("See ");
    const para_tail = try builder.text(".");
    const paragraph = try builder.block(.paragraph, &.{ para_text, xref, para_tail }, null);
    const section = try builder.block(.section, &.{ heading, paragraph }, null);
    const doc_node = try builder.block(.document, &.{section}, null);

    try builder.edge(.xref, xref, .{ .node = heading });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer owned.deinitDocument(std.testing.allocator, doc);

    try validate(doc);
    try std.testing.expectEqual(@as(usize, 1), doc.roots.len);
    try std.testing.expectEqualStrings("Builder doc", doc.nodes[title_text].text.?);
}

test "builder assembles citation to bibliography entry" {
    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const cite_label = try builder.text("knuth84");
    const cite_ref = try builder.inlineNode(.reference, &.{cite_label});
    const para = try builder.block(.paragraph, &.{cite_ref}, null);
    const bib_text = try builder.text("Donald E. Knuth. Literate Programming. 1984.");
    const bib_para = try builder.block(.paragraph, &.{bib_text}, null);
    const bib_def = try builder.block(.bibliography_def, &.{bib_para}, "bib-knuth84");
    const doc_node = try builder.block(.document, &.{ para, bib_def }, null);

    try builder.edge(.cite, cite_ref, .{ .node = bib_def });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer owned.deinitDocument(std.testing.allocator, doc);

    try validate(doc);
    try std.testing.expectEqual(Node.Kind.bibliography_def, doc.nodes[bib_def].kind);
}

test "lookup helpers find nodes and edges" {
    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const target_text = try builder.text("Target");
    const target_heading = try builder.block(.heading, &.{target_text}, "target");
    const label = try builder.text("target heading");
    const reference = try builder.inlineNode(.reference, &.{label});
    const paragraph = try builder.block(.paragraph, &.{reference}, null);
    const doc_node = try builder.block(.document, &.{ target_heading, paragraph }, null);

    try builder.edge(.xref, reference, .{ .node = target_heading });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer owned.deinitDocument(std.testing.allocator, doc);

    try std.testing.expectEqual(@as(?usize, target_heading), lookupNodeByName(doc, "target"));
    try std.testing.expectEqual(@as(usize, 1), edgesFrom(doc, reference).len);
    try std.testing.expectEqual(Edge.Kind.xref, edgesFrom(doc, reference)[0].kind);
}

test "builder assembles include node" {
    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const quote_text = try builder.text("Shared block");
    const quote_para = try builder.block(.paragraph, &.{quote_text}, null);
    const quote = try builder.block(.quote, &.{quote_para}, "shared-quote");
    const include = try builder.block(.include, &.{}, null);
    const doc_node = try builder.block(.document, &.{include}, null);

    try builder.edge(.include, include, .{ .node = quote });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer owned.deinitDocument(std.testing.allocator, doc);

    try validate(doc);
    try std.testing.expectEqual(Edge.Kind.include, outgoingEdge(doc, include).?.kind);
}

test "validate reference groups only contain references" {
    const bad_doc = Document{
        .roots = &.{0},
        .nodes = &.{
            .{ .kind = .document, .children = &.{1} },
            .{ .kind = .paragraph, .children = &.{2} },
            .{ .kind = .reference_group, .children = &.{3} },
            .{ .kind = .text, .text = "not a reference" },
        },
        .edges = &.{},
    };

    try std.testing.expectError(error.ReferenceGroupChildrenMustBeReference, validate(bad_doc));
}

test "builder assembles grouped citations" {
    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    const cite_one_label = try builder.text("knuth84");
    const cite_one = try builder.inlineNode(.reference, &.{cite_one_label});
    const cite_two_label = try builder.text("lamport94");
    const cite_two = try builder.inlineNode(.reference, &.{cite_two_label});
    const cite_group = try builder.inlineNode(.reference_group, &.{ cite_one, cite_two });
    const paragraph = try builder.block(.paragraph, &.{cite_group}, null);

    const bib_one_text = try builder.text("Knuth");
    const bib_one_para = try builder.block(.paragraph, &.{bib_one_text}, null);
    const bib_one = try builder.block(.bibliography_def, &.{bib_one_para}, "bib-knuth84");

    const bib_two_text = try builder.text("Lamport");
    const bib_two_para = try builder.block(.paragraph, &.{bib_two_text}, null);
    const bib_two = try builder.block(.bibliography_def, &.{bib_two_para}, "bib-lamport94");

    const doc_node = try builder.block(.document, &.{ paragraph, bib_one, bib_two }, null);

    try builder.edge(.cite, cite_one, .{ .node = bib_one });
    try builder.edge(.cite, cite_two, .{ .node = bib_two });
    try builder.addRoot(doc_node);

    const doc = try builder.finish();
    defer owned.deinitDocument(std.testing.allocator, doc);

    try validate(doc);
    try std.testing.expectEqual(Node.Kind.reference_group, doc.nodes[cite_group].kind);
}
