const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;
const core = @import("core_ir.zig");

pub fn hashDocument(doc: core.Document) [Blake3.digest_length]u8 {
    var hasher = Blake3.init(.{});
    hashMetadata(&hasher, doc.metadata);
    for (doc.roots) |root_idx| hashNode(&hasher, doc, root_idx);
    var digest: [Blake3.digest_length]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn hashNode(h: *Blake3, doc: core.Document, node_idx: core.NodeIndex) void {
    const entry = doc.nodes[node_idx];
    h.update(&.{@intFromEnum(entry.tag)});
    switch (entry.tag) {
        .section => {
            const s = doc.sections[entry.index];
            hashMetadata(h, s.metadata);
            if (s.title) |title| hashBytes(h, title);
            hashNodeChildren(h, doc, s.first_child_ref, s.child_count);
        },
        .paragraph => {
            const p = doc.paragraphs[entry.index];
            hashInlineChildren(h, doc, p.first_child_ref, p.child_count);
        },
        .list => {
            const l = doc.lists[entry.index];
            h.update(&.{@intFromEnum(l.kind)});
            hashNodeChildren(h, doc, l.first_child_ref, l.child_count);
        },
        .list_item => {
            const li = doc.list_items[entry.index];
            hashNodeChildren(h, doc, li.first_child_ref, li.child_count);
        },
        .table => {
            const t = doc.tables[entry.index];
            hashNodeChildren(h, doc, t.first_child_ref, t.child_count);
        },
        .table_row => {
            const row = doc.rows[entry.index];
            hashNodeChildren(h, doc, row.first_child_ref, row.child_count);
        },
        .table_cell => {
            const cell = doc.cells[entry.index];
            hashNodeChildren(h, doc, cell.first_child_ref, cell.child_count);
        },
        .block => {
            const b = doc.blocks[entry.index];
            hashMetadata(h, b.metadata);
            hashNodeChildren(h, doc, b.first_child_ref, b.child_count);
        },
    }
    h.update(&.{0xFF});
}

fn hashNodeChildren(h: *Blake3, doc: core.Document, first: ?core.ChildRefIndex, count: u32) void {
    if (first == null or count == 0) return;
    for (core.nodeChildren(doc, first.?, count)) |child_idx| hashNode(h, doc, child_idx);
}

fn hashInlineChildren(h: *Blake3, doc: core.Document, first: ?core.InlineChildRefIndex, count: u32) void {
    if (first == null or count == 0) return;
    for (core.inlineChildren(doc, first.?, count)) |child_idx| hashInline(h, doc, child_idx);
}

fn hashInline(h: *Blake3, doc: core.Document, inline_idx: core.InlineIndex) void {
    const entry = doc.inlines[inline_idx];
    h.update(&.{@intFromEnum(entry.tag)});
    switch (entry.tag) {
        .text => hashBytes(h, doc.texts[entry.index].value),
        .link => {
            const l = doc.links[entry.index];
            hashBytes(h, l.target);
            if (l.label) |label_idx| hashInline(h, doc, label_idx);
        },
        .reference => {
            const r = doc.references[entry.index];
            hashBytes(h, r.target);
            if (r.label) |label_idx| hashInline(h, doc, label_idx);
        },
        .anchor => hashBytes(h, doc.anchors[entry.index].name),
        .emphasis => {
            const e = doc.emphases[entry.index];
            hashInlineChildren(h, doc, e.first_child_ref, e.child_count);
        },
        .strong => {
            const s = doc.strongs[entry.index];
            hashInlineChildren(h, doc, s.first_child_ref, s.child_count);
        },
    }
    h.update(&.{0xFE});
}

fn hashMetadata(h: *Blake3, m: core.Metadata) void {
    if (m.id) |id| hashBytes(h, id);
    if (m.title) |title| hashBytes(h, title);
    for (m.roles) |role| hashBytes(h, role);
    for (m.attrs) |attr| {
        hashBytes(h, attr.key);
        hashBytes(h, attr.value);
    }
}

fn hashBytes(h: *Blake3, bytes: []const u8) void {
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(bytes.len), .big);
    h.update(&len_buf);
    h.update(bytes);
}
