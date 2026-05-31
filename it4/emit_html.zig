const std = @import("std");
const core = @import("core_ir.zig");

pub fn emitHtml(allocator: std.mem.Allocator, doc: core.Document) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>");
    if (doc.metadata.title) |title| try appendEscapedHtml(&buf, allocator, title);
    try buf.appendSlice(allocator, "</title>\n</head>\n<body>\n");
    for (doc.roots) |root_idx| try emitNode(&buf, allocator, doc, root_idx, 0);
    try buf.appendSlice(allocator, "</body>\n</html>\n");
    return buf.toOwnedSlice(allocator);
}

fn emitNode(buf: *std.ArrayList(u8), a: std.mem.Allocator, doc: core.Document, node_idx: core.NodeIndex, depth: usize) anyerror!void {
    const entry = doc.nodes[node_idx];
    switch (entry.tag) {
        .section => {
            const s = doc.sections[entry.index];
            const h_level = @min(depth + 1, 6);
            const h_open = try std.fmt.allocPrint(a, "<h{d}>", .{h_level});
            defer a.free(h_open);
            try buf.appendSlice(a, h_open);
            if (s.title) |title| {
                try appendEscapedHtml(buf, a, title);
            } else if (s.metadata.title) |title| {
                try appendEscapedHtml(buf, a, title);
            }
            const h_close = try std.fmt.allocPrint(a, "</h{d}>\n", .{h_level});
            defer a.free(h_close);
            try buf.appendSlice(a, h_close);
            if (s.metadata.id) |id| {
                try buf.appendSlice(a, "<a id=\"");
                try appendEscapedHtml(buf, a, id);
                try buf.appendSlice(a, "\"></a>\n");
            }
            try emitNodeChildren(buf, a, doc, s.first_child_ref, s.child_count, depth + 1);
        },
        .paragraph => {
            const p = doc.paragraphs[entry.index];
            try buf.appendSlice(a, "<p>");
            try emitInlineChildren(buf, a, doc, p.first_child_ref, p.child_count);
            try buf.appendSlice(a, "</p>\n");
        },
        .list => {
            const l = doc.lists[entry.index];
            const tag = switch (l.kind) {
                .ordered => "ol",
                .unordered, .task, .description => "ul",
            };
            const open_tag = try std.fmt.allocPrint(a, "<{s}>\n", .{tag});
            defer a.free(open_tag);
            try buf.appendSlice(a, open_tag);
            if (l.first_child_ref) |first| {
                for (core.nodeChildren(doc, first, l.child_count)) |item_idx| {
                    try buf.appendSlice(a, "<li>");
                    const item = doc.list_items[doc.nodes[item_idx].index];
                    try emitNodeChildren(buf, a, doc, item.first_child_ref, item.child_count, depth + 1);
                    try buf.appendSlice(a, "</li>\n");
                }
            }
            const close_tag = try std.fmt.allocPrint(a, "</{s}>\n", .{tag});
            defer a.free(close_tag);
            try buf.appendSlice(a, close_tag);
        },
        .list_item => unreachable,
        .table => {
            const t = doc.tables[entry.index];
            try buf.appendSlice(a, "<table>\n");
            if (t.first_child_ref) |first| {
                for (core.nodeChildren(doc, first, t.child_count)) |row_idx| {
                    try buf.appendSlice(a, "<tr>");
                    const row = doc.rows[doc.nodes[row_idx].index];
                    if (row.first_child_ref) |row_first| {
                        for (core.nodeChildren(doc, row_first, row.child_count)) |cell_idx| {
                            try buf.appendSlice(a, "<td>");
                            const cell = doc.cells[doc.nodes[cell_idx].index];
                            try emitNodeChildren(buf, a, doc, cell.first_child_ref, cell.child_count, depth + 1);
                            try buf.appendSlice(a, "</td>");
                        }
                    }
                    try buf.appendSlice(a, "</tr>\n");
                }
            }
            try buf.appendSlice(a, "</table>\n");
        },
        .table_row, .table_cell => unreachable,
        .block => {
            const b = doc.blocks[entry.index];
            try buf.appendSlice(a, "<div>");
            try emitNodeChildren(buf, a, doc, b.first_child_ref, b.child_count, depth + 1);
            try buf.appendSlice(a, "</div>\n");
        },
    }
}

fn emitNodeChildren(buf: *std.ArrayList(u8), a: std.mem.Allocator, doc: core.Document, first: ?core.ChildRefIndex, count: u32, depth: usize) anyerror!void {
    if (first == null or count == 0) return;
    for (core.nodeChildren(doc, first.?, count)) |child_idx| try emitNode(buf, a, doc, child_idx, depth);
}

fn emitInlineChildren(buf: *std.ArrayList(u8), a: std.mem.Allocator, doc: core.Document, first: ?core.InlineChildRefIndex, count: u32) anyerror!void {
    if (first == null or count == 0) return;
    for (core.inlineChildren(doc, first.?, count)) |child_idx| try emitInline(buf, a, doc, child_idx);
}

fn emitInline(buf: *std.ArrayList(u8), a: std.mem.Allocator, doc: core.Document, inline_idx: core.InlineIndex) anyerror!void {
    const entry = doc.inlines[inline_idx];
    switch (entry.tag) {
        .text => try appendEscapedHtml(buf, a, doc.texts[entry.index].value),
        .link => {
            const l = doc.links[entry.index];
            try buf.appendSlice(a, "<a href=\"");
            try appendEscapedHtml(buf, a, l.target);
            try buf.appendSlice(a, "\">");
            if (l.label) |label_idx| {
                try emitInline(buf, a, doc, label_idx);
            } else {
                try appendEscapedHtml(buf, a, l.target);
            }
            try buf.appendSlice(a, "</a>");
        },
        .reference => {
            const r = doc.references[entry.index];
            try buf.appendSlice(a, "<a href=\"#");
            try appendEscapedHtml(buf, a, r.target);
            try buf.appendSlice(a, "\">");
            if (r.label) |label_idx| {
                try emitInline(buf, a, doc, label_idx);
            } else {
                try appendEscapedHtml(buf, a, r.target);
            }
            try buf.appendSlice(a, "</a>");
        },
        .anchor => {
            try buf.appendSlice(a, "<a id=\"");
            try appendEscapedHtml(buf, a, doc.anchors[entry.index].name);
            try buf.appendSlice(a, "\"></a>");
        },
        .emphasis => {
            const e = doc.emphases[entry.index];
            try buf.appendSlice(a, "<em>");
            try emitInlineChildren(buf, a, doc, e.first_child_ref, e.child_count);
            try buf.appendSlice(a, "</em>");
        },
        .strong => {
            const s = doc.strongs[entry.index];
            try buf.appendSlice(a, "<strong>");
            try emitInlineChildren(buf, a, doc, s.first_child_ref, s.child_count);
            try buf.appendSlice(a, "</strong>");
        },
    }
}

fn appendEscapedHtml(buf: *std.ArrayList(u8), a: std.mem.Allocator, s: []const u8) !void {
    var i: usize = 0;
    var last: usize = 0;
    while (i < s.len) : (i += 1) {
        const replacement: ?[]const u8 = switch (s[i]) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            else => null,
        };
        if (replacement) |r| {
            if (i > last) try buf.appendSlice(a, s[last..i]);
            try buf.appendSlice(a, r);
            last = i + 1;
        }
    }
    if (last < s.len) try buf.appendSlice(a, s[last..]);
}
