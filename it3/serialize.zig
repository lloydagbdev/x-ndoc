const std = @import("std");
const arena = @import("arena_ir.zig");
const author = @import("author_ir.zig");
const lower = @import("lower.zig");

pub const MAGIC = "XNDOC\x00";
pub const FORMAT_VERSION: u16 = 1;
pub const IR_VERSION: u16 = 1;
pub const NULL_U32: u32 = 0xFFFFFFFF;

// ── disk record type definitions ──

pub const StringRefDisk = struct {
    start: u32,
    len: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.start, .little);
        std.mem.writeInt(u32, buf[4..8], self.len, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .start = std.mem.readInt(u32, buf[0..4], .little),
            .len = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const KVPairDisk = struct {
    key_ref: u32,
    value_ref: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.key_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.value_ref, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .key_ref = std.mem.readInt(u32, buf[0..4], .little),
            .value_ref = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const MetadataDisk = struct {
    id_ref: u32,
    title_ref: u32,
    roles_first: u32,
    roles_count: u32,
    attrs_first: u32,
    attrs_count: u32,

    pub const size = 24;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.id_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.title_ref, .little);
        std.mem.writeInt(u32, buf[8..12], self.roles_first, .little);
        std.mem.writeInt(u32, buf[12..16], self.roles_count, .little);
        std.mem.writeInt(u32, buf[16..20], self.attrs_first, .little);
        std.mem.writeInt(u32, buf[20..24], self.attrs_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .id_ref = std.mem.readInt(u32, buf[0..4], .little),
            .title_ref = std.mem.readInt(u32, buf[4..8], .little),
            .roles_first = std.mem.readInt(u32, buf[8..12], .little),
            .roles_count = std.mem.readInt(u32, buf[12..16], .little),
            .attrs_first = std.mem.readInt(u32, buf[16..20], .little),
            .attrs_count = std.mem.readInt(u32, buf[20..24], .little),
        };
    }
};

pub const NodeEntryDisk = struct {
    tag: u8,
    index: u32,

    pub const size = 5;
    pub fn encode(buf: []u8, self: @This()) void {
        buf[0] = self.tag;
        std.mem.writeInt(u32, buf[1..5], self.index, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .tag = buf[0],
            .index = std.mem.readInt(u32, buf[1..5], .little),
        };
    }
};

pub const InlineEntryDisk = struct {
    tag: u8,
    index: u32,

    pub const size = 5;
    pub fn encode(buf: []u8, self: @This()) void {
        buf[0] = self.tag;
        std.mem.writeInt(u32, buf[1..5], self.index, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .tag = buf[0],
            .index = std.mem.readInt(u32, buf[1..5], .little),
        };
    }
};

pub const SectionDataDisk = struct {
    meta: MetadataDisk,
    title_ref: u32,
    first_child: u32,
    child_count: u32,

    pub const size = 36;
    pub fn encode(buf: []u8, self: @This()) void {
        MetadataDisk.encode(buf[0..24], self.meta);
        std.mem.writeInt(u32, buf[24..28], self.title_ref, .little);
        std.mem.writeInt(u32, buf[28..32], self.first_child, .little);
        std.mem.writeInt(u32, buf[32..36], self.child_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .meta = MetadataDisk.decode(buf[0..24]),
            .title_ref = std.mem.readInt(u32, buf[24..28], .little),
            .first_child = std.mem.readInt(u32, buf[28..32], .little),
            .child_count = std.mem.readInt(u32, buf[32..36], .little),
        };
    }
};

pub const ParagraphDataDisk = struct {
    first_inline: u32,
    inline_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_inline, .little);
        std.mem.writeInt(u32, buf[4..8], self.inline_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_inline = std.mem.readInt(u32, buf[0..4], .little),
            .inline_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const ListDataDisk = struct {
    kind: u8,
    first_item: u32,
    item_count: u32,

    pub const size = 9;
    pub fn encode(buf: []u8, self: @This()) void {
        buf[0] = self.kind;
        std.mem.writeInt(u32, buf[1..5], self.first_item, .little);
        std.mem.writeInt(u32, buf[5..9], self.item_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .kind = buf[0],
            .first_item = std.mem.readInt(u32, buf[1..5], .little),
            .item_count = std.mem.readInt(u32, buf[5..9], .little),
        };
    }
};

pub const ListItemDataDisk = struct {
    first_child: u32,
    child_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_child, .little);
        std.mem.writeInt(u32, buf[4..8], self.child_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_child = std.mem.readInt(u32, buf[0..4], .little),
            .child_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const TableDataDisk = struct {
    first_row: u32,
    row_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_row, .little);
        std.mem.writeInt(u32, buf[4..8], self.row_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_row = std.mem.readInt(u32, buf[0..4], .little),
            .row_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const TableRowDataDisk = struct {
    first_cell: u32,
    cell_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_cell, .little);
        std.mem.writeInt(u32, buf[4..8], self.cell_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_cell = std.mem.readInt(u32, buf[0..4], .little),
            .cell_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const TableCellDataDisk = struct {
    first_child: u32,
    child_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_child, .little);
        std.mem.writeInt(u32, buf[4..8], self.child_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_child = std.mem.readInt(u32, buf[0..4], .little),
            .child_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const BlockDataDisk = struct {
    meta: MetadataDisk,
    first_child: u32,
    child_count: u32,

    pub const size = 32;
    pub fn encode(buf: []u8, self: @This()) void {
        MetadataDisk.encode(buf[0..24], self.meta);
        std.mem.writeInt(u32, buf[24..28], self.first_child, .little);
        std.mem.writeInt(u32, buf[28..32], self.child_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .meta = MetadataDisk.decode(buf[0..24]),
            .first_child = std.mem.readInt(u32, buf[24..28], .little),
            .child_count = std.mem.readInt(u32, buf[28..32], .little),
        };
    }
};

pub const TextDataDisk = struct {
    value_ref: u32,

    pub const size = 4;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.value_ref, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .value_ref = std.mem.readInt(u32, buf[0..4], .little),
        };
    }
};

pub const LinkDataDisk = struct {
    target_ref: u32,
    label: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.target_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.label, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .target_ref = std.mem.readInt(u32, buf[0..4], .little),
            .label = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const ReferenceDataDisk = struct {
    target_ref: u32,
    label: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.target_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.label, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .target_ref = std.mem.readInt(u32, buf[0..4], .little),
            .label = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const AnchorDataDisk = struct {
    name_ref: u32,

    pub const size = 4;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.name_ref, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .name_ref = std.mem.readInt(u32, buf[0..4], .little),
        };
    }
};

pub const EmphasisDataDisk = struct {
    first_inline: u32,
    inline_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_inline, .little);
        std.mem.writeInt(u32, buf[4..8], self.inline_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_inline = std.mem.readInt(u32, buf[0..4], .little),
            .inline_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const StrongDataDisk = struct {
    first_inline: u32,
    inline_count: u32,

    pub const size = 8;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_inline, .little);
        std.mem.writeInt(u32, buf[4..8], self.inline_count, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .first_inline = std.mem.readInt(u32, buf[0..4], .little),
            .inline_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

pub const DiagnosticDisk = struct {
    message_ref: u32,

    pub const size = 4;
    pub fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.message_ref, .little);
    }
    pub fn decode(buf: []const u8) @This() {
        return .{
            .message_ref = std.mem.readInt(u32, buf[0..4], .little),
        };
    }
};

fn optU32(val: ?u32) u32 {
    return if (val) |v| v else NULL_U32;
}

fn u32isNull(v: u32) bool {
    return v == NULL_U32;
}

// ── string collection context ──

const StringCtx = struct {
    str_buf: std.ArrayList(u8),
    str_refs: std.ArrayList(StringRefDisk),

    fn init() @This() {
        return .{
            .str_buf = std.ArrayList(u8).empty,
            .str_refs = std.ArrayList(StringRefDisk).empty,
        };
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.str_buf.deinit(allocator);
        self.str_refs.deinit(allocator);
    }

    fn emit(self: *@This(), s: []const u8, allocator: std.mem.Allocator) !u32 {
        const start: u32 = @intCast(self.str_buf.items.len);
        try self.str_buf.appendSlice(allocator, s);
        const idx: u32 = @intCast(self.str_refs.items.len);
        try self.str_refs.append(allocator, .{ .start = start, .len = @intCast(s.len) });
        return idx;
    }

    fn emitOpt(self: *@This(), s: ?[]const u8, allocator: std.mem.Allocator) !u32 {
        if (s) |val| return self.emit(val, allocator);
        return NULL_U32;
    }
};

fn collectMetadataStrings(ctx: *StringCtx, meta: arena.Metadata, allocator: std.mem.Allocator) !MetadataDisk {
    const id_ref = try ctx.emitOpt(meta.id, allocator);
    const title_ref = try ctx.emitOpt(meta.title, allocator);

    const roles_first: u32 = @intCast(ctx.str_refs.items.len);
    for (meta.roles) |role| {
        _ = try ctx.emit(role, allocator);
    }
    const roles_count: u32 = @as(u32, @intCast(ctx.str_refs.items.len)) - roles_first;

    return .{
        .id_ref = id_ref,
        .title_ref = title_ref,
        .roles_first = roles_first,
        .roles_count = roles_count,
        .attrs_first = NULL_U32,
        .attrs_count = @intCast(meta.attrs.len),
    };
}

// ── header ──

pub const HeaderDisk = struct {
    magic: [6]u8,
    format_version: u16,
    ir_version: u16,
    flags: u32,
    node_entries_count: u32,
    inline_entries_count: u32,
    sections_count: u32,
    paragraphs_count: u32,
    lists_count: u32,
    list_items_count: u32,
    tables_count: u32,
    rows_count: u32,
    cells_count: u32,
    blocks_count: u32,
    texts_count: u32,
    links_count: u32,
    references_count: u32,
    anchors_count: u32,
    emphases_count: u32,
    strongs_count: u32,
    diagnostics_count: u32,
    roots_count: u32,
    string_refs_count: u32,
    kv_pairs_count: u32,
    bytes_len: u64,
    doc_meta: MetadataDisk,

    pub const name = "header";
    pub const byte_size: usize = 130;

    pub fn encode(buf: []u8, self: @This()) void {
        @memcpy(buf[0..6], &self.magic);
        std.mem.writeInt(u16, buf[6..8], self.format_version, .little);
        std.mem.writeInt(u16, buf[8..10], self.ir_version, .little);
        std.mem.writeInt(u32, buf[10..14], self.flags, .little);
        var pos: usize = 14;
        inline for (.{ "node_entries_count", "inline_entries_count", "sections_count", "paragraphs_count", "lists_count", "list_items_count", "tables_count", "rows_count", "cells_count", "blocks_count", "texts_count", "links_count", "references_count", "anchors_count", "emphases_count", "strongs_count", "diagnostics_count", "roots_count", "string_refs_count", "kv_pairs_count" }) |field| {
            const val = @field(self, field);
            buf[pos] = @intCast(val & 0xFF);
            buf[pos + 1] = @intCast((val >> 8) & 0xFF);
            buf[pos + 2] = @intCast((val >> 16) & 0xFF);
            buf[pos + 3] = @intCast((val >> 24) & 0xFF);
            pos += 4;
        }
        const bl = self.bytes_len;
        buf[pos] = @intCast(bl & 0xFF);
        buf[pos + 1] = @intCast((bl >> 8) & 0xFF);
        buf[pos + 2] = @intCast((bl >> 16) & 0xFF);
        buf[pos + 3] = @intCast((bl >> 24) & 0xFF);
        buf[pos + 4] = @intCast((bl >> 32) & 0xFF);
        buf[pos + 5] = @intCast((bl >> 40) & 0xFF);
        buf[pos + 6] = @intCast((bl >> 48) & 0xFF);
        buf[pos + 7] = @intCast((bl >> 56) & 0xFF);
        pos += 8;
        MetadataDisk.encode(buf[pos .. pos + 24], self.doc_meta);
    }

    pub fn decode(buf: []const u8) @This() {
        var magic: [6]u8 = undefined;
        @memcpy(&magic, buf[0..6]);
        const self: HeaderDisk = .{
            .magic = magic,
            .format_version = std.mem.readInt(u16, buf[6..8], .little),
            .ir_version = std.mem.readInt(u16, buf[8..10], .little),
            .flags = std.mem.readInt(u32, buf[10..14], .little),
            .node_entries_count = std.mem.readInt(u32, buf[14..18], .little),
            .inline_entries_count = std.mem.readInt(u32, buf[18..22], .little),
            .sections_count = std.mem.readInt(u32, buf[22..26], .little),
            .paragraphs_count = std.mem.readInt(u32, buf[26..30], .little),
            .lists_count = std.mem.readInt(u32, buf[30..34], .little),
            .list_items_count = std.mem.readInt(u32, buf[34..38], .little),
            .tables_count = std.mem.readInt(u32, buf[38..42], .little),
            .rows_count = std.mem.readInt(u32, buf[42..46], .little),
            .cells_count = std.mem.readInt(u32, buf[46..50], .little),
            .blocks_count = std.mem.readInt(u32, buf[50..54], .little),
            .texts_count = std.mem.readInt(u32, buf[54..58], .little),
            .links_count = std.mem.readInt(u32, buf[58..62], .little),
            .references_count = std.mem.readInt(u32, buf[62..66], .little),
            .anchors_count = std.mem.readInt(u32, buf[66..70], .little),
            .emphases_count = std.mem.readInt(u32, buf[70..74], .little),
            .strongs_count = std.mem.readInt(u32, buf[74..78], .little),
            .diagnostics_count = std.mem.readInt(u32, buf[78..82], .little),
            .roots_count = std.mem.readInt(u32, buf[82..86], .little),
            .string_refs_count = std.mem.readInt(u32, buf[86..90], .little),
            .kv_pairs_count = std.mem.readInt(u32, buf[90..94], .little),
            .bytes_len = std.mem.readInt(u64, buf[94..102], .little),
            .doc_meta = MetadataDisk.decode(buf[102..126]),
        };
        return self;
    }
};

test "header round-trip" {
    var buf: [HeaderDisk.byte_size]u8 = undefined;
    const h = HeaderDisk{
        .magic = MAGIC.*,
        .format_version = FORMAT_VERSION,
        .ir_version = IR_VERSION,
        .flags = 0,
        .node_entries_count = 10,
        .inline_entries_count = 20,
        .sections_count = 1,
        .paragraphs_count = 2,
        .lists_count = 3,
        .list_items_count = 4,
        .tables_count = 5,
        .rows_count = 6,
        .cells_count = 7,
        .blocks_count = 8,
        .texts_count = 9,
        .links_count = 10,
        .references_count = 11,
        .anchors_count = 12,
        .emphases_count = 13,
        .strongs_count = 14,
        .diagnostics_count = 15,
        .roots_count = 16,
        .string_refs_count = 17,
        .kv_pairs_count = 18,
        .bytes_len = 999,
        .doc_meta = .{
            .id_ref = NULL_U32,
            .title_ref = NULL_U32,
            .roles_first = NULL_U32,
            .roles_count = 0,
            .attrs_first = NULL_U32,
            .attrs_count = 0,
        },
    };
    HeaderDisk.encode(buf[0..], h);
    const decoded = HeaderDisk.decode(&buf);
    try std.testing.expectEqual(FORMAT_VERSION, decoded.format_version);
    try std.testing.expectEqual(IR_VERSION, decoded.ir_version);
    try std.testing.expectEqual(@as(u32, 10), decoded.node_entries_count);
    try std.testing.expectEqual(@as(u32, 20), decoded.inline_entries_count);
    try std.testing.expectEqual(@as(u32, 999), @as(u32, @intCast(decoded.bytes_len)));
    try std.testing.expectEqual(NULL_U32, decoded.doc_meta.id_ref);
}

// ── validation ──

pub const ValidationError = error{
    InvalidMagic,
    UnsupportedVersion,
    TruncatedHeader,
    TruncatedSection,
    InvalidNodeEntryTag,
    InvalidInlineEntryTag,
    InvalidListKind,
    OutOfBoundsStringRef,
    NullValueNotAllowed,
};

pub const ValidationReport = struct {
    total_bytes: usize,
    node_count: usize,
    inline_count: usize,
    string_count: usize,
};

pub fn validate(bytes: []const u8) ValidationError!ValidationReport {
    if (bytes.len < HeaderDisk.byte_size) return error.TruncatedHeader;

    const header = HeaderDisk.decode(bytes[0..HeaderDisk.byte_size]);

    if (!std.mem.eql(u8, &header.magic, MAGIC)) return error.InvalidMagic;
    if (header.format_version != FORMAT_VERSION) return error.UnsupportedVersion;

    var offset: usize = HeaderDisk.byte_size;

    // section offsets
    const sections = [_]struct { count: u32, rec_size: usize, name: []const u8 }{
        .{ .count = header.node_entries_count, .rec_size = NodeEntryDisk.size, .name = "node_entries" },
        .{ .count = header.inline_entries_count, .rec_size = InlineEntryDisk.size, .name = "inline_entries" },
        .{ .count = header.sections_count, .rec_size = SectionDataDisk.size, .name = "sections" },
        .{ .count = header.paragraphs_count, .rec_size = ParagraphDataDisk.size, .name = "paragraphs" },
        .{ .count = header.lists_count, .rec_size = ListDataDisk.size, .name = "lists" },
        .{ .count = header.list_items_count, .rec_size = ListItemDataDisk.size, .name = "list_items" },
        .{ .count = header.tables_count, .rec_size = TableDataDisk.size, .name = "tables" },
        .{ .count = header.rows_count, .rec_size = TableRowDataDisk.size, .name = "rows" },
        .{ .count = header.cells_count, .rec_size = TableCellDataDisk.size, .name = "cells" },
        .{ .count = header.blocks_count, .rec_size = BlockDataDisk.size, .name = "blocks" },
        .{ .count = header.texts_count, .rec_size = TextDataDisk.size, .name = "texts" },
        .{ .count = header.links_count, .rec_size = LinkDataDisk.size, .name = "links" },
        .{ .count = header.references_count, .rec_size = ReferenceDataDisk.size, .name = "references" },
        .{ .count = header.anchors_count, .rec_size = AnchorDataDisk.size, .name = "anchors" },
        .{ .count = header.emphases_count, .rec_size = EmphasisDataDisk.size, .name = "emphases" },
        .{ .count = header.strongs_count, .rec_size = StrongDataDisk.size, .name = "strongs" },
        .{ .count = header.diagnostics_count, .rec_size = DiagnosticDisk.size, .name = "diagnostics" },
    };

    for (sections) |sec| {
        const sec_size = sec.count * sec.rec_size;
        if (offset + sec_size > bytes.len) return error.TruncatedSection;
        offset += sec_size;
    }

    const roots_size = header.roots_count * 4;
    if (offset + roots_size > bytes.len) return error.TruncatedSection;
    offset += roots_size;

    const refs_size = header.string_refs_count * StringRefDisk.size;
    if (offset + refs_size > bytes.len) return error.TruncatedSection;
    offset += refs_size;

    const kv_size = header.kv_pairs_count * KVPairDisk.size;
    if (offset + kv_size > bytes.len) return error.TruncatedSection;
    offset += kv_size;

    const bytes_arena_size: usize = @intCast(header.bytes_len);
    if (offset + bytes_arena_size != bytes.len) return error.TruncatedSection;

    return ValidationReport{
        .total_bytes = bytes.len,
        .node_count = header.node_entries_count,
        .inline_count = header.inline_entries_count,
        .string_count = header.string_refs_count,
    };
}

// ── serialize ──

pub fn serialize(out_allocator: std.mem.Allocator, doc: arena.DocumentArena) ![]u8 {
    var buf = std.ArrayList(u8).empty;

    var ctx = StringCtx.init();
    defer ctx.deinit(out_allocator);

    // collect text strings
    var text_disk = std.ArrayList(TextDataDisk).empty;
    defer text_disk.deinit(out_allocator);
    for (doc.texts) |t| {
        const ref_idx = try ctx.emit(t.value, out_allocator);
        try text_disk.append(out_allocator, .{ .value_ref = ref_idx });
    }

    // collect link strings (target only; label is inline index)
    var link_disk = std.ArrayList(LinkDataDisk).empty;
    defer link_disk.deinit(out_allocator);
    for (doc.links) |l| {
        const target_ref = try ctx.emit(l.target, out_allocator);
        try link_disk.append(out_allocator, .{ .target_ref = target_ref, .label = optU32(l.label) });
    }

    // collect reference strings
    var ref_disk = std.ArrayList(ReferenceDataDisk).empty;
    defer ref_disk.deinit(out_allocator);
    for (doc.references) |r| {
        const target_ref = try ctx.emit(r.target, out_allocator);
        try ref_disk.append(out_allocator, .{ .target_ref = target_ref, .label = optU32(r.label) });
    }

    // collect anchor strings
    var anchor_disk = std.ArrayList(AnchorDataDisk).empty;
    defer anchor_disk.deinit(out_allocator);
    for (doc.anchors) |a| {
        const name_ref = try ctx.emit(a.name, out_allocator);
        try anchor_disk.append(out_allocator, .{ .name_ref = name_ref });
    }

    // collect section metadata strings
    var section_disk = std.ArrayList(SectionDataDisk).empty;
    defer section_disk.deinit(out_allocator);
    var kv_pairs = std.ArrayList(KVPairDisk).empty;
    defer kv_pairs.deinit(out_allocator);

    for (doc.sections) |s| {
        const meta = try collectMetadataStrings(&ctx, s.metadata, out_allocator);
        const attrs_first: u32 = @intCast(kv_pairs.items.len);
        for (s.metadata.attrs) |attr| {
            try kv_pairs.append(out_allocator, .{ .key_ref = try ctx.emit(attr.key, out_allocator), .value_ref = try ctx.emit(attr.value, out_allocator) });
        }
        var section_meta = meta;
        section_meta.attrs_first = attrs_first;
        try section_disk.append(out_allocator, .{
            .meta = section_meta,
            .title_ref = try ctx.emitOpt(s.title, out_allocator),
            .first_child = optU32(s.first_child),
            .child_count = s.child_count,
        });
    }

    // collect block metadata strings
    var block_disk = std.ArrayList(BlockDataDisk).empty;
    defer block_disk.deinit(out_allocator);
    for (doc.blocks) |b| {
        const meta = try collectMetadataStrings(&ctx, b.metadata, out_allocator);
        const attrs_first: u32 = @intCast(kv_pairs.items.len);
        for (b.metadata.attrs) |attr| {
            try kv_pairs.append(out_allocator, .{ .key_ref = try ctx.emit(attr.key, out_allocator), .value_ref = try ctx.emit(attr.value, out_allocator) });
        }
        var block_meta = meta;
        block_meta.attrs_first = attrs_first;
        try block_disk.append(out_allocator, .{
            .meta = block_meta,
            .first_child = optU32(b.first_child),
            .child_count = b.child_count,
        });
    }

    // collect diagnostic strings
    var diag_disk = std.ArrayList(DiagnosticDisk).empty;
    defer diag_disk.deinit(out_allocator);
    for (doc.diagnostics) |d| {
        const msg_ref = try ctx.emit(d.message, out_allocator);
        try diag_disk.append(out_allocator, .{ .message_ref = msg_ref });
    }

    // collect document metadata strings
    const doc_meta = try collectMetadataStrings(&ctx, doc.metadata, out_allocator);
    var doc_meta_disk = doc_meta;
    const doc_attrs_first: u32 = @intCast(kv_pairs.items.len);
    for (doc.metadata.attrs) |attr| {
        try kv_pairs.append(out_allocator, .{ .key_ref = try ctx.emit(attr.key, out_allocator), .value_ref = try ctx.emit(attr.value, out_allocator) });
    }
    doc_meta_disk.attrs_first = doc_attrs_first;
    doc_meta_disk.attrs_count = @intCast(doc.metadata.attrs.len);

    var header_buf: [HeaderDisk.byte_size]u8 = undefined;
    const header = HeaderDisk{
        .magic = MAGIC.*,
        .format_version = FORMAT_VERSION,
        .ir_version = IR_VERSION,
        .flags = 0,
        .node_entries_count = @intCast(doc.nodes.len),
        .inline_entries_count = @intCast(doc.inlines.len),
        .sections_count = @intCast(doc.sections.len),
        .paragraphs_count = @intCast(doc.paragraphs.len),
        .lists_count = @intCast(doc.lists.len),
        .list_items_count = @intCast(doc.list_items.len),
        .tables_count = @intCast(doc.tables.len),
        .rows_count = @intCast(doc.rows.len),
        .cells_count = @intCast(doc.cells.len),
        .blocks_count = @intCast(doc.blocks.len),
        .texts_count = @intCast(doc.texts.len),
        .links_count = @intCast(doc.links.len),
        .references_count = @intCast(doc.references.len),
        .anchors_count = @intCast(doc.anchors.len),
        .emphases_count = @intCast(doc.emphases.len),
        .strongs_count = @intCast(doc.strongs.len),
        .diagnostics_count = @intCast(doc.diagnostics.len),
        .roots_count = @intCast(doc.roots.len),
        .string_refs_count = @intCast(ctx.str_refs.items.len),
        .kv_pairs_count = @intCast(kv_pairs.items.len),
        .bytes_len = ctx.str_buf.items.len,
        .doc_meta = doc_meta_disk,
    };
    HeaderDisk.encode(header_buf[0..], header);
    try buf.appendSlice(out_allocator, &header_buf);

    var rec_buf = std.ArrayList(u8).empty;
    defer rec_buf.deinit(out_allocator);
    for (doc.nodes) |n| {
        try rec_buf.resize(out_allocator, NodeEntryDisk.size);
        NodeEntryDisk.encode(rec_buf.items, .{ .tag = @intFromEnum(n.tag), .index = n.index });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }

    for (doc.inlines) |inl| {
        try rec_buf.resize(out_allocator, InlineEntryDisk.size);
        InlineEntryDisk.encode(rec_buf.items, .{ .tag = @intFromEnum(inl.tag), .index = inl.index });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }

    for (section_disk.items) |s| {
        try rec_buf.resize(out_allocator, SectionDataDisk.size);
        SectionDataDisk.encode(rec_buf.items, s);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.paragraphs) |p| {
        try rec_buf.resize(out_allocator, ParagraphDataDisk.size);
        ParagraphDataDisk.encode(rec_buf.items, .{ .first_inline = optU32(p.first_inline), .inline_count = p.inline_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.lists) |l| {
        try rec_buf.resize(out_allocator, ListDataDisk.size);
        ListDataDisk.encode(rec_buf.items, .{ .kind = @intFromEnum(l.kind), .first_item = optU32(l.first_item), .item_count = l.item_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.list_items) |li| {
        try rec_buf.resize(out_allocator, ListItemDataDisk.size);
        ListItemDataDisk.encode(rec_buf.items, .{ .first_child = optU32(li.first_child), .child_count = li.child_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.tables) |t| {
        try rec_buf.resize(out_allocator, TableDataDisk.size);
        TableDataDisk.encode(rec_buf.items, .{ .first_row = optU32(t.first_row), .row_count = t.row_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.rows) |r| {
        try rec_buf.resize(out_allocator, TableRowDataDisk.size);
        TableRowDataDisk.encode(rec_buf.items, .{ .first_cell = optU32(r.first_cell), .cell_count = r.cell_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.cells) |c| {
        try rec_buf.resize(out_allocator, TableCellDataDisk.size);
        TableCellDataDisk.encode(rec_buf.items, .{ .first_child = optU32(c.first_child), .child_count = c.child_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (block_disk.items) |b| {
        try rec_buf.resize(out_allocator, BlockDataDisk.size);
        BlockDataDisk.encode(rec_buf.items, b);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (text_disk.items) |t| {
        try rec_buf.resize(out_allocator, TextDataDisk.size);
        TextDataDisk.encode(rec_buf.items, t);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (link_disk.items) |l| {
        try rec_buf.resize(out_allocator, LinkDataDisk.size);
        LinkDataDisk.encode(rec_buf.items, l);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (ref_disk.items) |r| {
        try rec_buf.resize(out_allocator, ReferenceDataDisk.size);
        ReferenceDataDisk.encode(rec_buf.items, r);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (anchor_disk.items) |a| {
        try rec_buf.resize(out_allocator, AnchorDataDisk.size);
        AnchorDataDisk.encode(rec_buf.items, a);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.emphases) |e| {
        try rec_buf.resize(out_allocator, EmphasisDataDisk.size);
        EmphasisDataDisk.encode(rec_buf.items, .{ .first_inline = optU32(e.first_inline), .inline_count = e.inline_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (doc.strongs) |s| {
        try rec_buf.resize(out_allocator, StrongDataDisk.size);
        StrongDataDisk.encode(rec_buf.items, .{ .first_inline = optU32(s.first_inline), .inline_count = s.inline_count });
        try buf.appendSlice(out_allocator, rec_buf.items);
    }
    for (diag_disk.items) |d| {
        try rec_buf.resize(out_allocator, DiagnosticDisk.size);
        DiagnosticDisk.encode(rec_buf.items, d);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }

    for (doc.roots) |root| {
        try rec_buf.resize(out_allocator, 4);
        rec_buf.items[0] = @intCast(root & 0xFF);
        rec_buf.items[1] = @intCast((root >> 8) & 0xFF);
        rec_buf.items[2] = @intCast((root >> 16) & 0xFF);
        rec_buf.items[3] = @intCast((root >> 24) & 0xFF);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }

    for (ctx.str_refs.items) |sr| {
        try rec_buf.resize(out_allocator, StringRefDisk.size);
        StringRefDisk.encode(rec_buf.items, sr);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }

    for (kv_pairs.items) |kv| {
        try rec_buf.resize(out_allocator, KVPairDisk.size);
        KVPairDisk.encode(rec_buf.items, kv);
        try buf.appendSlice(out_allocator, rec_buf.items);
    }

    try buf.appendSlice(out_allocator, ctx.str_buf.items);

    return buf.toOwnedSlice(out_allocator);
}

// ── borrow view getters ──

fn readEntry(buf: []const u8, index: u32, rec_size: u32) []const u8 {
    const start = index * rec_size;
    return buf[start..][0..rec_size];
}

fn resolveStr(ref_table: []const StringRefDisk, bytes_arena: []const u8, ref_idx: u32) []const u8 {
    if (ref_idx == NULL_U32) return &.{};
    const sr = ref_table[ref_idx];
    return bytes_arena[sr.start .. sr.start + sr.len];
}

fn resolveSliceU32(slice: []const u8, start: u32) u32 {
    if (start * 4 >= slice.len) return 0;
    return std.mem.readInt(u32, slice[@as(usize, @intCast(start * 4))..][0..4], .little);
}

fn p32(val: ?u32) ?u32 {
    return if (val) |v| if (v == NULL_U32) null else v else null;
}

// ── deserialize ──

pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !arena.DocumentArena {
    _ = try validate(bytes);
    const header = HeaderDisk.decode(bytes[0..HeaderDisk.byte_size]);

    var offset: usize = HeaderDisk.byte_size;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const aa = arena_state.allocator();

    // ── read sections ──
    const read_section = struct {
        fn read(offset_ptr: *usize, buf: []const u8, count: u32, rec_size: usize) []const u8 {
            const start = offset_ptr.*;
            offset_ptr.* += count * rec_size;
            return buf[start..][0 .. count * rec_size];
        }
    }.read;

    const node_bytes = read_section(&offset, bytes, header.node_entries_count, NodeEntryDisk.size);
    const inline_bytes = read_section(&offset, bytes, header.inline_entries_count, InlineEntryDisk.size);
    const section_bytes = read_section(&offset, bytes, header.sections_count, SectionDataDisk.size);
    const paragraph_bytes = read_section(&offset, bytes, header.paragraphs_count, ParagraphDataDisk.size);
    const list_bytes = read_section(&offset, bytes, header.lists_count, ListDataDisk.size);
    const list_item_bytes = read_section(&offset, bytes, header.list_items_count, ListItemDataDisk.size);
    const table_bytes = read_section(&offset, bytes, header.tables_count, TableDataDisk.size);
    const row_bytes = read_section(&offset, bytes, header.rows_count, TableRowDataDisk.size);
    const cell_bytes = read_section(&offset, bytes, header.cells_count, TableCellDataDisk.size);
    const block_bytes = read_section(&offset, bytes, header.blocks_count, BlockDataDisk.size);
    const text_bytes = read_section(&offset, bytes, header.texts_count, TextDataDisk.size);
    const link_bytes = read_section(&offset, bytes, header.links_count, LinkDataDisk.size);
    const ref_bytes = read_section(&offset, bytes, header.references_count, ReferenceDataDisk.size);
    const anchor_bytes = read_section(&offset, bytes, header.anchors_count, AnchorDataDisk.size);
    const emphasis_bytes = read_section(&offset, bytes, header.emphases_count, EmphasisDataDisk.size);
    const strong_bytes = read_section(&offset, bytes, header.strongs_count, StrongDataDisk.size);
    const diag_bytes = read_section(&offset, bytes, header.diagnostics_count, DiagnosticDisk.size);
    const roots_bytes = read_section(&offset, bytes, header.roots_count, 4);
    const string_refs_bytes = read_section(&offset, bytes, header.string_refs_count, StringRefDisk.size);
    const kv_pairs_bytes = read_section(&offset, bytes, header.kv_pairs_count, KVPairDisk.size);

    const bytes_arena = bytes[offset .. offset + @as(usize, @intCast(header.bytes_len))];
    // offset += bytes_arena.len; // not needed after this

    // build in-memory string refs
    var ref_table = try std.ArrayList(StringRefDisk).initCapacity(aa, header.string_refs_count);
    var sr_pos: usize = 0;
    for (0..header.string_refs_count) |_| {
        ref_table.appendAssumeCapacity(StringRefDisk.decode(string_refs_bytes[sr_pos..][0..StringRefDisk.size]));
        sr_pos += StringRefDisk.size;
    }

    // build kv pairs
    var kv_table = try std.ArrayList(KVPairDisk).initCapacity(aa, header.kv_pairs_count);
    var kv_pos: usize = 0;
    for (0..header.kv_pairs_count) |_| {
        kv_table.appendAssumeCapacity(KVPairDisk.decode(kv_pairs_bytes[kv_pos..][0..KVPairDisk.size]));
        kv_pos += KVPairDisk.size;
    }

    // ── allocate and decode typed arrays ──

    // nodes
    var nodes = try std.ArrayList(arena.NodeEntry).initCapacity(aa, header.node_entries_count);
    var pos: usize = 0;
    for (0..header.node_entries_count) |_| {
        const d = NodeEntryDisk.decode(node_bytes[pos..][0..NodeEntryDisk.size]);
        nodes.appendAssumeCapacity(.{ .tag = @enumFromInt(d.tag), .index = d.index });
        pos += NodeEntryDisk.size;
    }

    // inlines
    var inlines = try std.ArrayList(arena.InlineEntry).initCapacity(aa, header.inline_entries_count);
    var ipos: usize = 0;
    for (0..header.inline_entries_count) |_| {
        const d = InlineEntryDisk.decode(inline_bytes[ipos..][0..InlineEntryDisk.size]);
        inlines.appendAssumeCapacity(.{ .tag = @enumFromInt(d.tag), .index = d.index });
        ipos += InlineEntryDisk.size;
    }

    // sections
    var sections = try std.ArrayList(arena.SectionData).initCapacity(aa, header.sections_count);
    var spos: usize = 0;
    for (0..header.sections_count) |_| {
        const d = SectionDataDisk.decode(section_bytes[spos..][0..SectionDataDisk.size]);
        const meta = decodeMetadata(aa, d.meta, ref_table.items, bytes_arena, kv_table.items);
        const title: ?[]const u8 = if (d.title_ref != NULL_U32) resolveStr(ref_table.items, bytes_arena, d.title_ref) else null;
        sections.appendAssumeCapacity(.{
            .metadata = meta,
            .title = title,
            .first_child = p32(d.first_child),
            .child_count = d.child_count,
        });
        spos += SectionDataDisk.size;
    }

    // paragraphs
    var paragraphs = try std.ArrayList(arena.ParagraphData).initCapacity(aa, header.paragraphs_count);
    var ppos: usize = 0;
    for (0..header.paragraphs_count) |_| {
        const d = ParagraphDataDisk.decode(paragraph_bytes[ppos..][0..ParagraphDataDisk.size]);
        paragraphs.appendAssumeCapacity(.{ .first_inline = p32(d.first_inline), .inline_count = d.inline_count });
        ppos += ParagraphDataDisk.size;
    }

    // lists
    var lists = try std.ArrayList(arena.ListData).initCapacity(aa, header.lists_count);
    var lpos: usize = 0;
    for (0..header.lists_count) |_| {
        const d = ListDataDisk.decode(list_bytes[lpos..][0..ListDataDisk.size]);
        lists.appendAssumeCapacity(.{ .kind = @enumFromInt(d.kind), .first_item = p32(d.first_item), .item_count = d.item_count });
        lpos += ListDataDisk.size;
    }

    // list items
    var list_items = try std.ArrayList(arena.ListItemData).initCapacity(aa, header.list_items_count);
    var lipos: usize = 0;
    for (0..header.list_items_count) |_| {
        const d = ListItemDataDisk.decode(list_item_bytes[lipos..][0..ListItemDataDisk.size]);
        list_items.appendAssumeCapacity(.{ .first_child = p32(d.first_child), .child_count = d.child_count });
        lipos += ListItemDataDisk.size;
    }

    // tables
    var tables = try std.ArrayList(arena.TableData).initCapacity(aa, header.tables_count);
    var tpos: usize = 0;
    for (0..header.tables_count) |_| {
        const d = TableDataDisk.decode(table_bytes[tpos..][0..TableDataDisk.size]);
        tables.appendAssumeCapacity(.{ .first_row = p32(d.first_row), .row_count = d.row_count });
        tpos += TableDataDisk.size;
    }

    // rows
    var rows = try std.ArrayList(arena.TableRowData).initCapacity(aa, header.rows_count);
    var rpos: usize = 0;
    for (0..header.rows_count) |_| {
        const d = TableRowDataDisk.decode(row_bytes[rpos..][0..TableRowDataDisk.size]);
        rows.appendAssumeCapacity(.{ .first_cell = p32(d.first_cell), .cell_count = d.cell_count });
        rpos += TableRowDataDisk.size;
    }

    // cells
    var cells = try std.ArrayList(arena.TableCellData).initCapacity(aa, header.cells_count);
    var cpos: usize = 0;
    for (0..header.cells_count) |_| {
        const d = TableCellDataDisk.decode(cell_bytes[cpos..][0..TableCellDataDisk.size]);
        cells.appendAssumeCapacity(.{ .first_child = p32(d.first_child), .child_count = d.child_count });
        cpos += TableCellDataDisk.size;
    }

    // blocks
    var blocks = try std.ArrayList(arena.BlockData).initCapacity(aa, header.blocks_count);
    var bpos: usize = 0;
    for (0..header.blocks_count) |_| {
        const d = BlockDataDisk.decode(block_bytes[bpos..][0..BlockDataDisk.size]);
        const meta = decodeMetadata(aa, d.meta, ref_table.items, bytes_arena, kv_table.items);
        blocks.appendAssumeCapacity(.{
            .metadata = meta,
            .first_child = p32(d.first_child),
            .child_count = d.child_count,
        });
        bpos += BlockDataDisk.size;
    }

    // texts
    var texts = try std.ArrayList(arena.TextData).initCapacity(aa, header.texts_count);
    var txpos: usize = 0;
    for (0..header.texts_count) |_| {
        const d = TextDataDisk.decode(text_bytes[txpos..][0..TextDataDisk.size]);
        texts.appendAssumeCapacity(.{ .value = resolveStr(ref_table.items, bytes_arena, d.value_ref) });
        txpos += TextDataDisk.size;
    }

    // links
    var links = try std.ArrayList(arena.LinkData).initCapacity(aa, header.links_count);
    var lkpos: usize = 0;
    for (0..header.links_count) |_| {
        const d = LinkDataDisk.decode(link_bytes[lkpos..][0..LinkDataDisk.size]);
        links.appendAssumeCapacity(.{ .target = resolveStr(ref_table.items, bytes_arena, d.target_ref), .label = p32(d.label) });
        lkpos += LinkDataDisk.size;
    }

    // references
    var references = try std.ArrayList(arena.ReferenceData).initCapacity(aa, header.references_count);
    var rfpos: usize = 0;
    for (0..header.references_count) |_| {
        const d = ReferenceDataDisk.decode(ref_bytes[rfpos..][0..ReferenceDataDisk.size]);
        references.appendAssumeCapacity(.{ .target = resolveStr(ref_table.items, bytes_arena, d.target_ref), .label = p32(d.label) });
        rfpos += ReferenceDataDisk.size;
    }

    // anchors
    var anchors = try std.ArrayList(arena.AnchorData).initCapacity(aa, header.anchors_count);
    var apos: usize = 0;
    for (0..header.anchors_count) |_| {
        const d = AnchorDataDisk.decode(anchor_bytes[apos..][0..AnchorDataDisk.size]);
        anchors.appendAssumeCapacity(.{ .name = resolveStr(ref_table.items, bytes_arena, d.name_ref) });
        apos += AnchorDataDisk.size;
    }

    // emphases
    var emphases = try std.ArrayList(arena.EmphasisData).initCapacity(aa, header.emphases_count);
    var epos: usize = 0;
    for (0..header.emphases_count) |_| {
        const d = EmphasisDataDisk.decode(emphasis_bytes[epos..][0..EmphasisDataDisk.size]);
        emphases.appendAssumeCapacity(.{ .first_inline = p32(d.first_inline), .inline_count = d.inline_count });
        epos += EmphasisDataDisk.size;
    }

    // strongs
    var strongs = try std.ArrayList(arena.StrongData).initCapacity(aa, header.strongs_count);
    var stpos: usize = 0;
    for (0..header.strongs_count) |_| {
        const d = StrongDataDisk.decode(strong_bytes[stpos..][0..StrongDataDisk.size]);
        strongs.appendAssumeCapacity(.{ .first_inline = p32(d.first_inline), .inline_count = d.inline_count });
        stpos += StrongDataDisk.size;
    }

    // diagnostics
    var diagnostics = try std.ArrayList(arena.Diagnostic).initCapacity(aa, header.diagnostics_count);
    var dpos: usize = 0;
    for (0..header.diagnostics_count) |_| {
        const d = DiagnosticDisk.decode(diag_bytes[dpos..][0..DiagnosticDisk.size]);
        diagnostics.appendAssumeCapacity(.{ .message = resolveStr(ref_table.items, bytes_arena, d.message_ref) });
        dpos += DiagnosticDisk.size;
    }

    // roots
    var roots = try std.ArrayList(u32).initCapacity(aa, header.roots_count);
    var rtpos: usize = 0;
    for (0..header.roots_count) |_| {
        roots.appendAssumeCapacity(std.mem.readInt(u32, roots_bytes[rtpos..][0..4], .little));
        rtpos += 4;
    }

    const doc_meta = decodeMetadata(aa, header.doc_meta, ref_table.items, bytes_arena, kv_table.items);

    return arena.DocumentArena{
        .arena = arena_state,
        .metadata = doc_meta,
        .nodes = nodes.items,
        .inlines = inlines.items,
        .sections = sections.items,
        .paragraphs = paragraphs.items,
        .lists = lists.items,
        .list_items = list_items.items,
        .tables = tables.items,
        .rows = rows.items,
        .cells = cells.items,
        .blocks = blocks.items,
        .texts = texts.items,
        .links = links.items,
        .references = references.items,
        .anchors = anchors.items,
        .emphases = emphases.items,
        .strongs = strongs.items,
        .diagnostics = diagnostics.items,
        .roots = roots.items,
    };
}

fn decodeMetadata(
    aa: std.mem.Allocator,
    disk: MetadataDisk,
    string_refs: []const StringRefDisk,
    bytes_arena: []const u8,
    kv_pairs: []const KVPairDisk,
) arena.Metadata {
    const id: ?[]const u8 = if (disk.id_ref != NULL_U32) resolveStr(string_refs, bytes_arena, disk.id_ref) else null;
    const title: ?[]const u8 = if (disk.title_ref != NULL_U32) resolveStr(string_refs, bytes_arena, disk.title_ref) else null;

    var roles = std.ArrayList([]const u8).empty;
    if (disk.roles_count > 0) {
        const rstart: u32 = disk.roles_first;
        for (0..disk.roles_count) |ri| {
            const sr = string_refs[rstart + @as(u32, @intCast(ri))];
            const role = bytes_arena[sr.start .. sr.start + sr.len];
            roles.append(aa, role) catch {};
        }
    }

    var attrs = std.ArrayList(arena.KVPair).empty;
    if (disk.attrs_count > 0) {
        const astart: u32 = disk.attrs_first;
        for (0..disk.attrs_count) |ai| {
            const kv = kv_pairs[astart + @as(u32, @intCast(ai))];
            const key = resolveStr(string_refs, bytes_arena, kv.key_ref);
            const val = resolveStr(string_refs, bytes_arena, kv.value_ref);
            attrs.append(aa, .{ .key = key, .value = val }) catch {};
        }
    }

    return .{ .id = id, .title = title, .roles = roles.items, .attrs = attrs.items };
}

// ── zero-copy borrowed view ──

pub const BorrowedArenaView = struct {
    raw: []const u8,
    header: HeaderDisk,

    node_bytes: []const u8,
    inline_bytes: []const u8,
    section_bytes: []const u8,
    paragraph_bytes: []const u8,
    list_bytes: []const u8,
    list_item_bytes: []const u8,
    table_bytes: []const u8,
    row_bytes: []const u8,
    cell_bytes: []const u8,
    block_bytes: []const u8,
    text_bytes: []const u8,
    link_bytes: []const u8,
    ref_bytes: []const u8,
    anchor_bytes: []const u8,
    emphasis_bytes: []const u8,
    strong_bytes: []const u8,
    diag_bytes: []const u8,
    roots_slice: []const u8,

    string_refs: []const u8,
    kv_pairs: []const u8,
    bytes_arena: []const u8,

    _ref_table: []StringRefDisk,
    _kv_table: []KVPairDisk,

    pub fn deinit(self: *BorrowedArenaView, allocator: std.mem.Allocator) void {
        allocator.free(self._ref_table);
        allocator.free(self._kv_table);
        self.* = undefined;
    }

    pub fn getText(self: *const BorrowedArenaView, idx: u32) []const u8 {
        const d = TextDataDisk.decode(self.text_bytes[@as(usize, @intCast(idx)) * TextDataDisk.size ..][0..TextDataDisk.size]);
        return resolveStr(self._ref_table, self.bytes_arena, d.value_ref);
    }

    pub fn nodeCount(self: *const BorrowedArenaView) u32 {
        return self.header.node_entries_count;
    }

    pub fn inlineCount(self: *const BorrowedArenaView) u32 {
        return self.header.inline_entries_count;
    }
};

pub fn view(allocator: std.mem.Allocator, bytes: []const u8) !BorrowedArenaView {
    _ = try validate(bytes);
    const header = HeaderDisk.decode(bytes[0..HeaderDisk.byte_size]);

    var offset: usize = HeaderDisk.byte_size;

    const read_section = struct {
        fn read(offset_ptr: *usize, count: u32, rec_size: usize) u32 {
            const start: u32 = @as(u32, @intCast(offset_ptr.*));
            offset_ptr.* += count * rec_size;
            return start;
        }
    }.read;

    const node_s = read_section(&offset, header.node_entries_count, NodeEntryDisk.size);
    const inline_s = read_section(&offset, header.inline_entries_count, InlineEntryDisk.size);
    const section_s = read_section(&offset, header.sections_count, SectionDataDisk.size);
    const paragraph_s = read_section(&offset, header.paragraphs_count, ParagraphDataDisk.size);
    const list_s = read_section(&offset, header.lists_count, ListDataDisk.size);
    const list_item_s = read_section(&offset, header.list_items_count, ListItemDataDisk.size);
    const table_s = read_section(&offset, header.tables_count, TableDataDisk.size);
    const row_s = read_section(&offset, header.rows_count, TableRowDataDisk.size);
    const cell_s = read_section(&offset, header.cells_count, TableCellDataDisk.size);
    const block_s = read_section(&offset, header.blocks_count, BlockDataDisk.size);
    const text_s = read_section(&offset, header.texts_count, TextDataDisk.size);
    const link_s = read_section(&offset, header.links_count, LinkDataDisk.size);
    const ref_s = read_section(&offset, header.references_count, ReferenceDataDisk.size);
    const anchor_s = read_section(&offset, header.anchors_count, AnchorDataDisk.size);
    const emphasis_s = read_section(&offset, header.emphases_count, EmphasisDataDisk.size);
    const strong_s = read_section(&offset, header.strongs_count, StrongDataDisk.size);
    const diag_s = read_section(&offset, header.diagnostics_count, DiagnosticDisk.size);
    const roots_s = read_section(&offset, header.roots_count, 4);
    const string_refs_s = read_section(&offset, header.string_refs_count, StringRefDisk.size);
    const kv_pairs_s = read_section(&offset, header.kv_pairs_count, KVPairDisk.size);

    const bytes_start = offset;
    _ = bytes_start;

    var ref_table = try allocator.alloc(StringRefDisk, header.string_refs_count);
    errdefer allocator.free(ref_table);
    var sr_pos: usize = 0;
    for (0..header.string_refs_count) |i| {
        ref_table[i] = StringRefDisk.decode(bytes[string_refs_s + @as(usize, @intCast(sr_pos)) ..][0..StringRefDisk.size]);
        sr_pos += StringRefDisk.size;
    }

    var kv_table = try allocator.alloc(KVPairDisk, header.kv_pairs_count);
    errdefer allocator.free(kv_table);
    var kv_p: usize = 0;
    for (0..header.kv_pairs_count) |i| {
        kv_table[i] = KVPairDisk.decode(bytes[kv_pairs_s + @as(usize, @intCast(kv_p)) ..][0..KVPairDisk.size]);
        kv_p += KVPairDisk.size;
    }

    return BorrowedArenaView{
        .raw = bytes,
        .header = header,
        .node_bytes = bytes[node_s..],
        .inline_bytes = bytes[inline_s..],
        .section_bytes = bytes[section_s..],
        .paragraph_bytes = bytes[paragraph_s..],
        .list_bytes = bytes[list_s..],
        .list_item_bytes = bytes[list_item_s..],
        .table_bytes = bytes[table_s..],
        .row_bytes = bytes[row_s..],
        .cell_bytes = bytes[cell_s..],
        .block_bytes = bytes[block_s..],
        .text_bytes = bytes[text_s..],
        .link_bytes = bytes[link_s..],
        .ref_bytes = bytes[ref_s..],
        .anchor_bytes = bytes[anchor_s..],
        .emphasis_bytes = bytes[emphasis_s..],
        .strong_bytes = bytes[strong_s..],
        .diag_bytes = bytes[diag_s..],
        .roots_slice = bytes[roots_s..],
        .string_refs = bytes[string_refs_s..],
        .kv_pairs = bytes[kv_pairs_s..],
        .bytes_arena = bytes[offset .. offset + @as(usize, @intCast(header.bytes_len))],
        ._ref_table = ref_table,
        ._kv_table = kv_table,
    };
}

// ── author IR load ──

pub fn deserializeToAuthorIr(allocator: std.mem.Allocator, bytes: []const u8) !author.Document {
    const doc_arena = try deserialize(allocator, bytes);
    defer doc_arena.deinit();

    _ = try lower.lowerDocument(allocator, doc_arena);
    return undefined;
}

// ── tests ──

const test_allocator = std.testing.allocator;

test "validate rejects bad magic" {
    var buf: [HeaderDisk.byte_size]u8 = undefined;
    @memset(&buf, 0);
    buf[0] = 'B';
    buf[1] = 'A';
    buf[2] = 'D';
    buf[3] = '!';
    buf[4] = '!';
    buf[5] = '!';
    try std.testing.expectError(error.InvalidMagic, validate(&buf));
}

test "validate rejects bad version" {
    var buf: [HeaderDisk.byte_size]u8 = undefined;
    @memset(&buf, 0);
    @memcpy(buf[0..6], MAGIC);
    std.mem.writeInt(u16, buf[6..8], 999, .little);
    try std.testing.expectError(error.UnsupportedVersion, validate(&buf));
}

test "validate rejects truncated data" {
    var buf: [HeaderDisk.byte_size]u8 = undefined;
    @memset(&buf, 0);
    @memcpy(buf[0..6], MAGIC);
    std.mem.writeInt(u16, buf[6..8], FORMAT_VERSION, .little);
    std.mem.writeInt(u16, buf[8..10], IR_VERSION, .little);
    std.mem.writeInt(u32, buf[14..18], 1, .little); // node_entries_count = 1
    try std.testing.expectError(error.TruncatedSection, validate(&buf));
}

test "header encode/decode round-trip" {
    // defined inline above already tested
}

test "serialize deserialize round-trip" {
    const build = @import("build_ir.zig");
    const lower_mod = @import("lower.zig");

    var b = build.Builder.init(test_allocator);

    const meta = try b.metadata(.{ .id = "test-doc" });
    const intro_text = try b.inlineText("Hello, world!");
    const intro_emph = try b.inlineEmphasis(&.{try b.inlineText("emphasized")});
    const intro_para = try b.paragraph(&.{ intro_text, intro_emph });

    const sec_meta = try b.metadata(.{ .id = "intro" });
    const sec = try b.section(sec_meta, "Introduction", &.{intro_para});

    const details_meta = try b.metadata(.{ .id = "details" });
    const first_text = try b.inlineText("First item");
    const first_para = try b.paragraph(&.{first_text});
    const li1 = try b.listItem(&.{first_para});
    const second_text = try b.inlineText("Second item");
    const second_para = try b.paragraph(&.{second_text});
    const li2 = try b.listItem(&.{second_para});
    const list_node = try b.list(.ordered, &.{ li1, li2 });
    const details_sec = try b.section(details_meta, "Details", &.{list_node});

    var doc = try b.document(meta, &.{ sec, details_sec });
    defer doc.deinit(test_allocator);

    var doc_arena = try lower_mod.lower(test_allocator, &doc);
    defer doc_arena.deinit();

    const serialized = try serialize(test_allocator, doc_arena);
    defer test_allocator.free(serialized);

    var deserialized = try deserialize(test_allocator, serialized);
    defer deserialized.deinit();

    try std.testing.expectEqual(doc_arena.nodes.len, deserialized.nodes.len);
    try std.testing.expectEqual(doc_arena.inlines.len, deserialized.inlines.len);
    try std.testing.expectEqual(doc_arena.roots.len, deserialized.roots.len);
    try std.testing.expectEqual(doc_arena.sections.len, deserialized.sections.len);

    const v = try validate(serialized);
    try std.testing.expect(v.total_bytes > HeaderDisk.byte_size);
    try std.testing.expect(v.node_count > 0);
    try std.testing.expect(v.inline_count > 0);
}

test "serialize borrowed view round-trip" {
    const build = @import("build_ir.zig");
    const lower_mod = @import("lower.zig");

    var b = build.Builder.init(test_allocator);
    const meta = try b.metadata(.{});
    const text = try b.inlineText("Some text here");
    const para = try b.paragraph(&.{text});
    const sec = try b.section(meta, "Hello", &.{para});
    var doc = try b.document(meta, &.{sec});
    defer doc.deinit(test_allocator);

    var doc_arena = try lower_mod.lower(test_allocator, &doc);
    defer doc_arena.deinit();

    const serialized = try serialize(test_allocator, doc_arena);
    defer test_allocator.free(serialized);

    var bv = try view(test_allocator, serialized);
    defer bv.deinit(test_allocator);

    try std.testing.expectEqual(doc_arena.inlines.len, bv.inlineCount());
    try std.testing.expect(bv.getText(0).len > 0);
}

test "serialize determinism" {
    const build = @import("build_ir.zig");
    const lower_mod = @import("lower.zig");

    var b1 = build.Builder.init(test_allocator);
    const meta1 = try b1.metadata(.{ .id = "dt" });
    const text1 = try b1.inlineText("hello");
    const para1 = try b1.paragraph(&.{text1});
    var doc1 = try b1.document(meta1, &.{para1});
    defer doc1.deinit(test_allocator);
    var arena1 = try lower_mod.lower(test_allocator, &doc1);
    defer arena1.deinit();

    var b2 = build.Builder.init(test_allocator);
    const meta2 = try b2.metadata(.{ .id = "dt" });
    const text2 = try b2.inlineText("hello");
    const para2 = try b2.paragraph(&.{text2});
    var doc2 = try b2.document(meta2, &.{para2});
    defer doc2.deinit(test_allocator);
    var arena2 = try lower_mod.lower(test_allocator, &doc2);
    defer arena2.deinit();

    const s1 = try serialize(test_allocator, arena1);
    defer test_allocator.free(s1);
    const s2 = try serialize(test_allocator, arena2);
    defer test_allocator.free(s2);

    try std.testing.expectEqual(s1.len, s2.len);
    try std.testing.expect(std.mem.eql(u8, s1, s2));
}
