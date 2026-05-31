const std = @import("std");
const core = @import("core_ir.zig");

pub fn validate(allocator: std.mem.Allocator, doc: core.Document) ![]core.Diagnostic {
    var diags = std.ArrayList(core.Diagnostic).empty;
    errdefer {
        for (diags.items) |d| allocator.free(d.message);
        diags.deinit(allocator);
    }

    try validateRoots(&diags, allocator, doc);
    try validateIdentifiers(&diags, allocator, doc);
    try validateNodes(&diags, allocator, doc);
    try validateInlineRefs(&diags, allocator, doc);
    return diags.toOwnedSlice(allocator);
}

fn validateRoots(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document) !void {
    for (doc.roots) |root_idx| {
        if (root_idx >= doc.nodes.len) {
            try pushDiag(diags, allocator, .err, .document, "Root index out of range");
        }
    }
}

fn validateNodes(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document) !void {
    for (doc.nodes, 0..) |entry, i| {
        const node_idx: core.NodeIndex = @intCast(i);
        switch (entry.tag) {
            .section => {
                if (entry.index >= doc.sections.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "Section payload index out of range");
                const s = doc.sections[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, s.first_child_ref, s.child_count);
            },
            .paragraph => {
                if (entry.index >= doc.paragraphs.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "Paragraph payload index out of range");
                const p = doc.paragraphs[entry.index];
                try validateInlineChildSpan(diags, allocator, doc, .{ .node = node_idx }, p.first_child_ref, p.child_count);
            },
            .list => {
                if (entry.index >= doc.lists.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "List payload index out of range");
                const l = doc.lists[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, l.first_child_ref, l.child_count);
                try validateExpectedChildTags(diags, allocator, doc, .{ .node = node_idx }, l.first_child_ref, l.child_count, .list_item);
            },
            .list_item => {
                if (entry.index >= doc.list_items.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "List item payload index out of range");
                const li = doc.list_items[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, li.first_child_ref, li.child_count);
            },
            .table => {
                if (entry.index >= doc.tables.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "Table payload index out of range");
                const t = doc.tables[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, t.first_child_ref, t.child_count);
                try validateExpectedChildTags(diags, allocator, doc, .{ .node = node_idx }, t.first_child_ref, t.child_count, .table_row);
            },
            .table_row => {
                if (entry.index >= doc.rows.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "Table row payload index out of range");
                const row = doc.rows[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, row.first_child_ref, row.child_count);
                try validateExpectedChildTags(diags, allocator, doc, .{ .node = node_idx }, row.first_child_ref, row.child_count, .table_cell);
            },
            .table_cell => {
                if (entry.index >= doc.cells.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "Table cell payload index out of range");
                const cell = doc.cells[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, cell.first_child_ref, cell.child_count);
            },
            .block => {
                if (entry.index >= doc.blocks.len) try pushDiag(diags, allocator, .err, .{ .node = node_idx }, "Block payload index out of range");
                const b = doc.blocks[entry.index];
                try validateNodeChildSpan(diags, allocator, doc, .{ .node = node_idx }, b.first_child_ref, b.child_count);
            },
        }
    }
}

fn validateIdentifiers(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document) !void {
    var seen = std.StringHashMap(core.DiagnosticSubject).init(allocator);
    defer seen.deinit();

    for (doc.sections, 0..) |section, i| {
        if (section.metadata.id) |id| {
            try checkUniqueIdentifier(diags, allocator, &seen, id, .{ .node = findNodeIndex(doc, .section, @intCast(i)).? }, "Duplicate section id");
        }
    }

    for (doc.blocks, 0..) |block, i| {
        if (block.metadata.id) |id| {
            try checkUniqueIdentifier(diags, allocator, &seen, id, .{ .node = findNodeIndex(doc, .block, @intCast(i)).? }, "Duplicate block id");
        }
    }

    for (doc.anchors, 0..) |anchor, i| {
        try checkUniqueIdentifier(diags, allocator, &seen, anchor.name, .{ .inline_ref = findInlineIndex(doc, .anchor, @intCast(i)).? }, "Duplicate anchor name");
    }
}

fn validateInlineRefs(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document) !void {
    var anchors = std.StringHashMap(void).init(allocator);
    defer anchors.deinit();

    for (doc.anchors) |anchor| try anchors.put(anchor.name, {});
    for (doc.sections) |section| if (section.metadata.id) |id| try anchors.put(id, {});
    for (doc.blocks) |block| if (block.metadata.id) |id| try anchors.put(id, {});

    for (doc.references, 0..) |reference, i| {
        if (!anchors.contains(reference.target)) {
            const msg = try std.fmt.allocPrint(allocator, "Unresolved reference '{s}'", .{reference.target});
            try diags.append(allocator, .{ .level = .err, .subject = .{ .inline_ref = @intCast(i) }, .message = msg });
        }
    }
}

fn checkUniqueIdentifier(
    diags: *std.ArrayList(core.Diagnostic),
    allocator: std.mem.Allocator,
    seen: *std.StringHashMap(core.DiagnosticSubject),
    value: []const u8,
    subject: core.DiagnosticSubject,
    prefix: []const u8,
) !void {
    if (seen.get(value)) |prior| {
        _ = prior;
        const msg = try std.fmt.allocPrint(allocator, "{s}: '{s}'", .{ prefix, value });
        try diags.append(allocator, .{ .level = .err, .subject = subject, .message = msg });
        return;
    }
    try seen.put(value, subject);
}

fn findNodeIndex(doc: core.Document, tag: core.NodeTag, payload_index: u32) ?core.NodeIndex {
    for (doc.nodes, 0..) |entry, i| {
        if (entry.tag == tag and entry.index == payload_index) return @intCast(i);
    }
    return null;
}

fn findInlineIndex(doc: core.Document, tag: core.InlineTag, payload_index: u32) ?core.InlineIndex {
    for (doc.inlines, 0..) |entry, i| {
        if (entry.tag == tag and entry.index == payload_index) return @intCast(i);
    }
    return null;
}

fn validateNodeChildSpan(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document, subject: core.DiagnosticSubject, first: ?core.ChildRefIndex, count: u32) !void {
    if (count == 0) {
        if (first != null) try pushDiag(diags, allocator, .err, subject, "Empty node child span has non-null first ref");
        return;
    }
    if (first == null) {
        try pushDiag(diags, allocator, .err, subject, "Non-empty node child span has null first ref");
        return;
    }
    if (first.? + count > doc.node_child_refs.len) {
        try pushDiag(diags, allocator, .err, subject, "Node child refs out of range");
        return;
    }
    for (core.nodeChildren(doc, first.?, count)) |child_idx| {
        if (child_idx >= doc.nodes.len) try pushDiag(diags, allocator, .err, subject, "Node child index out of range");
    }
}

fn validateInlineChildSpan(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document, subject: core.DiagnosticSubject, first: ?core.InlineChildRefIndex, count: u32) !void {
    if (count == 0) {
        if (first != null) try pushDiag(diags, allocator, .err, subject, "Empty inline child span has non-null first ref");
        return;
    }
    if (first == null) {
        try pushDiag(diags, allocator, .err, subject, "Non-empty inline child span has null first ref");
        return;
    }
    if (first.? + count > doc.inline_child_refs.len) {
        try pushDiag(diags, allocator, .err, subject, "Inline child refs out of range");
        return;
    }
    for (core.inlineChildren(doc, first.?, count)) |child_idx| {
        if (child_idx >= doc.inlines.len) try pushDiag(diags, allocator, .err, subject, "Inline child index out of range");
    }
}

fn validateExpectedChildTags(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, doc: core.Document, subject: core.DiagnosticSubject, first: ?core.ChildRefIndex, count: u32, expected: core.NodeTag) !void {
    if (first == null or count == 0) return;
    for (core.nodeChildren(doc, first.?, count)) |child_idx| {
        if (doc.nodes[child_idx].tag != expected) {
            const msg = try std.fmt.allocPrint(allocator, "Unexpected child tag: expected {s}, got {s}", .{ @tagName(expected), @tagName(doc.nodes[child_idx].tag) });
            try diags.append(allocator, .{ .level = .err, .subject = subject, .message = msg });
        }
    }
}

fn pushDiag(diags: *std.ArrayList(core.Diagnostic), allocator: std.mem.Allocator, level: core.DiagnosticLevel, subject: core.DiagnosticSubject, msg: []const u8) !void {
    try diags.append(allocator, .{ .level = level, .subject = subject, .message = try allocator.dupe(u8, msg) });
}
