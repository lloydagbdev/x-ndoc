const std = @import("std");
const core = @import("core_ir.zig");
const validate_core = @import("validate.zig");

pub const MAGIC = "XNDC4\x00";
pub const FORMAT_VERSION: u16 = 1;
pub const NULL_U32: u32 = 0xFFFFFFFF;

pub const ValidationReport = struct {
    total_bytes: usize,
    node_count: usize,
    inline_count: usize,
    string_count: usize,
};

pub const ValidationError = error{
    OutOfMemory,
    TruncatedHeader,
    InvalidMagic,
    UnsupportedVersion,
    TruncatedSection,
    InvalidNodeIndex,
    InvalidInlineIndex,
    InvalidStringRef,
    InvalidPayloadIndex,
    InvalidRoot,
    SemanticInvalid,
};

const StringRefDisk = struct {
    start: u32,
    len: u32,

    const size = 8;

    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.start, .little);
        std.mem.writeInt(u32, buf[4..8], self.len, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{
            .start = std.mem.readInt(u32, buf[0..4], .little),
            .len = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

const KVPairDisk = struct {
    key_ref: u32,
    value_ref: u32,

    const size = 8;

    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.key_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.value_ref, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{
            .key_ref = std.mem.readInt(u32, buf[0..4], .little),
            .value_ref = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

const MetadataDisk = struct {
    id_ref: u32,
    title_ref: u32,
    roles_first: u32,
    roles_count: u32,
    attrs_first: u32,
    attrs_count: u32,

    const size = 24;

    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.id_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.title_ref, .little);
        std.mem.writeInt(u32, buf[8..12], self.roles_first, .little);
        std.mem.writeInt(u32, buf[12..16], self.roles_count, .little);
        std.mem.writeInt(u32, buf[16..20], self.attrs_first, .little);
        std.mem.writeInt(u32, buf[20..24], self.attrs_count, .little);
    }

    fn decode(buf: []const u8) @This() {
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

const NodeRefDisk = struct {
    tag: u8,
    index: u32,

    const size = 5;

    fn encode(buf: []u8, self: @This()) void {
        buf[0] = self.tag;
        std.mem.writeInt(u32, buf[1..5], self.index, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{ .tag = buf[0], .index = std.mem.readInt(u32, buf[1..5], .little) };
    }
};

const InlineRefDisk = struct {
    tag: u8,
    index: u32,

    const size = 5;

    fn encode(buf: []u8, self: @This()) void {
        buf[0] = self.tag;
        std.mem.writeInt(u32, buf[1..5], self.index, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{ .tag = buf[0], .index = std.mem.readInt(u32, buf[1..5], .little) };
    }
};

const ChildSpanDisk = struct {
    first_child_ref: u32,
    child_count: u32,

    const size = 8;

    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.first_child_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.child_count, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{
            .first_child_ref = std.mem.readInt(u32, buf[0..4], .little),
            .child_count = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

const SectionDisk = struct {
    meta: MetadataDisk,
    title_ref: u32,
    first_child_ref: u32,
    child_count: u32,

    const size = 36;

    fn encode(buf: []u8, self: @This()) void {
        MetadataDisk.encode(buf[0..24], self.meta);
        std.mem.writeInt(u32, buf[24..28], self.title_ref, .little);
        std.mem.writeInt(u32, buf[28..32], self.first_child_ref, .little);
        std.mem.writeInt(u32, buf[32..36], self.child_count, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{
            .meta = MetadataDisk.decode(buf[0..24]),
            .title_ref = std.mem.readInt(u32, buf[24..28], .little),
            .first_child_ref = std.mem.readInt(u32, buf[28..32], .little),
            .child_count = std.mem.readInt(u32, buf[32..36], .little),
        };
    }
};

const ListDisk = struct {
    kind: u8,
    first_child_ref: u32,
    child_count: u32,

    const size = 9;

    fn encode(buf: []u8, self: @This()) void {
        buf[0] = self.kind;
        std.mem.writeInt(u32, buf[1..5], self.first_child_ref, .little);
        std.mem.writeInt(u32, buf[5..9], self.child_count, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{
            .kind = buf[0],
            .first_child_ref = std.mem.readInt(u32, buf[1..5], .little),
            .child_count = std.mem.readInt(u32, buf[5..9], .little),
        };
    }
};

const BlockDisk = struct {
    meta: MetadataDisk,
    first_child_ref: u32,
    child_count: u32,

    const size = 32;

    fn encode(buf: []u8, self: @This()) void {
        MetadataDisk.encode(buf[0..24], self.meta);
        std.mem.writeInt(u32, buf[24..28], self.first_child_ref, .little);
        std.mem.writeInt(u32, buf[28..32], self.child_count, .little);
    }

    fn decode(buf: []const u8) @This() {
        return .{
            .meta = MetadataDisk.decode(buf[0..24]),
            .first_child_ref = std.mem.readInt(u32, buf[24..28], .little),
            .child_count = std.mem.readInt(u32, buf[28..32], .little),
        };
    }
};

const TextDisk = struct {
    value_ref: u32,
    const size = 4;
    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.value_ref, .little);
    }
    fn decode(buf: []const u8) @This() {
        return .{ .value_ref = std.mem.readInt(u32, buf[0..4], .little) };
    }
};

const LinkDisk = struct {
    target_ref: u32,
    label: u32,
    const size = 8;
    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.target_ref, .little);
        std.mem.writeInt(u32, buf[4..8], self.label, .little);
    }
    fn decode(buf: []const u8) @This() {
        return .{
            .target_ref = std.mem.readInt(u32, buf[0..4], .little),
            .label = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

const AnchorDisk = struct {
    name_ref: u32,
    const size = 4;
    fn encode(buf: []u8, self: @This()) void {
        std.mem.writeInt(u32, buf[0..4], self.name_ref, .little);
    }
    fn decode(buf: []const u8) @This() {
        return .{ .name_ref = std.mem.readInt(u32, buf[0..4], .little) };
    }
};

const HeaderDisk = struct {
    magic: [6]u8,
    format_version: u16,
    doc_meta: MetadataDisk,
    roots_count: u32,
    node_child_refs_count: u32,
    inline_child_refs_count: u32,
    node_refs_count: u32,
    inline_refs_count: u32,
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
    string_refs_count: u32,
    kv_pairs_count: u32,
    bytes_len: u32,

    const byte_size = 6 + 2 + 24 + (22 * 4);

    fn encode(buf: []u8, self: @This()) void {
        @memcpy(buf[0..6], &self.magic);
        std.mem.writeInt(u16, buf[6..8], self.format_version, .little);
        MetadataDisk.encode(buf[8..32], self.doc_meta);
        var off: usize = 32;
        inline for (.{ self.roots_count, self.node_child_refs_count, self.inline_child_refs_count, self.node_refs_count, self.inline_refs_count, self.sections_count, self.paragraphs_count, self.lists_count, self.list_items_count, self.tables_count, self.rows_count, self.cells_count, self.blocks_count, self.texts_count, self.links_count, self.references_count, self.anchors_count, self.emphases_count, self.strongs_count, self.string_refs_count, self.kv_pairs_count, self.bytes_len }) |value| {
            std.mem.writeInt(u32, buf[off..][0..4], value, .little);
            off += 4;
        }
    }

    fn decode(buf: []const u8) @This() {
        var magic: [6]u8 = undefined;
        @memcpy(&magic, buf[0..6]);
        return .{
            .magic = magic,
            .format_version = std.mem.readInt(u16, buf[6..8], .little),
            .doc_meta = MetadataDisk.decode(buf[8..32]),
            .roots_count = std.mem.readInt(u32, buf[32..36], .little),
            .node_child_refs_count = std.mem.readInt(u32, buf[36..40], .little),
            .inline_child_refs_count = std.mem.readInt(u32, buf[40..44], .little),
            .node_refs_count = std.mem.readInt(u32, buf[44..48], .little),
            .inline_refs_count = std.mem.readInt(u32, buf[48..52], .little),
            .sections_count = std.mem.readInt(u32, buf[52..56], .little),
            .paragraphs_count = std.mem.readInt(u32, buf[56..60], .little),
            .lists_count = std.mem.readInt(u32, buf[60..64], .little),
            .list_items_count = std.mem.readInt(u32, buf[64..68], .little),
            .tables_count = std.mem.readInt(u32, buf[68..72], .little),
            .rows_count = std.mem.readInt(u32, buf[72..76], .little),
            .cells_count = std.mem.readInt(u32, buf[76..80], .little),
            .blocks_count = std.mem.readInt(u32, buf[80..84], .little),
            .texts_count = std.mem.readInt(u32, buf[84..88], .little),
            .links_count = std.mem.readInt(u32, buf[88..92], .little),
            .references_count = std.mem.readInt(u32, buf[92..96], .little),
            .anchors_count = std.mem.readInt(u32, buf[96..100], .little),
            .emphases_count = std.mem.readInt(u32, buf[100..104], .little),
            .strongs_count = std.mem.readInt(u32, buf[104..108], .little),
            .string_refs_count = std.mem.readInt(u32, buf[108..112], .little),
            .kv_pairs_count = std.mem.readInt(u32, buf[112..116], .little),
            .bytes_len = std.mem.readInt(u32, buf[116..120], .little),
        };
    }
};

const StringCtx = struct {
    bytes: std.ArrayList(u8),
    refs: std.ArrayList(StringRefDisk),

    fn init() @This() {
        return .{ .bytes = .empty, .refs = .empty };
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
        self.refs.deinit(allocator);
    }

    fn emit(self: *@This(), value: []const u8, allocator: std.mem.Allocator) !u32 {
        const start: u32 = @intCast(self.bytes.items.len);
        try self.bytes.appendSlice(allocator, value);
        try self.refs.append(allocator, .{ .start = start, .len = @intCast(value.len) });
        return @intCast(self.refs.items.len - 1);
    }

    fn emitOpt(self: *@This(), value: ?[]const u8, allocator: std.mem.Allocator) !u32 {
        if (value) |v| return try self.emit(v, allocator);
        return NULL_U32;
    }
};

pub fn validate(bytes: []const u8) ValidationError!ValidationReport {
    const header = try validateStructural(bytes);
    try validateSemanticDocument(bytes, header);

    return .{
        .total_bytes = bytes.len,
        .node_count = header.node_refs_count,
        .inline_count = header.inline_refs_count,
        .string_count = header.string_refs_count,
    };
}

fn validateStructural(bytes: []const u8) ValidationError!HeaderDisk {
    if (bytes.len < HeaderDisk.byte_size) return error.TruncatedHeader;
    const header = HeaderDisk.decode(bytes[0..HeaderDisk.byte_size]);
    if (!std.mem.eql(u8, &header.magic, MAGIC)) return error.InvalidMagic;
    if (header.format_version != FORMAT_VERSION) return error.UnsupportedVersion;

    var offset: usize = HeaderDisk.byte_size;
    inline for (.{
        header.roots_count * 4,
        header.node_child_refs_count * 4,
        header.inline_child_refs_count * 4,
        header.node_refs_count * NodeRefDisk.size,
        header.inline_refs_count * InlineRefDisk.size,
        header.sections_count * SectionDisk.size,
        header.paragraphs_count * ChildSpanDisk.size,
        header.lists_count * ListDisk.size,
        header.list_items_count * ChildSpanDisk.size,
        header.tables_count * ChildSpanDisk.size,
        header.rows_count * ChildSpanDisk.size,
        header.cells_count * ChildSpanDisk.size,
        header.blocks_count * BlockDisk.size,
        header.texts_count * TextDisk.size,
        header.links_count * LinkDisk.size,
        header.references_count * LinkDisk.size,
        header.anchors_count * AnchorDisk.size,
        header.emphases_count * ChildSpanDisk.size,
        header.strongs_count * ChildSpanDisk.size,
        header.string_refs_count * StringRefDisk.size,
        header.kv_pairs_count * KVPairDisk.size,
    }) |sec_size| {
        if (offset + sec_size > bytes.len) return error.TruncatedSection;
        offset += sec_size;
    }
    if (offset + header.bytes_len != bytes.len) return error.TruncatedSection;

    try validateSemantic(bytes, header);
    return header;
}

fn validateSemanticDocument(bytes: []const u8, header: HeaderDisk) ValidationError!void {
    _ = header;
    var doc = try deserializeUnvalidated(std.heap.page_allocator, bytes);
    defer doc.deinit();

    const diags = try validate_core.validate(std.heap.page_allocator, doc);
    defer {
        for (diags) |d| std.heap.page_allocator.free(d.message);
        std.heap.page_allocator.free(diags);
    }
    if (diags.len > 0) return error.SemanticInvalid;
}

fn validateSemantic(bytes: []const u8, header: HeaderDisk) ValidationError!void {
    var offset: usize = HeaderDisk.byte_size;
    const roots = readSection(&offset, bytes, header.roots_count, 4);
    const node_child_refs = readSection(&offset, bytes, header.node_child_refs_count, 4);
    const inline_child_refs = readSection(&offset, bytes, header.inline_child_refs_count, 4);
    const node_refs = readSection(&offset, bytes, header.node_refs_count, NodeRefDisk.size);
    const inline_refs = readSection(&offset, bytes, header.inline_refs_count, InlineRefDisk.size);
    const sections = readSection(&offset, bytes, header.sections_count, SectionDisk.size);
    const paragraphs = readSection(&offset, bytes, header.paragraphs_count, ChildSpanDisk.size);
    const lists = readSection(&offset, bytes, header.lists_count, ListDisk.size);
    const list_items = readSection(&offset, bytes, header.list_items_count, ChildSpanDisk.size);
    const tables = readSection(&offset, bytes, header.tables_count, ChildSpanDisk.size);
    const rows = readSection(&offset, bytes, header.rows_count, ChildSpanDisk.size);
    const cells = readSection(&offset, bytes, header.cells_count, ChildSpanDisk.size);
    const blocks = readSection(&offset, bytes, header.blocks_count, BlockDisk.size);
    const texts = readSection(&offset, bytes, header.texts_count, TextDisk.size);
    const links = readSection(&offset, bytes, header.links_count, LinkDisk.size);
    const references = readSection(&offset, bytes, header.references_count, LinkDisk.size);
    const anchors = readSection(&offset, bytes, header.anchors_count, AnchorDisk.size);
    const emphases = readSection(&offset, bytes, header.emphases_count, ChildSpanDisk.size);
    const strongs = readSection(&offset, bytes, header.strongs_count, ChildSpanDisk.size);
    const string_refs = readSection(&offset, bytes, header.string_refs_count, StringRefDisk.size);
    const kv_pairs = readSection(&offset, bytes, header.kv_pairs_count, KVPairDisk.size);
    const bytes_arena = bytes[offset .. offset + header.bytes_len];

    _ = kv_pairs;

    var i: usize = 0;
    while (i < roots.len) : (i += 4) {
        if (std.mem.readInt(u32, roots[i..][0..4], .little) >= header.node_refs_count) return error.InvalidRoot;
    }
    i = 0;
    while (i < node_child_refs.len) : (i += 4) {
        if (std.mem.readInt(u32, node_child_refs[i..][0..4], .little) >= header.node_refs_count) return error.InvalidNodeIndex;
    }
    i = 0;
    while (i < inline_child_refs.len) : (i += 4) {
        if (std.mem.readInt(u32, inline_child_refs[i..][0..4], .little) >= header.inline_refs_count) return error.InvalidInlineIndex;
    }

    i = 0;
    while (i < node_refs.len) : (i += NodeRefDisk.size) {
        const entry = NodeRefDisk.decode(node_refs[i..][0..NodeRefDisk.size]);
        switch (entry.tag) {
            0 => if (entry.index >= header.sections_count) return error.InvalidPayloadIndex,
            1 => if (entry.index >= header.paragraphs_count) return error.InvalidPayloadIndex,
            2 => if (entry.index >= header.lists_count) return error.InvalidPayloadIndex,
            3 => if (entry.index >= header.list_items_count) return error.InvalidPayloadIndex,
            4 => if (entry.index >= header.tables_count) return error.InvalidPayloadIndex,
            5 => if (entry.index >= header.rows_count) return error.InvalidPayloadIndex,
            6 => if (entry.index >= header.cells_count) return error.InvalidPayloadIndex,
            7 => if (entry.index >= header.blocks_count) return error.InvalidPayloadIndex,
            else => return error.InvalidPayloadIndex,
        }
    }

    i = 0;
    while (i < inline_refs.len) : (i += InlineRefDisk.size) {
        const entry = InlineRefDisk.decode(inline_refs[i..][0..InlineRefDisk.size]);
        switch (entry.tag) {
            0 => if (entry.index >= header.texts_count) return error.InvalidPayloadIndex,
            1 => if (entry.index >= header.links_count) return error.InvalidPayloadIndex,
            2 => if (entry.index >= header.references_count) return error.InvalidPayloadIndex,
            3 => if (entry.index >= header.anchors_count) return error.InvalidPayloadIndex,
            4 => if (entry.index >= header.emphases_count) return error.InvalidPayloadIndex,
            5 => if (entry.index >= header.strongs_count) return error.InvalidPayloadIndex,
            else => return error.InvalidPayloadIndex,
        }
    }

    i = 0;
    while (i < string_refs.len) : (i += StringRefDisk.size) {
        const sr = StringRefDisk.decode(string_refs[i..][0..StringRefDisk.size]);
        if (sr.start + sr.len > bytes_arena.len) return error.InvalidStringRef;
    }

    try validateMetadata(header.doc_meta, header.string_refs_count, header.kv_pairs_count);
    try validateSectionSpans(sections, header.node_child_refs_count, header.string_refs_count, header.kv_pairs_count);
    try validateChildSpans(paragraphs, header.inline_child_refs_count);
    try validateListSpans(lists, header.node_child_refs_count);
    try validateChildSpans(list_items, header.node_child_refs_count);
    try validateChildSpans(tables, header.node_child_refs_count);
    try validateChildSpans(rows, header.node_child_refs_count);
    try validateChildSpans(cells, header.node_child_refs_count);
    try validateBlockSpans(blocks, header.node_child_refs_count, header.string_refs_count, header.kv_pairs_count);
    try validateTextRefs(texts, header.string_refs_count);
    try validateLinkRefs(links, header.string_refs_count, header.inline_refs_count);
    try validateLinkRefs(references, header.string_refs_count, header.inline_refs_count);
    try validateAnchorRefs(anchors, header.string_refs_count);
    try validateChildSpans(emphases, header.inline_child_refs_count);
    try validateChildSpans(strongs, header.inline_child_refs_count);
}

fn validateMetadata(meta: MetadataDisk, string_ref_count: u32, kv_count: u32) ValidationError!void {
    if (meta.id_ref != NULL_U32 and meta.id_ref >= string_ref_count) return error.InvalidStringRef;
    if (meta.title_ref != NULL_U32 and meta.title_ref >= string_ref_count) return error.InvalidStringRef;
    if (meta.roles_count > 0 and meta.roles_first + meta.roles_count > string_ref_count) return error.InvalidStringRef;
    if (meta.attrs_count > 0 and meta.attrs_first + meta.attrs_count > kv_count) return error.InvalidPayloadIndex;
}

fn validateSectionSpans(bytes: []const u8, child_ref_count: u32, string_ref_count: u32, kv_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += SectionDisk.size) {
        const d = SectionDisk.decode(bytes[i..][0..SectionDisk.size]);
        try validateMetadata(d.meta, string_ref_count, kv_count);
        if (d.title_ref != NULL_U32 and d.title_ref >= string_ref_count) return error.InvalidStringRef;
        try validateSpanRaw(d.first_child_ref, d.child_count, child_ref_count);
    }
}

fn validateListSpans(bytes: []const u8, child_ref_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += ListDisk.size) {
        const d = ListDisk.decode(bytes[i..][0..ListDisk.size]);
        if (d.kind > 3) return error.InvalidPayloadIndex;
        try validateSpanRaw(d.first_child_ref, d.child_count, child_ref_count);
    }
}

fn validateBlockSpans(bytes: []const u8, child_ref_count: u32, string_ref_count: u32, kv_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += BlockDisk.size) {
        const d = BlockDisk.decode(bytes[i..][0..BlockDisk.size]);
        try validateMetadata(d.meta, string_ref_count, kv_count);
        try validateSpanRaw(d.first_child_ref, d.child_count, child_ref_count);
    }
}

fn validateChildSpans(bytes: []const u8, child_ref_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += ChildSpanDisk.size) {
        const d = ChildSpanDisk.decode(bytes[i..][0..ChildSpanDisk.size]);
        try validateSpanRaw(d.first_child_ref, d.child_count, child_ref_count);
    }
}

fn validateTextRefs(bytes: []const u8, string_ref_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += TextDisk.size) {
        const d = TextDisk.decode(bytes[i..][0..TextDisk.size]);
        if (d.value_ref >= string_ref_count) return error.InvalidStringRef;
    }
}

fn validateLinkRefs(bytes: []const u8, string_ref_count: u32, inline_ref_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += LinkDisk.size) {
        const d = LinkDisk.decode(bytes[i..][0..LinkDisk.size]);
        if (d.target_ref >= string_ref_count) return error.InvalidStringRef;
        if (d.label != NULL_U32 and d.label >= inline_ref_count) return error.InvalidInlineIndex;
    }
}

fn validateAnchorRefs(bytes: []const u8, string_ref_count: u32) ValidationError!void {
    var i: usize = 0;
    while (i < bytes.len) : (i += AnchorDisk.size) {
        const d = AnchorDisk.decode(bytes[i..][0..AnchorDisk.size]);
        if (d.name_ref >= string_ref_count) return error.InvalidStringRef;
    }
}

fn validateSpanRaw(first: u32, count: u32, child_ref_count: u32) ValidationError!void {
    if (count == 0) {
        if (first != NULL_U32) return error.InvalidPayloadIndex;
        return;
    }
    if (first == NULL_U32 or first + count > child_ref_count) return error.InvalidPayloadIndex;
}

pub fn serialize(allocator: std.mem.Allocator, doc: core.Document) ![]u8 {
    var strings = StringCtx.init();
    defer strings.deinit(allocator);
    var kv_pairs = std.ArrayList(KVPairDisk).empty;
    defer kv_pairs.deinit(allocator);

    const doc_meta = try collectMetadata(&strings, &kv_pairs, allocator, doc.metadata);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var section_disks = std.ArrayList(SectionDisk).empty;
    defer section_disks.deinit(allocator);
    for (doc.sections) |section| {
        try section_disks.append(allocator, .{
            .meta = try collectMetadata(&strings, &kv_pairs, allocator, section.metadata),
            .title_ref = try strings.emitOpt(section.title, allocator),
            .first_child_ref = optU32(section.first_child_ref),
            .child_count = section.child_count,
        });
    }

    var paragraph_disks = std.ArrayList(ChildSpanDisk).empty;
    defer paragraph_disks.deinit(allocator);
    for (doc.paragraphs) |paragraph| {
        try paragraph_disks.append(allocator, .{ .first_child_ref = optU32(paragraph.first_child_ref), .child_count = paragraph.child_count });
    }

    var list_disks = std.ArrayList(ListDisk).empty;
    defer list_disks.deinit(allocator);
    for (doc.lists) |list| {
        try list_disks.append(allocator, .{ .kind = @intFromEnum(list.kind), .first_child_ref = optU32(list.first_child_ref), .child_count = list.child_count });
    }

    var list_item_disks = std.ArrayList(ChildSpanDisk).empty;
    defer list_item_disks.deinit(allocator);
    for (doc.list_items) |item| {
        try list_item_disks.append(allocator, .{ .first_child_ref = optU32(item.first_child_ref), .child_count = item.child_count });
    }

    var table_disks = std.ArrayList(ChildSpanDisk).empty;
    defer table_disks.deinit(allocator);
    for (doc.tables) |table| {
        try table_disks.append(allocator, .{ .first_child_ref = optU32(table.first_child_ref), .child_count = table.child_count });
    }

    var row_disks = std.ArrayList(ChildSpanDisk).empty;
    defer row_disks.deinit(allocator);
    for (doc.rows) |row| {
        try row_disks.append(allocator, .{ .first_child_ref = optU32(row.first_child_ref), .child_count = row.child_count });
    }

    var cell_disks = std.ArrayList(ChildSpanDisk).empty;
    defer cell_disks.deinit(allocator);
    for (doc.cells) |cell| {
        try cell_disks.append(allocator, .{ .first_child_ref = optU32(cell.first_child_ref), .child_count = cell.child_count });
    }

    var block_disks = std.ArrayList(BlockDisk).empty;
    defer block_disks.deinit(allocator);
    for (doc.blocks) |block| {
        try block_disks.append(allocator, .{
            .meta = try collectMetadata(&strings, &kv_pairs, allocator, block.metadata),
            .first_child_ref = optU32(block.first_child_ref),
            .child_count = block.child_count,
        });
    }

    var text_disks = std.ArrayList(TextDisk).empty;
    defer text_disks.deinit(allocator);
    for (doc.texts) |text| try text_disks.append(allocator, .{ .value_ref = try strings.emit(text.value, allocator) });

    var link_disks = std.ArrayList(LinkDisk).empty;
    defer link_disks.deinit(allocator);
    for (doc.links) |link| try link_disks.append(allocator, .{ .target_ref = try strings.emit(link.target, allocator), .label = optU32(link.label) });

    var ref_disks = std.ArrayList(LinkDisk).empty;
    defer ref_disks.deinit(allocator);
    for (doc.references) |reference| try ref_disks.append(allocator, .{ .target_ref = try strings.emit(reference.target, allocator), .label = optU32(reference.label) });

    var anchor_disks = std.ArrayList(AnchorDisk).empty;
    defer anchor_disks.deinit(allocator);
    for (doc.anchors) |anchor| try anchor_disks.append(allocator, .{ .name_ref = try strings.emit(anchor.name, allocator) });

    var emphasis_disks = std.ArrayList(ChildSpanDisk).empty;
    defer emphasis_disks.deinit(allocator);
    for (doc.emphases) |entry| try emphasis_disks.append(allocator, .{ .first_child_ref = optU32(entry.first_child_ref), .child_count = entry.child_count });

    var strong_disks = std.ArrayList(ChildSpanDisk).empty;
    defer strong_disks.deinit(allocator);
    for (doc.strongs) |entry| try strong_disks.append(allocator, .{ .first_child_ref = optU32(entry.first_child_ref), .child_count = entry.child_count });

    const header = HeaderDisk{
        .magic = MAGIC.*, 
        .format_version = FORMAT_VERSION,
        .doc_meta = doc_meta,
        .roots_count = @intCast(doc.roots.len),
        .node_child_refs_count = @intCast(doc.node_child_refs.len),
        .inline_child_refs_count = @intCast(doc.inline_child_refs.len),
        .node_refs_count = @intCast(doc.nodes.len),
        .inline_refs_count = @intCast(doc.inlines.len),
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
        .string_refs_count = @intCast(strings.refs.items.len),
        .kv_pairs_count = @intCast(kv_pairs.items.len),
        .bytes_len = @intCast(strings.bytes.items.len),
    };

    const header_bytes = try allocator.alloc(u8, HeaderDisk.byte_size);
    defer allocator.free(header_bytes);
    HeaderDisk.encode(header_bytes, header);
    try out.appendSlice(allocator, header_bytes);

    try appendU32Slice(&out, allocator, doc.roots);
    try appendU32Slice(&out, allocator, doc.node_child_refs);
    try appendU32Slice(&out, allocator, doc.inline_child_refs);
    try appendNodeRefs(&out, allocator, doc.nodes);
    try appendInlineRefs(&out, allocator, doc.inlines);
    try appendSectionDisks(&out, allocator, section_disks.items);
    try appendChildSpans(&out, allocator, paragraph_disks.items);
    try appendListDisks(&out, allocator, list_disks.items);
    try appendChildSpans(&out, allocator, list_item_disks.items);
    try appendChildSpans(&out, allocator, table_disks.items);
    try appendChildSpans(&out, allocator, row_disks.items);
    try appendChildSpans(&out, allocator, cell_disks.items);
    try appendBlockDisks(&out, allocator, block_disks.items);
    try appendTextDisks(&out, allocator, text_disks.items);
    try appendLinkDisks(&out, allocator, link_disks.items);
    try appendLinkDisks(&out, allocator, ref_disks.items);
    try appendAnchorDisks(&out, allocator, anchor_disks.items);
    try appendChildSpans(&out, allocator, emphasis_disks.items);
    try appendChildSpans(&out, allocator, strong_disks.items);
    try appendStringRefs(&out, allocator, strings.refs.items);
    try appendKvPairs(&out, allocator, kv_pairs.items);
    try out.appendSlice(allocator, strings.bytes.items);

    return out.toOwnedSlice(allocator);
}

pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !core.Document {
    _ = try validate(bytes);
    return try deserializeUnvalidated(allocator, bytes);
}

fn deserializeUnvalidated(backing: std.mem.Allocator, bytes: []const u8) !core.Document {
    const header = try validateStructural(bytes);
    var offset: usize = HeaderDisk.byte_size;
    const arena_state = try backing.create(std.heap.ArenaAllocator);
    errdefer backing.destroy(arena_state);
    arena_state.* = std.heap.ArenaAllocator.init(backing);
    errdefer arena_state.deinit();
    const aa = arena_state.allocator();

    const roots_bytes = readSection(&offset, bytes, header.roots_count, 4);
    const node_child_refs_bytes = readSection(&offset, bytes, header.node_child_refs_count, 4);
    const inline_child_refs_bytes = readSection(&offset, bytes, header.inline_child_refs_count, 4);
    const node_refs_bytes = readSection(&offset, bytes, header.node_refs_count, NodeRefDisk.size);
    const inline_refs_bytes = readSection(&offset, bytes, header.inline_refs_count, InlineRefDisk.size);
    const sections_bytes = readSection(&offset, bytes, header.sections_count, SectionDisk.size);
    const paragraphs_bytes = readSection(&offset, bytes, header.paragraphs_count, ChildSpanDisk.size);
    const lists_bytes = readSection(&offset, bytes, header.lists_count, ListDisk.size);
    const list_items_bytes = readSection(&offset, bytes, header.list_items_count, ChildSpanDisk.size);
    const tables_bytes = readSection(&offset, bytes, header.tables_count, ChildSpanDisk.size);
    const rows_bytes = readSection(&offset, bytes, header.rows_count, ChildSpanDisk.size);
    const cells_bytes = readSection(&offset, bytes, header.cells_count, ChildSpanDisk.size);
    const blocks_bytes = readSection(&offset, bytes, header.blocks_count, BlockDisk.size);
    const texts_bytes = readSection(&offset, bytes, header.texts_count, TextDisk.size);
    const links_bytes = readSection(&offset, bytes, header.links_count, LinkDisk.size);
    const references_bytes = readSection(&offset, bytes, header.references_count, LinkDisk.size);
    const anchors_bytes = readSection(&offset, bytes, header.anchors_count, AnchorDisk.size);
    const emphases_bytes = readSection(&offset, bytes, header.emphases_count, ChildSpanDisk.size);
    const strongs_bytes = readSection(&offset, bytes, header.strongs_count, ChildSpanDisk.size);
    const string_refs_bytes = readSection(&offset, bytes, header.string_refs_count, StringRefDisk.size);
    const kv_pairs_bytes = readSection(&offset, bytes, header.kv_pairs_count, KVPairDisk.size);
    const bytes_arena = bytes[offset .. offset + header.bytes_len];

    const string_refs = try decodeStringRefs(aa, string_refs_bytes, header.string_refs_count);
    const kv_pairs = try decodeKvPairs(aa, kv_pairs_bytes, header.kv_pairs_count);

    return .{
        .arena = arena_state,
        .arena_owner = backing,
        .metadata = decodeMetadata(aa, header.doc_meta, string_refs, bytes_arena, kv_pairs),
        .roots = try decodeU32Slice(aa, roots_bytes, header.roots_count),
        .node_child_refs = try decodeU32Slice(aa, node_child_refs_bytes, header.node_child_refs_count),
        .inline_child_refs = try decodeU32Slice(aa, inline_child_refs_bytes, header.inline_child_refs_count),
        .nodes = try decodeNodeRefs(aa, node_refs_bytes, header.node_refs_count),
        .inlines = try decodeInlineRefs(aa, inline_refs_bytes, header.inline_refs_count),
        .sections = try decodeSections(aa, sections_bytes, header.sections_count, string_refs, bytes_arena, kv_pairs),
        .paragraphs = try decodeChildSpanSlice(core.ParagraphData, aa, paragraphs_bytes, header.paragraphs_count),
        .lists = try decodeLists(aa, lists_bytes, header.lists_count),
        .list_items = try decodeChildSpanSlice(core.ListItemData, aa, list_items_bytes, header.list_items_count),
        .tables = try decodeChildSpanSlice(core.TableData, aa, tables_bytes, header.tables_count),
        .rows = try decodeChildSpanSlice(core.TableRowData, aa, rows_bytes, header.rows_count),
        .cells = try decodeChildSpanSlice(core.TableCellData, aa, cells_bytes, header.cells_count),
        .blocks = try decodeBlocks(aa, blocks_bytes, header.blocks_count, string_refs, bytes_arena, kv_pairs),
        .texts = try decodeTexts(aa, texts_bytes, header.texts_count, string_refs, bytes_arena),
        .links = try decodeLinks(aa, links_bytes, header.links_count, string_refs, bytes_arena),
        .references = try decodeLinksAsReferences(aa, references_bytes, header.references_count, string_refs, bytes_arena),
        .anchors = try decodeAnchors(aa, anchors_bytes, header.anchors_count, string_refs, bytes_arena),
        .emphases = try decodeChildSpanSlice(core.EmphasisData, aa, emphases_bytes, header.emphases_count),
        .strongs = try decodeChildSpanSlice(core.StrongData, aa, strongs_bytes, header.strongs_count),
    };
}

fn collectMetadata(strings: *StringCtx, kv_pairs: *std.ArrayList(KVPairDisk), allocator: std.mem.Allocator, meta: core.Metadata) !MetadataDisk {
    const roles_first: u32 = @intCast(strings.refs.items.len);
    for (meta.roles) |role| _ = try strings.emit(role, allocator);
    const attrs_first: u32 = @intCast(kv_pairs.items.len);
    for (meta.attrs) |attr| {
        try kv_pairs.append(allocator, .{ .key_ref = try strings.emit(attr.key, allocator), .value_ref = try strings.emit(attr.value, allocator) });
    }
    return .{
        .id_ref = try strings.emitOpt(meta.id, allocator),
        .title_ref = try strings.emitOpt(meta.title, allocator),
        .roles_first = roles_first,
        .roles_count = @intCast(meta.roles.len),
        .attrs_first = attrs_first,
        .attrs_count = @intCast(meta.attrs.len),
    };
}

fn appendU32Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u32) !void {
    for (values) |value| {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, value, .little);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendNodeRefs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const core.NodeRef) !void {
    for (values) |value| {
        var buf: [NodeRefDisk.size]u8 = undefined;
        const disk = NodeRefDisk{ .tag = @intFromEnum(value.tag), .index = value.index };
        NodeRefDisk.encode(&buf, disk);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendInlineRefs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const core.InlineRef) !void {
    for (values) |value| {
        var buf: [InlineRefDisk.size]u8 = undefined;
        const disk = InlineRefDisk{ .tag = @intFromEnum(value.tag), .index = value.index };
        InlineRefDisk.encode(&buf, disk);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendSectionDisks(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const SectionDisk) !void {
    for (values) |value| {
        var buf: [SectionDisk.size]u8 = undefined;
        SectionDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendChildSpans(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const ChildSpanDisk) !void {
    for (values) |value| {
        var buf: [ChildSpanDisk.size]u8 = undefined;
        ChildSpanDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendListDisks(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const ListDisk) !void {
    for (values) |value| {
        var buf: [ListDisk.size]u8 = undefined;
        ListDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendBlockDisks(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const BlockDisk) !void {
    for (values) |value| {
        var buf: [BlockDisk.size]u8 = undefined;
        BlockDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendTextDisks(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const TextDisk) !void {
    for (values) |value| {
        var buf: [TextDisk.size]u8 = undefined;
        TextDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendLinkDisks(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const LinkDisk) !void {
    for (values) |value| {
        var buf: [LinkDisk.size]u8 = undefined;
        LinkDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendAnchorDisks(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const AnchorDisk) !void {
    for (values) |value| {
        var buf: [AnchorDisk.size]u8 = undefined;
        AnchorDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendStringRefs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const StringRefDisk) !void {
    for (values) |value| {
        var buf: [StringRefDisk.size]u8 = undefined;
        StringRefDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn appendKvPairs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const KVPairDisk) !void {
    for (values) |value| {
        var buf: [KVPairDisk.size]u8 = undefined;
        KVPairDisk.encode(&buf, value);
        try out.appendSlice(allocator, &buf);
    }
}

fn readSection(offset: *usize, bytes: []const u8, count: u32, rec_size: usize) []const u8 {
    const start = offset.*;
    offset.* += count * rec_size;
    return bytes[start..][0 .. count * rec_size];
}

fn decodeU32Slice(allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]u32 {
    var out = try std.ArrayList(u32).initCapacity(allocator, count);
    for (0..count) |i| out.appendAssumeCapacity(std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little));
    return out.items;
}

fn decodeStringRefs(allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]StringRefDisk {
    var out = try std.ArrayList(StringRefDisk).initCapacity(allocator, count);
    for (0..count) |i| out.appendAssumeCapacity(StringRefDisk.decode(bytes[i * StringRefDisk.size ..][0..StringRefDisk.size]));
    return out.items;
}

fn decodeKvPairs(allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]KVPairDisk {
    var out = try std.ArrayList(KVPairDisk).initCapacity(allocator, count);
    for (0..count) |i| out.appendAssumeCapacity(KVPairDisk.decode(bytes[i * KVPairDisk.size ..][0..KVPairDisk.size]));
    return out.items;
}

fn decodeNodeRefs(allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]core.NodeRef {
    var out = try std.ArrayList(core.NodeRef).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = NodeRefDisk.decode(bytes[i * NodeRefDisk.size ..][0..NodeRefDisk.size]);
        out.appendAssumeCapacity(.{ .tag = @enumFromInt(disk.tag), .index = disk.index });
    }
    return out.items;
}

fn decodeInlineRefs(allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]core.InlineRef {
    var out = try std.ArrayList(core.InlineRef).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = InlineRefDisk.decode(bytes[i * InlineRefDisk.size ..][0..InlineRefDisk.size]);
        out.appendAssumeCapacity(.{ .tag = @enumFromInt(disk.tag), .index = disk.index });
    }
    return out.items;
}

fn decodeSections(allocator: std.mem.Allocator, bytes: []const u8, count: u32, refs: []const StringRefDisk, arena_bytes: []const u8, kv_pairs: []const KVPairDisk) ![]core.SectionData {
    var out = try std.ArrayList(core.SectionData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = SectionDisk.decode(bytes[i * SectionDisk.size ..][0..SectionDisk.size]);
        out.appendAssumeCapacity(.{
            .metadata = decodeMetadata(allocator, disk.meta, refs, arena_bytes, kv_pairs),
            .title = if (disk.title_ref != NULL_U32) resolveStr(refs, arena_bytes, disk.title_ref) else null,
            .first_child_ref = p32(disk.first_child_ref),
            .child_count = disk.child_count,
        });
    }
    return out.items;
}

fn decodeLists(allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]core.ListData {
    var out = try std.ArrayList(core.ListData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = ListDisk.decode(bytes[i * ListDisk.size ..][0..ListDisk.size]);
        out.appendAssumeCapacity(.{ .kind = @enumFromInt(disk.kind), .first_child_ref = p32(disk.first_child_ref), .child_count = disk.child_count });
    }
    return out.items;
}

fn decodeBlocks(allocator: std.mem.Allocator, bytes: []const u8, count: u32, refs: []const StringRefDisk, arena_bytes: []const u8, kv_pairs: []const KVPairDisk) ![]core.BlockData {
    var out = try std.ArrayList(core.BlockData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = BlockDisk.decode(bytes[i * BlockDisk.size ..][0..BlockDisk.size]);
        out.appendAssumeCapacity(.{ .metadata = decodeMetadata(allocator, disk.meta, refs, arena_bytes, kv_pairs), .first_child_ref = p32(disk.first_child_ref), .child_count = disk.child_count });
    }
    return out.items;
}

fn decodeChildSpanSlice(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, count: u32) ![]T {
    var out = try std.ArrayList(T).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = ChildSpanDisk.decode(bytes[i * ChildSpanDisk.size ..][0..ChildSpanDisk.size]);
        out.appendAssumeCapacity(.{ .first_child_ref = p32(disk.first_child_ref), .child_count = disk.child_count });
    }
    return out.items;
}

fn decodeTexts(allocator: std.mem.Allocator, bytes: []const u8, count: u32, refs: []const StringRefDisk, arena_bytes: []const u8) ![]core.TextData {
    var out = try std.ArrayList(core.TextData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = TextDisk.decode(bytes[i * TextDisk.size ..][0..TextDisk.size]);
        out.appendAssumeCapacity(.{ .value = resolveStr(refs, arena_bytes, disk.value_ref) });
    }
    return out.items;
}

fn decodeLinks(allocator: std.mem.Allocator, bytes: []const u8, count: u32, refs: []const StringRefDisk, arena_bytes: []const u8) ![]core.LinkData {
    var out = try std.ArrayList(core.LinkData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = LinkDisk.decode(bytes[i * LinkDisk.size ..][0..LinkDisk.size]);
        out.appendAssumeCapacity(.{ .target = resolveStr(refs, arena_bytes, disk.target_ref), .label = p32(disk.label) });
    }
    return out.items;
}

fn decodeLinksAsReferences(allocator: std.mem.Allocator, bytes: []const u8, count: u32, refs: []const StringRefDisk, arena_bytes: []const u8) ![]core.ReferenceData {
    var out = try std.ArrayList(core.ReferenceData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = LinkDisk.decode(bytes[i * LinkDisk.size ..][0..LinkDisk.size]);
        out.appendAssumeCapacity(.{ .target = resolveStr(refs, arena_bytes, disk.target_ref), .label = p32(disk.label) });
    }
    return out.items;
}

fn decodeAnchors(allocator: std.mem.Allocator, bytes: []const u8, count: u32, refs: []const StringRefDisk, arena_bytes: []const u8) ![]core.AnchorData {
    var out = try std.ArrayList(core.AnchorData).initCapacity(allocator, count);
    for (0..count) |i| {
        const disk = AnchorDisk.decode(bytes[i * AnchorDisk.size ..][0..AnchorDisk.size]);
        out.appendAssumeCapacity(.{ .name = resolveStr(refs, arena_bytes, disk.name_ref) });
    }
    return out.items;
}

fn decodeMetadata(allocator: std.mem.Allocator, disk: MetadataDisk, refs: []const StringRefDisk, arena_bytes: []const u8, kv_pairs: []const KVPairDisk) core.Metadata {
    const roles = if (disk.roles_count == 0) &.{} else blk: {
        const out = allocator.alloc([]const u8, disk.roles_count) catch unreachable;
        for (0..disk.roles_count) |i| {
            out[i] = resolveStr(refs, arena_bytes, disk.roles_first + @as(u32, @intCast(i)));
        }
        break :blk out;
    };
    const attrs = if (disk.attrs_count == 0) &.{} else blk: {
        const out = allocator.alloc(core.KVPair, disk.attrs_count) catch unreachable;
        for (0..disk.attrs_count) |i| {
            const kv = kv_pairs[disk.attrs_first + @as(u32, @intCast(i))];
            out[i] = .{ .key = resolveStr(refs, arena_bytes, kv.key_ref), .value = resolveStr(refs, arena_bytes, kv.value_ref) };
        }
        break :blk out;
    };
    return .{
        .id = if (disk.id_ref != NULL_U32) resolveStr(refs, arena_bytes, disk.id_ref) else null,
        .title = if (disk.title_ref != NULL_U32) resolveStr(refs, arena_bytes, disk.title_ref) else null,
        .roles = roles,
        .attrs = attrs,
    };
}

fn resolveStr(refs: []const StringRefDisk, arena_bytes: []const u8, idx: u32) []const u8 {
    const sr = refs[idx];
    return arena_bytes[sr.start .. sr.start + sr.len];
}

fn optU32(value: ?u32) u32 {
    return value orelse NULL_U32;
}

fn p32(value: u32) ?u32 {
    return if (value == NULL_U32) null else value;
}

test "validate rejects bad magic" {
    var buf: [HeaderDisk.byte_size]u8 = undefined;
    @memset(&buf, 0);
    try std.testing.expectError(error.InvalidMagic, validate(&buf));
}
