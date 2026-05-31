const std = @import("std");
const lower = @import("lower.zig");
const validate_mod = @import("validate.zig");
const traverse = @import("traverse.zig");
const emit_html = @import("emit_html.zig");
const hash_mod = @import("hash.zig");
const serialize_mod = @import("serialize.zig");
const privacy_mod = @import("privacy.zig");
const smoke = @import("smoke_support.zig");

pub fn main() !void {
    var arena_outer = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_outer.deinit();
    const allocator = arena_outer.allocator();

    var doc = try smoke.buildExampleDocument(allocator);
    defer doc.deinit(allocator);

    var core_doc = try lower.lower(allocator, &doc);
    defer core_doc.deinit();

    const diags = try validate_mod.validate(allocator, core_doc);
    defer {
        for (diags) |d| allocator.free(d.message);
        allocator.free(diags);
    }

    std.debug.print("=== it4 core ===\n", .{});
    std.debug.print("roots={d} nodes={d} inlines={d}\n", .{ core_doc.roots.len, core_doc.nodes.len, core_doc.inlines.len });
    std.debug.print("validation={d}\n", .{diags.len});

    var walker = traverse.Walker.init(allocator, core_doc);
    defer walker.deinit();
    try walker.walkDocument();
    var node_count: usize = 0;
    var inline_count: usize = 0;
    while (walker.next()) |event| {
        switch (event) {
            .node => |nr| {
                node_count += 1;
                try walker.pushNodeChildren(nr.entry);
            },
            .inline_el => |ir| {
                inline_count += 1;
                try walker.pushInlineChildren(ir.entry);
            },
        }
    }
    std.debug.print("walked nodes={d} inlines={d}\n", .{ node_count, inline_count });

    const digest = hash_mod.hashDocument(core_doc);
    std.debug.print("hash=", .{});
    for (digest) |b| std.debug.print("{x:0>2}", .{b});
    std.debug.print("\n", .{});

    const html = try emit_html.emitHtml(allocator, core_doc);
    defer allocator.free(html);
    const binary = try serialize_mod.serialize(allocator, core_doc);
    defer allocator.free(binary);
    const report = try serialize_mod.validate(binary);
    std.debug.print("serialized bytes={d} strings={d}\n", .{ report.total_bytes, report.string_count });

    var scan_result = try privacy_mod.scanDocument(core_doc, allocator);
    defer scan_result.deinit();
    const audit = try privacy_mod.applyPolicy(scan_result.findings, privacy_mod.publicPolicy, allocator);
    defer allocator.free(audit);
    std.debug.print("privacy findings={d} public redactions={d}\n", .{ scan_result.findings.len, audit.len });

    std.debug.print("{s}", .{html});
}
