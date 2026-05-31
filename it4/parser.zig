const std = @import("std");
const adapter = @import("adapter.zig");
const core = @import("core_ir.zig");
const author = @import("author_ir.zig");

const OpenList = struct {
    indent: usize,
    kind: author.ListKind,
    item_open: bool,
};

pub fn parseMiniMarkdown(allocator: std.mem.Allocator, input: []const u8) !core.Document {
    var temp = std.heap.ArenaAllocator.init(allocator);
    defer temp.deinit();

    var events = std.ArrayList(adapter.Event).empty;
    defer events.deinit(allocator);

    var title: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, input, '\n');
    var section_levels = std.ArrayList(usize).empty;
    defer section_levels.deinit(allocator);

    var paragraph_open = false;
    var lists = std.ArrayList(OpenList).empty;
    defer lists.deinit(allocator);
    var table_open = false;
    var first_line = true;

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        const trimmed = std.mem.trim(u8, line, " \t");

        if (first_line and std.mem.startsWith(u8, trimmed, "= ")) {
            title = trimmed[2..];
            first_line = false;
            continue;
        }
        first_line = false;

        if (trimmed.len == 0) {
            try closeParagraph(&events, allocator, &paragraph_open);
            try closeAllLists(&events, allocator, &lists);
            try closeTable(&events, allocator, &table_open);
            continue;
        }

        if (headingLevel(trimmed)) |level| {
            try closeParagraph(&events, allocator, &paragraph_open);
            try closeAllLists(&events, allocator, &lists);
            try closeTable(&events, allocator, &table_open);

            while (section_levels.items.len >= level) {
                _ = section_levels.pop();
                try events.append(allocator, .{ .end_section = {} });
            }

            const heading_text = std.mem.trim(u8, trimmed[level + 1 ..], " ");
            const id = try slugify(temp.allocator(), heading_text);
            try events.append(allocator, .{ .begin_section = .{ .id = id, .title = heading_text } });
            try section_levels.append(allocator, level);
            continue;
        }

        if (parseListLine(line)) |list_line| {
            try closeParagraph(&events, allocator, &paragraph_open);
            try closeTable(&events, allocator, &table_open);
            try updateListStack(&events, allocator, &lists, list_line.indent, list_line.kind);
            try events.append(allocator, .{ .begin_paragraph = {} });
            try emitInlineEvents(allocator, list_line.text, &events);
            try events.append(allocator, .{ .end_paragraph = {} });
            continue;
        }

        if (isTableRow(trimmed)) {
            try closeParagraph(&events, allocator, &paragraph_open);
            try closeAllLists(&events, allocator, &lists);
            if (!table_open) {
                try events.append(allocator, .{ .begin_table = {} });
                table_open = true;
            }
            try emitTableRow(allocator, trimmed, &events);
            continue;
        }

        try closeAllLists(&events, allocator, &lists);
        try closeTable(&events, allocator, &table_open);
        if (!paragraph_open) {
            try events.append(allocator, .{ .begin_paragraph = {} });
            paragraph_open = true;
        } else {
            try events.append(allocator, .{ .text = " " });
        }
        try emitInlineEvents(allocator, trimmed, &events);
    }

    try closeParagraph(&events, allocator, &paragraph_open);
    try closeAllLists(&events, allocator, &lists);
    try closeTable(&events, allocator, &table_open);
    while (section_levels.pop()) |_| {
        try events.append(allocator, .{ .end_section = {} });
    }

    return try adapter.lowerEventStream(allocator, .{ .title = title }, events.items);
}

fn closeParagraph(events: *std.ArrayList(adapter.Event), allocator: std.mem.Allocator, open: *bool) !void {
    if (open.*) {
        try events.append(allocator, .{ .end_paragraph = {} });
        open.* = false;
    }
}

fn closeAllLists(events: *std.ArrayList(adapter.Event), allocator: std.mem.Allocator, lists: *std.ArrayList(OpenList)) !void {
    while (lists.items.len > 0) {
        var top = &lists.items[lists.items.len - 1];
        if (top.item_open) {
            try events.append(allocator, .{ .end_list_item = {} });
            top.item_open = false;
        }
        _ = lists.pop();
        try events.append(allocator, .{ .end_list = {} });
    }
}

fn updateListStack(events: *std.ArrayList(adapter.Event), allocator: std.mem.Allocator, lists: *std.ArrayList(OpenList), indent: usize, kind: author.ListKind) !void {
    while (lists.items.len > 0 and lists.items[lists.items.len - 1].indent > indent) {
        var top = &lists.items[lists.items.len - 1];
        if (top.item_open) {
            try events.append(allocator, .{ .end_list_item = {} });
            top.item_open = false;
        }
        _ = lists.pop();
        try events.append(allocator, .{ .end_list = {} });
    }

    if (lists.items.len == 0) {
        try events.append(allocator, .{ .begin_list = kind });
        try lists.append(allocator, .{ .indent = indent, .kind = kind, .item_open = false });
    } else {
        var top = &lists.items[lists.items.len - 1];
        if (indent > top.indent) {
            try events.append(allocator, .{ .begin_list = kind });
            try lists.append(allocator, .{ .indent = indent, .kind = kind, .item_open = false });
        } else if (indent == top.indent and top.kind != kind) {
            if (top.item_open) {
                try events.append(allocator, .{ .end_list_item = {} });
                top.item_open = false;
            }
            _ = lists.pop();
            try events.append(allocator, .{ .end_list = {} });
            try events.append(allocator, .{ .begin_list = kind });
            try lists.append(allocator, .{ .indent = indent, .kind = kind, .item_open = false });
        }
    }

    var current = &lists.items[lists.items.len - 1];
    if (current.item_open) {
        try events.append(allocator, .{ .end_list_item = {} });
    }
    try events.append(allocator, .{ .begin_list_item = {} });
    current.item_open = true;
}

fn closeTable(events: *std.ArrayList(adapter.Event), allocator: std.mem.Allocator, open: *bool) !void {
    if (open.*) {
        try events.append(allocator, .{ .end_table = {} });
        open.* = false;
    }
}

fn headingLevel(line: []const u8) ?usize {
    var i: usize = 0;
    while (i < line.len and line[i] == '#') : (i += 1) {}
    if (i > 0 and i < line.len and line[i] == ' ') return i;
    return null;
}

fn parseListLine(line: []const u8) ?struct { indent: usize, kind: author.ListKind, text: []const u8 } {
    var indent: usize = 0;
    while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
    if (indent + 2 <= line.len and std.mem.startsWith(u8, line[indent..], "- ")) {
        return .{ .indent = indent, .kind = .unordered, .text = line[indent + 2 ..] };
    }
    var i: usize = indent;
    while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {}
    if (i > indent and i + 1 < line.len and line[i] == '.' and line[i + 1] == ' ') {
        return .{ .indent = indent, .kind = .ordered, .text = line[i + 2 ..] };
    }
    return null;
}

fn isTableRow(line: []const u8) bool {
    return line.len > 2 and line[0] == '|' and std.mem.lastIndexOfScalar(u8, line[1..], '|') != null;
}

fn emitTableRow(allocator: std.mem.Allocator, line: []const u8, events: *std.ArrayList(adapter.Event)) !void {
    try events.append(allocator, .{ .begin_table_row = {} });
    var parts = std.mem.splitScalar(u8, line[1..], '|');
    while (parts.next()) |part| {
        const cell = std.mem.trim(u8, part, " ");
        if (cell.len == 0) continue;
        try events.append(allocator, .{ .begin_table_cell = {} });
        try events.append(allocator, .{ .begin_paragraph = {} });
        try emitInlineEvents(allocator, cell, events);
        try events.append(allocator, .{ .end_paragraph = {} });
        try events.append(allocator, .{ .end_table_cell = {} });
    }
    try events.append(allocator, .{ .end_table_row = {} });
}

fn emitInlineEvents(allocator: std.mem.Allocator, text: []const u8, events: *std.ArrayList(adapter.Event)) !void {
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], "**")) {
            if (std.mem.indexOf(u8, text[i + 2 ..], "**")) |end| {
                try events.append(allocator, .{ .begin_strong = {} });
                try emitInlineEvents(allocator, text[i + 2 .. i + 2 + end], events);
                try events.append(allocator, .{ .end_strong = {} });
                i += 4 + end;
                continue;
            }
        }
        if (text[i] == '*') {
            if (std.mem.indexOfScalar(u8, text[i + 1 ..], '*')) |end| {
                try events.append(allocator, .{ .begin_emphasis = {} });
                try emitInlineEvents(allocator, text[i + 1 .. i + 1 + end], events);
                try events.append(allocator, .{ .end_emphasis = {} });
                i += 2 + end;
                continue;
            }
        }
        if (std.mem.startsWith(u8, text[i..], "[[")) {
            if (std.mem.indexOf(u8, text[i + 2 ..], "]]")) |end| {
                try events.append(allocator, .{ .anchor = text[i + 2 .. i + 2 + end] });
                i += 4 + end;
                continue;
            }
        }
        if (std.mem.startsWith(u8, text[i..], "<<")) {
            if (std.mem.indexOf(u8, text[i + 2 ..], ">>")) |end| {
                const inner = text[i + 2 .. i + 2 + end];
                if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                    try events.append(allocator, .{ .reference = .{ .target = std.mem.trim(u8, inner[0..comma], " "), .label = std.mem.trim(u8, inner[comma + 1 ..], " ") } });
                } else {
                    try events.append(allocator, .{ .reference = .{ .target = std.mem.trim(u8, inner, " "), .label = null } });
                }
                i += 4 + end;
                continue;
            }
        }
        if (text[i] == '[') {
            if (std.mem.indexOfScalar(u8, text[i + 1 ..], ']')) |close| {
                const after = i + 1 + close + 1;
                if (after < text.len and text[after] == '(') {
                    if (std.mem.indexOfScalar(u8, text[after + 1 ..], ')')) |end| {
                        try events.append(allocator, .{ .link = .{ .target = text[after + 1 .. after + 1 + end], .label = text[i + 1 .. i + 1 + close] } });
                        i = after + 2 + end;
                        continue;
                    }
                }
            }
        }

        const next = nextSpecial(text, i);
        try events.append(allocator, .{ .text = text[i..next] });
        i = next;
    }
}

fn nextSpecial(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len) : (i += 1) {
        if (text[i] == '*' or text[i] == '[' or text[i] == '<') return i;
    }
    return text.len;
}

fn slugify(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var last_dash = false;
    for (text) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try out.append(allocator, std.ascii.toLower(c));
            last_dash = false;
        } else if (!last_dash) {
            try out.append(allocator, '-');
            last_dash = true;
        }
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') _ = out.pop();
    return out.toOwnedSlice(allocator);
}
