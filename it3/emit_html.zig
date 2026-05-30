const std = @import("std");
const arena = @import("arena_ir.zig");

pub fn emitHtml(allocator: std.mem.Allocator, doc: arena.DocumentArena) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>");

    if (doc.metadata.title) |title| {
        try appendEscapedHtml(&buf, allocator, title);
    }

    try buf.appendSlice(allocator, "</title>\n<style>\n");
    try buf.appendSlice(allocator, "body{font-family:sans-serif;max-width:50em;margin:2em auto;padding:0 1em;line-height:1.5}\n");
    try buf.appendSlice(allocator, "table{border-collapse:collapse;width:100%}\n");
    try buf.appendSlice(allocator, "td,th{border:1px solid #ccc;padding:.5em;text-align:left}\n");
    try buf.appendSlice(allocator, "</style>\n</head>\n<body>\n");

    for (doc.roots) |root_idx| {
        const entry = doc.nodes[root_idx];
        try emitNode(&buf, allocator, doc, root_idx, entry, 0);
    }

    try buf.appendSlice(allocator, "</body>\n</html>\n");
    return buf.toOwnedSlice(allocator);
}

fn emitNode(
    buf: *std.ArrayList(u8),
    a: std.mem.Allocator,
    doc: arena.DocumentArena,
    node_idx: arena.NodeIndex,
    entry: arena.NodeEntry,
    depth: usize,
) anyerror!void {
    _ = node_idx;
    switch (entry.tag) {
        .section => {
            const s = doc.sections[entry.index];
            const h_level = @min(depth + 1, 6);
            const h_tag = try std.fmt.allocPrint(a, "<h{d}>", .{h_level});
            defer a.free(h_tag);
            try buf.appendSlice(a, h_tag);

            if (s.title) |t| {
                try appendEscapedHtml(buf, a, t);
            } else if (s.metadata.title) |t| {
                try appendEscapedHtml(buf, a, t);
            }

            const h_close = try std.fmt.allocPrint(a, "</h{d}>\n", .{h_level});
            defer a.free(h_close);
            try buf.appendSlice(a, h_close);

            if (s.metadata.id) |id| {
                const anchor_str = try std.fmt.allocPrint(a, "<a id=\"{s}\"></a>\n", .{id});
                defer a.free(anchor_str);
                try buf.appendSlice(a, anchor_str);
            }

            if (s.child_count > 0 and s.first_child != null) {
                const children = arena.childSlice(doc, s.first_child.?, s.child_count);
                for (children, 0..) |child_entry, child_idx| {
                    const ci: arena.NodeIndex = @intCast(child_idx + s.first_child.?);
                    try emitNode(buf, a, doc, ci, child_entry, depth + 1);
                }
            }
        },
        .paragraph => {
            const p = doc.paragraphs[entry.index];
            try buf.appendSlice(a, "<p>");
            if (p.inline_count > 0 and p.first_inline != null) {
                const inlines = arena.childInlineSlice(doc, p.first_inline.?, p.inline_count);
                for (inlines) |inline_entry| {
                    try emitInline(buf, a, doc, inline_entry);
                }
            }
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

            if (l.item_count > 0 and l.first_item != null) {
                const items = arena.childSlice(doc, l.first_item.?, l.item_count);
                for (items) |item_entry| {
                    if (item_entry.tag == .list_item) {
                        const li = doc.list_items[item_entry.index];
                        try buf.appendSlice(a, "<li>");
                        if (li.child_count > 0 and li.first_child != null) {
                            const li_children = arena.childSlice(doc, li.first_child.?, li.child_count);
                            for (li_children, 0..) |child_entry, child_j| {
                                const cj: arena.NodeIndex = @intCast(child_j + li.first_child.?);
                                try emitNode(buf, a, doc, cj, child_entry, depth + 1);
                            }
                        }
                        try buf.appendSlice(a, "</li>\n");
                    }
                }
            }
            const close_tag = try std.fmt.allocPrint(a, "</{s}>\n", .{tag});
            defer a.free(close_tag);
            try buf.appendSlice(a, close_tag);
        },
        .list_item => {},
        .table => {
            const t = doc.tables[entry.index];
            try buf.appendSlice(a, "<table>\n");
            if (t.row_count > 0 and t.first_row != null) {
                const row_nodes = arena.childSlice(doc, t.first_row.?, t.row_count);
                for (row_nodes) |row_entry| {
                    if (row_entry.tag == .table_row) {
                        const r = doc.rows[row_entry.index];
                        try buf.appendSlice(a, "<tr>");
                        if (r.cell_count > 0 and r.first_cell != null) {
                            const cell_nodes = arena.childSlice(doc, r.first_cell.?, r.cell_count);
                            for (cell_nodes) |cell_entry| {
                                if (cell_entry.tag == .table_cell) {
                                    const c = doc.cells[cell_entry.index];
                                    try buf.appendSlice(a, "<td>");
                                    if (c.child_count > 0 and c.first_child != null) {
                                        const td_children = arena.childSlice(doc, c.first_child.?, c.child_count);
                                        for (td_children, 0..) |child_entry, child_k| {
                                            const ck: arena.NodeIndex = @intCast(child_k + c.first_child.?);
                                            try emitNode(buf, a, doc, ck, child_entry, depth + 1);
                                        }
                                    }
                                    try buf.appendSlice(a, "</td>");
                                }
                            }
                        }
                        try buf.appendSlice(a, "</tr>\n");
                    }
                }
            }
            try buf.appendSlice(a, "</table>\n");
        },
        .table_row, .table_cell => {},
        .block => {
            const b = doc.blocks[entry.index];
            try buf.appendSlice(a, "<div>");
            if (b.child_count > 0 and b.first_child != null) {
                const children = arena.childSlice(doc, b.first_child.?, b.child_count);
                for (children, 0..) |child_entry, child_j| {
                    const cj: arena.NodeIndex = @intCast(child_j + b.first_child.?);
                    try emitNode(buf, a, doc, cj, child_entry, depth + 1);
                }
            }
            try buf.appendSlice(a, "</div>\n");
        },
    }
}

fn emitInline(
    buf: *std.ArrayList(u8),
    a: std.mem.Allocator,
    doc: arena.DocumentArena,
    entry: arena.InlineEntry,
) anyerror!void {
    switch (entry.tag) {
        .text => {
            const t = doc.texts[entry.index];
            try appendEscapedHtml(buf, a, t.value);
        },
        .link => {
            const l = doc.links[entry.index];
            try buf.appendSlice(a, "<a href=\"");
            try appendEscapedHtml(buf, a, l.target);
            try buf.appendSlice(a, "\">");
            if (l.label) |label_idx| {
                const label_entry = doc.inlines[label_idx];
                if (label_entry.tag == .text) {
                    const label_text = doc.texts[label_entry.index];
                    try appendEscapedHtml(buf, a, label_text.value);
                }
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
                const label_entry = doc.inlines[label_idx];
                if (label_entry.tag == .text) {
                    const label_text = doc.texts[label_entry.index];
                    try appendEscapedHtml(buf, a, label_text.value);
                }
            } else {
                try appendEscapedHtml(buf, a, r.target);
            }
            try buf.appendSlice(a, "</a>");
        },
        .anchor => {
            const an = doc.anchors[entry.index];
            try buf.appendSlice(a, "<a id=\"");
            try appendEscapedHtml(buf, a, an.name);
            try buf.appendSlice(a, "\"></a>");
        },
        .emphasis => {
            const e = doc.emphases[entry.index];
            try buf.appendSlice(a, "<em>");
            if (e.inline_count > 0 and e.first_inline != null) {
                const inlines = arena.childInlineSlice(doc, e.first_inline.?, e.inline_count);
                for (inlines) |inline_entry| {
                    try emitInline(buf, a, doc, inline_entry);
                }
            }
            try buf.appendSlice(a, "</em>");
        },
        .strong => {
            const s = doc.strongs[entry.index];
            try buf.appendSlice(a, "<strong>");
            if (s.inline_count > 0 and s.first_inline != null) {
                const inlines = arena.childInlineSlice(doc, s.first_inline.?, s.inline_count);
                for (inlines) |inline_entry| {
                    try emitInline(buf, a, doc, inline_entry);
                }
            }
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
            if (i > last) {
                try buf.appendSlice(a, s[last..i]);
            }
            try buf.appendSlice(a, r);
            last = i + 1;
        }
    }
    if (last < s.len) {
        try buf.appendSlice(a, s[last..]);
    }
}
