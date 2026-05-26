const std = @import("std");
const semantic_ir = @import("semantic_ir.zig");

const Document = semantic_ir.Document;
const Node = semantic_ir.Node;
const NodeId = semantic_ir.NodeId;
const Target = semantic_ir.Target;

pub fn emit(writer: anytype, doc: Document) anyerror!void {
    try semantic_ir.validate(doc);

    for (doc.roots, 0..) |root, i| {
        if (i != 0) try writer.writeAll("\n");
        try emitNode(writer, doc, root, 0);
    }
}

fn emitNode(writer: anytype, doc: Document, id: NodeId, depth: usize) anyerror!void {
    const node = doc.nodes[id];
    switch (node.kind) {
        .document => try emitChildren(writer, doc, node.children, depth, true),
        .section => try emitSection(writer, doc, node.children, depth),
        .heading => {
            const level = headingLevel(depth);
            for (0..level) |_| try writer.writeByte('#');
            try writer.writeAll(" ");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("\n");
        },
        .paragraph => {
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("\n");
        },
        .list => try emitList(writer, doc, node.children),
        .list_item => try emitListItem(writer, doc, node.children),
        .quote => {
            try writer.writeAll("> ");
            try emitChildren(writer, doc, node.children, depth, false);
            try writer.writeAll("\n");
        },
        .code_block => {
            try writer.writeAll("```\n");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("\n```\n");
        },
        .include => {
            const edge = semantic_ir.outgoingEdge(doc, id) orelse return error.IncludeRequiresEdge;
            switch (edge.to) {
                .node => |target| try emitNode(writer, doc, target, depth),
                .external => |value| {
                    try writer.writeAll("include::");
                    try writer.writeAll(value);
                    try writer.writeAll("[]\n");
                },
            }
        },
        .footnote_def => {
            try writer.writeAll("[^");
            try writer.writeAll(footnoteLabel(node));
            try writer.writeAll("]: ");
            for (node.children, 0..) |child, i| {
                if (i != 0) try writer.writeAll("\n");
                const child_node = doc.nodes[child];
                switch (child_node.kind) {
                    .paragraph => try emitInlineChildren(writer, doc, child_node.children),
                    else => try emitNode(writer, doc, child, depth + 1),
                }
            }
            try writer.writeAll("\n");
        },
        .bibliography_def => {
            try writer.writeAll("[@");
            try writer.writeAll(bibliographyLabel(node));
            try writer.writeAll("]: ");
            for (node.children, 0..) |child, i| {
                if (i != 0) try writer.writeAll("\n");
                const child_node = doc.nodes[child];
                switch (child_node.kind) {
                    .paragraph => try emitInlineChildren(writer, doc, child_node.children),
                    else => try emitNode(writer, doc, child, depth + 1),
                }
            }
            try writer.writeAll("\n");
        },
        .text, .emphasis, .strong, .code_span, .reference, .reference_group => try emitInlineNode(writer, doc, id),
    }
}

fn emitSection(writer: anytype, doc: Document, children: []const NodeId, depth: usize) anyerror!void {
    for (children, 0..) |child, i| {
        if (i != 0) try writer.writeAll("\n");
        const child_depth = if (doc.nodes[child].kind == .heading) depth + 1 else depth + 2;
        try emitNode(writer, doc, child, child_depth);
    }
}

fn emitChildren(writer: anytype, doc: Document, children: []const NodeId, depth: usize, spaced: bool) anyerror!void {
    for (children, 0..) |child, i| {
        if (i != 0 and spaced) try writer.writeAll("\n");
        try emitNode(writer, doc, child, depth + 1);
    }
}

fn emitList(writer: anytype, doc: Document, children: []const NodeId) anyerror!void {
    for (children) |child| try emitNode(writer, doc, child, 0);
}

fn emitListItem(writer: anytype, doc: Document, children: []const NodeId) anyerror!void {
    try writer.writeAll("- ");
    for (children, 0..) |child, i| {
        const child_node = doc.nodes[child];
        if (i != 0) try writer.writeAll("\n");
        switch (child_node.kind) {
            .paragraph => try emitInlineChildren(writer, doc, child_node.children),
            else => try emitNode(writer, doc, child, 0),
        }
    }
    try writer.writeAll("\n");
}

fn emitInlineChildren(writer: anytype, doc: Document, children: []const NodeId) anyerror!void {
    for (children) |child| try emitInlineNode(writer, doc, child);
}

fn emitInlineNode(writer: anytype, doc: Document, id: NodeId) anyerror!void {
    const node = doc.nodes[id];
    switch (node.kind) {
        .text => try writer.writeAll(node.text orelse ""),
        .emphasis => {
            try writer.writeByte('*');
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeByte('*');
        },
        .strong => {
            try writer.writeAll("**");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("**");
        },
        .code_span => {
            try writer.writeByte('`');
            if (node.text) |text| try writer.writeAll(text) else try emitInlineChildren(writer, doc, node.children);
            try writer.writeByte('`');
        },
        .reference => {
            const edge = semantic_ir.outgoingEdge(doc, id) orelse return error.ReferenceRequiresEdge;
            switch (edge.kind) {
                .link, .xref => {
                    try writer.writeByte('[');
                    try emitInlineChildren(writer, doc, node.children);
                    try writer.writeAll("](");
                    try emitTarget(writer, doc, edge.to);
                    try writer.writeByte(')');
                },
                .footnote_ref => {
                    try writer.writeAll("[^");
                    if (referenceLabel(doc, id)) |label| {
                        try writer.writeAll(label);
                    }
                    try writer.writeByte(']');
                },
                .cite => {
                    try writer.writeAll("[@");
                    if (referenceLabel(doc, id)) |label| {
                        try writer.writeAll(label);
                    }
                    try writer.writeByte(']');
                },
                else => try emitInlineChildren(writer, doc, node.children),
            }
        },
        .reference_group => {
            if (isCitationGroup(doc, node.children)) {
                try writer.writeByte('[');
                for (node.children, 0..) |child, i| {
                    if (i != 0) try writer.writeAll("; ");
                    try writer.writeByte('@');
                    if (referenceLabel(doc, child)) |label| {
                        try writer.writeAll(label);
                    }
                }
                try writer.writeByte(']');
            } else {
                try emitInlineChildren(writer, doc, node.children);
            }
        },
        else => try emitNode(writer, doc, id, 0),
    }
}

fn isCitationGroup(doc: Document, children: []const NodeId) bool {
    if (children.len == 0) return false;
    for (children) |child| {
        const edge = semantic_ir.outgoingEdge(doc, child) orelse return false;
        if (edge.kind != .cite) return false;
    }
    return true;
}

fn emitTarget(writer: anytype, doc: Document, target: Target) anyerror!void {
    switch (target) {
        .external => |value| try writer.writeAll(value),
        .node => |target_id| {
            const target_node = doc.nodes[target_id];
            if (target_node.name) |name| {
                try writer.writeByte('#');
                try writer.writeAll(name);
            } else {
                try writer.writeAll("#node-");
                try writer.print("{d}", .{target_id});
            }
        },
    }
}

fn referenceLabel(doc: Document, id: NodeId) ?[]const u8 {
    const node = doc.nodes[id];
    if (node.children.len != 1) return null;
    const child = doc.nodes[node.children[0]];
    if (child.kind == .text) return child.text;
    return null;
}

fn footnoteLabel(node: Node) []const u8 {
    const name = node.name orelse return "note";
    if (std.mem.startsWith(u8, name, "fn-")) return name[3..];
    return name;
}

fn bibliographyLabel(node: Node) []const u8 {
    const name = node.name orelse return "ref";
    if (std.mem.startsWith(u8, name, "bib-")) return name[4..];
    return name;
}

fn headingLevel(depth: usize) usize {
    return if (depth < 6) depth else 6;
}
