const std = @import("std");
const semantic_ir = @import("semantic_ir.zig");

const Document = semantic_ir.Document;
const Node = semantic_ir.Node;
const NodeId = semantic_ir.NodeId;
const Target = semantic_ir.Target;

pub fn emit(writer: anytype, doc: Document) anyerror!void {
    try semantic_ir.validate(doc);

    try writer.writeAll("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>");
    try emitTitle(writer, doc);
    try writer.writeAll(
        \\</title><style>
        \\*{margin:0;padding:0;box-sizing:border-box}
        \\body{max-width:70ch;margin:40px auto;padding:0 20px;font:16px/1.6 system-ui,-apple-system,sans-serif;color:#1a1a1a;background:#fafafa}
        \\h1,h2,h3,h4{line-height:1.3;color:#111;margin-top:1.5em;margin-bottom:.4em}
        \\h2{border-bottom:1px solid #e0e0e0;padding-bottom:.25em}
        \\p{margin-bottom:.8em}
        \\ul,ol{margin:.6em 0;padding-left:1.5em}
        \\li{margin:.15em 0}
        \\a{color:#2563eb;text-decoration:none}
        \\a:hover,a:focus{text-decoration:underline}
        \\code,pre{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.92em}
        \\pre{padding:14px 16px;overflow-x:auto;background:#f0f0f0;border-radius:8px;line-height:1.45;margin:.8em 0}
        \\code{background:#eee;padding:2px 5px;border-radius:4px}
        \\pre code{background:none;padding:0;border-radius:0}
        \\blockquote{margin:.8em 0;padding-left:1rem;border-left:4px solid #d0d7de;color:#555}
        \\section{margin:1.5em 0}
        \\section.footnotes{margin-top:3em;padding-top:1em;border-top:2px solid #e0e0e0}
        \\section.footnotes ol{padding-left:1.2em}
        \\section.footnotes li{margin:.6em 0}
        \\section.bibliography{margin-top:1em;padding:.8em 1em;background:#f0f4ff;border-radius:8px;border-left:4px solid #2563eb}
        \\section.bibliography div{margin:.3em 0}
        \\sup{font-size:.75em}
        \\cite{font-style:normal}
        \\</style></head><body>
    );
    for (doc.roots) |root| try emitNode(writer, doc, root, 0);
    try writer.writeAll("</body></html>");
}

fn emitTitle(writer: anytype, doc: Document) anyerror!void {
    if (documentTitle(doc)) |title| {
        try writeEscaped(writer, title);
    } else {
        try writer.writeAll("Document");
    }
}

fn emitNode(writer: anytype, doc: Document, id: NodeId, depth: usize) anyerror!void {
    const node = doc.nodes[id];
    switch (node.kind) {
        .document => try emitChildren(writer, doc, node.children, depth),
        .section => {
            try writer.writeAll("<section");
            try emitIdAttr(writer, node);
            try writer.writeAll(">");
            try emitChildren(writer, doc, node.children, depth + 1);
            try writer.writeAll("</section>");
        },
        .heading => {
            const level = headingLevel(depth);
            try writer.print("<h{d}", .{level});
            try emitIdAttr(writer, node);
            try writer.writeAll(">");
            try emitInlineChildren(writer, doc, node.children);
            try writer.print("</h{d}>", .{level});
        },
        .paragraph => {
            try writer.writeAll("<p>");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("</p>");
        },
        .list => {
            try writer.writeAll("<ul>");
            try emitChildren(writer, doc, node.children, depth + 1);
            try writer.writeAll("</ul>");
        },
        .list_item => {
            try writer.writeAll("<li>");
            try emitChildren(writer, doc, node.children, depth + 1);
            try writer.writeAll("</li>");
        },
        .quote => {
            try writer.writeAll("<blockquote>");
            try emitChildren(writer, doc, node.children, depth + 1);
            try writer.writeAll("</blockquote>");
        },
        .code_block => {
            try writer.writeAll("<pre><code>");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("</code></pre>");
        },
        .include => {
            const edge = semantic_ir.outgoingEdge(doc, id) orelse return error.IncludeRequiresEdge;
            switch (edge.to) {
                .node => |target| try emitNode(writer, doc, target, depth),
                .external => |value| {
                    try writer.writeAll("<section data-include=\"");
                    try writeEscaped(writer, value);
                    try writer.writeAll("\"></section>");
                },
            }
        },
        .footnote_def => {
            try writer.writeAll("<section class=\"footnotes\"><ol><li");
            try emitIdAttr(writer, node);
            try writer.writeAll(">");
            try emitChildren(writer, doc, node.children, depth + 1);
            try writer.writeAll("</li></ol></section>");
        },
        .bibliography_def => {
            try writer.writeAll("<section class=\"bibliography\"><div");
            try emitIdAttr(writer, node);
            try writer.writeAll(">");
            try emitChildren(writer, doc, node.children, depth + 1);
            try writer.writeAll("</div></section>");
        },
        .text, .emphasis, .strong, .code_span, .reference, .reference_group => try emitInlineNode(writer, doc, id),
    }
}

fn emitChildren(writer: anytype, doc: Document, children: []const NodeId, depth: usize) anyerror!void {
    for (children) |child| try emitNode(writer, doc, child, depth);
}

fn emitInlineChildren(writer: anytype, doc: Document, children: []const NodeId) anyerror!void {
    for (children) |child| try emitInlineNode(writer, doc, child);
}

fn emitInlineNode(writer: anytype, doc: Document, id: NodeId) anyerror!void {
    const node = doc.nodes[id];
    switch (node.kind) {
        .text => try writeEscaped(writer, node.text orelse ""),
        .emphasis => {
            try writer.writeAll("<em>");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("</em>");
        },
        .strong => {
            try writer.writeAll("<strong>");
            try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("</strong>");
        },
        .code_span => {
            try writer.writeAll("<code>");
            if (node.text) |text| try writeEscaped(writer, text) else try emitInlineChildren(writer, doc, node.children);
            try writer.writeAll("</code>");
        },
        .reference => {
            const edge = semantic_ir.outgoingEdge(doc, id) orelse return error.ReferenceRequiresEdge;
            switch (edge.kind) {
                .link, .xref => {
                    try writer.writeAll("<a href=\"");
                    try emitTarget(writer, doc, edge.to);
                    try writer.writeAll("\">");
                    try emitInlineChildren(writer, doc, node.children);
                    try writer.writeAll("</a>");
                },
                .footnote_ref => {
                    try writer.writeAll("<sup><a href=\"");
                    try emitTarget(writer, doc, edge.to);
                    try writer.writeAll("\">");
                    try emitInlineChildren(writer, doc, node.children);
                    try writer.writeAll("</a></sup>");
                },
                .cite => {
                    try writer.writeAll("<cite>[<a href=\"");
                    try emitTarget(writer, doc, edge.to);
                    try writer.writeAll("\">");
                    try emitInlineChildren(writer, doc, node.children);
                    try writer.writeAll("</a>]</cite>");
                },
                else => try emitInlineChildren(writer, doc, node.children),
            }
        },
        .reference_group => {
            if (isCitationGroup(doc, node.children)) {
                try writer.writeAll("<cite>[");
                for (node.children, 0..) |child, i| {
                    if (i != 0) try writer.writeAll("; ");
                    const edge = semantic_ir.outgoingEdge(doc, child) orelse return error.ReferenceRequiresEdge;
                    try writer.writeAll("<a href=\"");
                    try emitTarget(writer, doc, edge.to);
                    try writer.writeAll("\">");
                    try emitInlineChildren(writer, doc, doc.nodes[child].children);
                    try writer.writeAll("</a>");
                }
                try writer.writeAll("]</cite>");
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
            } else if (target_node.kind == .heading) {
                try writer.writeByte('#');
                try emitSlug(writer, doc, target_node.children);
            } else {
                try writer.writeAll("#node-");
                try writer.print("{d}", .{target_id});
            }
        },
    }
}

fn emitIdAttr(writer: anytype, node: Node) anyerror!void {
    if (node.name) |name| {
        try writer.writeAll(" id=\"");
        try writeEscaped(writer, name);
        try writer.writeByte('"');
    }
}

fn emitSlug(writer: anytype, doc: Document, children: []const NodeId) anyerror!void {
    var wrote = false;
    var last_was_dash = false;
    for (children) |child| {
        const node = doc.nodes[child];
        if (node.kind != .text) continue;
        for (node.text orelse "") |c| {
            if (std.ascii.isAlphanumeric(c)) {
                try writer.writeByte(std.ascii.toLower(c));
                wrote = true;
                last_was_dash = false;
            } else if (wrote and !last_was_dash) {
                try writer.writeByte('-');
                last_was_dash = true;
            }
        }
    }
    if (!wrote) try writer.writeAll("node");
}

fn headingLevel(depth: usize) usize {
    const level = depth + 1;
    return if (level < 6) level else 6;
}

fn documentTitle(doc: Document) ?[]const u8 {
    for (doc.nodes) |node| {
        if (node.kind != .heading) continue;
        for (node.children) |child| {
            const child_node = doc.nodes[child];
            if (child_node.kind == .text and child_node.text != null) return child_node.text.?;
        }
    }
    return null;
}

fn writeEscaped(writer: anytype, value: []const u8) anyerror!void {
    for (value) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            else => try writer.writeByte(c),
        }
    }
}
