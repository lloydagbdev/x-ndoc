const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;
const core = @import("core_ir.zig");

pub const FindingKind = enum {
    email,
    url,
    api_key,
    ipv4,
    phone,
    custom,
};

pub const Location = union(enum) {
    text_inline: u32,
    link_target: u32,
    reference_target: u32,
    anchor_name: u32,
    section_metadata_id: u32,
    section_metadata_title: u32,
    section_metadata_attr: struct { section_idx: u32, entry_idx: u32, is_key: bool },
    block_metadata_id: u32,
    block_metadata_title: u32,
    block_metadata_attr: struct { block_idx: u32, entry_idx: u32, is_key: bool },
    document_metadata_id,
    document_metadata_title,
    document_metadata_attr: struct { entry_idx: u32, is_key: bool },
};

pub const Finding = struct {
    kind: FindingKind,
    location: Location,
    offset: u32,
    length: u32,
    text: []const u8,
};

pub const RedactionStrategy = enum {
    mask,
    remove,
    hash_content,
    replace,
};

pub const AuditEntry = struct {
    kind: FindingKind,
    location: Location,
    strategy: RedactionStrategy,
    original_slice: []const u8,
};

pub const Policy = struct {
    name: []const u8,
    redact_kinds: []const FindingKind,
    strategy: RedactionStrategy,
    replacement: ?[]const u8 = null,
};

pub const ScanResult = struct {
    findings: []Finding,
    state: std.heap.ArenaAllocator,

    pub fn deinit(self: *ScanResult) void {
        self.state.deinit();
        self.* = undefined;
    }
};

const known_api_key_prefixes = &[_][]const u8{
    "sk-",
    "pk-",
    "sk_live_",
    "sk_test_",
    "pk_live_",
    "pk_test_",
    "whsec_",
    "sk_",
    "rk_live_",
    "rk_test_",
};

pub fn isEmail(text: []const u8) bool {
    var at_pos: ?usize = null;
    var dot_after_at = false;
    for (text, 0..) |c, i| {
        if (c == '@' and at_pos == null) at_pos = i;
        if (at_pos != null and c == '.') dot_after_at = true;
        if (std.ascii.isWhitespace(c)) return false;
        if (c == '<' or c == '>') return false;
    }
    if (at_pos == null) return false;
    const local = text[0..at_pos.?];
    if (local.len == 0) return false;
    const domain = text[at_pos.? + 1 ..];
    if (domain.len == 0) return false;
    return dot_after_at;
}

pub fn isUrl(text: []const u8) bool {
    if (std.mem.startsWith(u8, text, "http://") or std.mem.startsWith(u8, text, "https://")) {
        if (text.len < 8) return false;
        const rest = if (std.mem.startsWith(u8, text, "https://")) text[8..] else text[7..];
        return rest.len > 0 and !std.ascii.isWhitespace(rest[0]);
    }
    return false;
}

pub fn isApiKey(text: []const u8) bool {
    for (known_api_key_prefixes) |prefix| {
        if (std.mem.startsWith(u8, text, prefix) and text.len > prefix.len) return true;
    }
    return false;
}

pub fn isIpv4(text: []const u8) bool {
    var dots: u8 = 0;
    var seg_val: u16 = 0;
    var seg_len: u8 = 0;
    for (text) |c| {
        if (c == '.') {
            if (seg_len == 0 or seg_val > 255) return false;
            dots += 1;
            seg_val = 0;
            seg_len = 0;
        } else if (std.ascii.isDigit(c)) {
            seg_val = seg_val * 10 + (c - '0');
            seg_len += 1;
            if (seg_len > 3) return false;
        } else {
            return false;
        }
    }
    if (seg_len == 0 or seg_val > 255) return false;
    return dots == 3;
}

pub fn isPhone(text: []const u8) bool {
    var digits: u8 = 0;
    for (text) |c| {
        if (std.ascii.isDigit(c)) {
            digits += 1;
        } else if (c == '(' or c == ')' or c == '-' or c == '+' or c == ' ' or c == '.') {
        } else {
            return false;
        }
    }
    return digits >= 7 and digits <= 15;
}

fn scanText(text: []const u8, allocator: std.mem.Allocator, results: *std.ArrayList(Finding), loc: Location) !void {
    if (isEmail(text)) try results.append(allocator, .{ .kind = .email, .location = loc, .offset = 0, .length = @intCast(text.len), .text = text });
    if (isUrl(text)) try results.append(allocator, .{ .kind = .url, .location = loc, .offset = 0, .length = @intCast(text.len), .text = text });
    if (isApiKey(text)) try results.append(allocator, .{ .kind = .api_key, .location = loc, .offset = 0, .length = @intCast(text.len), .text = text });
    if (isIpv4(text)) try results.append(allocator, .{ .kind = .ipv4, .location = loc, .offset = 0, .length = @intCast(text.len), .text = text });
    if (isPhone(text)) try results.append(allocator, .{ .kind = .phone, .location = loc, .offset = 0, .length = @intCast(text.len), .text = text });
}

pub fn scanDocument(doc: core.Document, allocator: std.mem.Allocator) !ScanResult {
    var results = std.ArrayList(Finding).empty;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const aa = arena_state.allocator();

    for (doc.texts, 0..) |t, i| try scanText(t.value, aa, &results, .{ .text_inline = @intCast(i) });
    for (doc.links, 0..) |l, i| try scanText(l.target, aa, &results, .{ .link_target = @intCast(i) });
    for (doc.references, 0..) |r, i| try scanText(r.target, aa, &results, .{ .reference_target = @intCast(i) });
    for (doc.anchors, 0..) |a, i| try scanText(a.name, aa, &results, .{ .anchor_name = @intCast(i) });

    for (doc.sections, 0..) |s, i| {
        const idx: u32 = @intCast(i);
        if (s.metadata.id) |id| try scanText(id, aa, &results, .{ .section_metadata_id = idx });
        if (s.metadata.title) |title| try scanText(title, aa, &results, .{ .section_metadata_title = idx });
        for (s.metadata.attrs, 0..) |attr, ai| {
            try scanText(attr.key, aa, &results, .{ .section_metadata_attr = .{ .section_idx = idx, .entry_idx = @intCast(ai), .is_key = true } });
            try scanText(attr.value, aa, &results, .{ .section_metadata_attr = .{ .section_idx = idx, .entry_idx = @intCast(ai), .is_key = false } });
        }
    }

    for (doc.blocks, 0..) |b, i| {
        const idx: u32 = @intCast(i);
        if (b.metadata.id) |id| try scanText(id, aa, &results, .{ .block_metadata_id = idx });
        if (b.metadata.title) |title| try scanText(title, aa, &results, .{ .block_metadata_title = idx });
        for (b.metadata.attrs, 0..) |attr, ai| {
            try scanText(attr.key, aa, &results, .{ .block_metadata_attr = .{ .block_idx = idx, .entry_idx = @intCast(ai), .is_key = true } });
            try scanText(attr.value, aa, &results, .{ .block_metadata_attr = .{ .block_idx = idx, .entry_idx = @intCast(ai), .is_key = false } });
        }
    }

    if (doc.metadata.id) |id| try scanText(id, aa, &results, .{ .document_metadata_id = {} });
    if (doc.metadata.title) |title| try scanText(title, aa, &results, .{ .document_metadata_title = {} });
    for (doc.metadata.attrs, 0..) |attr, ai| {
        try scanText(attr.key, aa, &results, .{ .document_metadata_attr = .{ .entry_idx = @intCast(ai), .is_key = true } });
        try scanText(attr.value, aa, &results, .{ .document_metadata_attr = .{ .entry_idx = @intCast(ai), .is_key = false } });
    }

    return .{ .findings = try results.toOwnedSlice(aa), .state = arena_state };
}

pub fn redactString(text: []const u8, strategy: RedactionStrategy, allocator: std.mem.Allocator, replacement: ?[]const u8) ![]const u8 {
    return switch (strategy) {
        .mask => blk: {
            const masked = try allocator.alloc(u8, text.len);
            @memset(masked, '*');
            break :blk masked;
        },
        .remove => &.{},
        .hash_content => blk: {
            var hasher = Blake3.init(.{});
            hasher.update(text);
            var digest: [Blake3.digest_length]u8 = undefined;
            hasher.final(&digest);
            const hex = "0123456789abcdef";
            const out = try allocator.alloc(u8, 64);
            for (digest, 0..) |byte, i| {
                out[i * 2] = hex[byte >> 4];
                out[i * 2 + 1] = hex[byte & 0x0F];
            }
            break :blk out;
        },
        .replace => if (replacement) |rep| try allocator.dupe(u8, rep) else text,
    };
}

pub fn applyPolicy(findings: []const Finding, policy: Policy, allocator: std.mem.Allocator) ![]AuditEntry {
    var entries = std.ArrayList(AuditEntry).empty;
    for (findings) |finding| {
        for (policy.redact_kinds) |kind| {
            if (finding.kind == kind) {
                try entries.append(allocator, .{
                    .kind = finding.kind,
                    .location = finding.location,
                    .strategy = policy.strategy,
                    .original_slice = finding.text,
                });
                break;
            }
        }
    }
    return entries.toOwnedSlice(allocator);
}

pub const publicPolicy = Policy{ .name = "public", .redact_kinds = &.{ .email, .api_key, .phone }, .strategy = .mask };
pub const internalPolicy = Policy{ .name = "internal", .redact_kinds = &.{.api_key}, .strategy = .mask };
pub const confidentialPolicy = Policy{ .name = "confidential", .redact_kinds = &.{ .email, .api_key, .ipv4, .phone, .url }, .strategy = .remove };
pub const strictPolicy = Policy{ .name = "strict", .redact_kinds = &.{ .email, .url, .api_key, .ipv4, .phone, .custom }, .strategy = .hash_content };

const test_allocator = std.testing.allocator;

test "email detection" {
    try std.testing.expect(isEmail("alice@example.com"));
    try std.testing.expect(!isEmail("not-email"));
}

test "url detection" {
    try std.testing.expect(isUrl("https://example.com"));
    try std.testing.expect(!isUrl("ftp://example.com"));
}

test "api key detection" {
    try std.testing.expect(isApiKey("sk-live-abc123"));
    try std.testing.expect(!isApiKey("normal text"));
}

test "redact hash" {
    const result = try redactString("hello", .hash_content, test_allocator, null);
    defer test_allocator.free(result);
    try std.testing.expectEqual(@as(usize, 64), result.len);
}
