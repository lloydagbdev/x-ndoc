const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;

const arena = @import("arena_ir.zig");

const Mark = struct {
    pub const section_open: u8 = 0x01;
    pub const paragraph: u8 = 0x02;
    pub const list_open: u8 = 0x03;
    pub const list_item: u8 = 0x04;
    pub const table_open: u8 = 0x05;
    pub const table_row: u8 = 0x06;
    pub const table_cell: u8 = 0x07;
    pub const block_open: u8 = 0x08;

    pub const text: u8 = 0x10;
    pub const link: u8 = 0x11;
    pub const reference: u8 = 0x12;
    pub const anchor: u8 = 0x13;
    pub const emphasis_open: u8 = 0x14;
    pub const strong_open: u8 = 0x15;

    pub const meta_id: u8 = 0x20;
    pub const meta_title: u8 = 0x21;
    pub const meta_role: u8 = 0x22;
    pub const meta_attr_key: u8 = 0x23;
    pub const meta_attr_val: u8 = 0x24;

    pub const list_ordered: u8 = 0x30;
    pub const list_unordered: u8 = 0x31;
    pub const list_task: u8 = 0x32;
    pub const list_description: u8 = 0x33;

    pub const end: u8 = 0xFF;
};

pub fn hashDocument(doc: arena.DocumentArena) [Blake3.digest_length]u8 {
    var hasher = Blake3.init(.{});

    hashMetadata(&hasher, doc.metadata);

    for (doc.roots) |root_idx| {
        hashNode(&hasher, doc, root_idx);
    }

    var digest: [Blake3.digest_length]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn hashNode(h: *Blake3, doc: arena.DocumentArena, node_idx: arena.NodeIndex) void {
    const entry = doc.nodes[node_idx];
    switch (entry.tag) {
        .section => {
            const s = doc.sections[entry.index];
            h.update(&.{Mark.section_open});
            hashMetadata(h, s.metadata);
            if (s.title) |t| {
                h.update(&.{Mark.meta_title});
                hashBytes(h, t);
            }
            if (s.child_count > 0) {
                const children = arena.childSlice(doc, s.first_child.?, s.child_count);
                for (children, 0..) |_, i| {
                    hashNode(h, doc, s.first_child.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
        .paragraph => {
            const p = doc.paragraphs[entry.index];
            h.update(&.{Mark.paragraph});
            if (p.inline_count > 0) {
                const inlines = arena.childInlineSlice(doc, p.first_inline.?, p.inline_count);
                for (inlines) |inline_entry| {
                    hashInline(h, doc, inline_entry);
                }
            }
            h.update(&.{Mark.end});
        },
        .list => {
            const l = doc.lists[entry.index];
            h.update(&.{Mark.list_open});
            h.update(&.{switch (l.kind) {
                .ordered => Mark.list_ordered,
                .unordered => Mark.list_unordered,
                .task => Mark.list_task,
                .description => Mark.list_description,
            }});
            if (l.item_count > 0) {
                for (0..l.item_count) |i| {
                    hashNode(h, doc, l.first_item.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
        .list_item => {
            const li = doc.list_items[entry.index];
            h.update(&.{Mark.list_item});
            if (li.child_count > 0) {
                for (0..li.child_count) |i| {
                    hashNode(h, doc, li.first_child.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
        .table => {
            const t = doc.tables[entry.index];
            h.update(&.{Mark.table_open});
            if (t.row_count > 0) {
                for (0..t.row_count) |i| {
                    hashNode(h, doc, t.first_row.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
        .table_row => {
            const r = doc.rows[entry.index];
            h.update(&.{Mark.table_row});
            if (r.cell_count > 0) {
                for (0..r.cell_count) |i| {
                    hashNode(h, doc, r.first_cell.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
        .table_cell => {
            const c = doc.cells[entry.index];
            h.update(&.{Mark.table_cell});
            if (c.child_count > 0) {
                for (0..c.child_count) |i| {
                    hashNode(h, doc, c.first_child.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
        .block => {
            const b = doc.blocks[entry.index];
            h.update(&.{Mark.block_open});
            hashMetadata(h, b.metadata);
            if (b.child_count > 0) {
                for (0..b.child_count) |i| {
                    hashNode(h, doc, b.first_child.? + @as(arena.NodeIndex, @intCast(i)));
                }
            }
            h.update(&.{Mark.end});
        },
    }
}

fn hashInline(h: *Blake3, doc: arena.DocumentArena, entry: arena.InlineEntry) void {
    switch (entry.tag) {
        .text => {
            h.update(&.{Mark.text});
            hashBytes(h, doc.texts[entry.index].value);
        },
        .link => {
            const l = doc.links[entry.index];
            h.update(&.{Mark.link});
            hashBytes(h, l.target);
            if (l.label) |label_idx| {
                if (label_idx < doc.inlines.len and doc.inlines[label_idx].tag == .text) {
                    hashBytes(h, doc.texts[doc.inlines[label_idx].index].value);
                }
            }
        },
        .reference => {
            const r = doc.references[entry.index];
            h.update(&.{Mark.reference});
            hashBytes(h, r.target);
            if (r.label) |label_idx| {
                if (label_idx < doc.inlines.len and doc.inlines[label_idx].tag == .text) {
                    hashBytes(h, doc.texts[doc.inlines[label_idx].index].value);
                }
            }
        },
        .anchor => {
            h.update(&.{Mark.anchor});
            hashBytes(h, doc.anchors[entry.index].name);
        },
        .emphasis => {
            const e = doc.emphases[entry.index];
            h.update(&.{Mark.emphasis_open});
            if (e.inline_count > 0) {
                const inlines = arena.childInlineSlice(doc, e.first_inline.?, e.inline_count);
                for (inlines) |inline_entry| {
                    hashInline(h, doc, inline_entry);
                }
            }
            h.update(&.{Mark.end});
        },
        .strong => {
            const s = doc.strongs[entry.index];
            h.update(&.{Mark.strong_open});
            if (s.inline_count > 0) {
                const inlines = arena.childInlineSlice(doc, s.first_inline.?, s.inline_count);
                for (inlines) |inline_entry| {
                    hashInline(h, doc, inline_entry);
                }
            }
            h.update(&.{Mark.end});
        },
    }
}

fn hashMetadata(h: *Blake3, m: arena.Metadata) void {
    if (m.id) |id| {
        h.update(&.{Mark.meta_id});
        hashBytes(h, id);
    }
    if (m.title) |title| {
        h.update(&.{Mark.meta_title});
        hashBytes(h, title);
    }
    for (m.roles) |role| {
        h.update(&.{Mark.meta_role});
        hashBytes(h, role);
    }
    if (m.attrs.len > 0) {
        const sorted = sortedAttrs(m.attrs);
        for (sorted) |attr| {
            h.update(&.{Mark.meta_attr_key});
            hashBytes(h, attr.key);
            h.update(&.{Mark.meta_attr_val});
            hashBytes(h, attr.value);
        }
    }
}

fn sortedAttrs(attrs: []const arena.KVPair) []const arena.KVPair {
    return attrs;
}

fn hashInt32(h: *Blake3, value: u32) void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .big);
    h.update(&buf);
}

fn hashBytes(h: *Blake3, bytes: []const u8) void {
    hashInt32(h, @intCast(bytes.len));
    h.update(bytes);
}
