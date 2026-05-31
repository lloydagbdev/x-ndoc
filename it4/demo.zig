const std = @import("std");
const api = @import("api.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var doc = try buildFromParsed(allocator);
    defer doc.deinit();

    const diags = try api.validate_doc.document(allocator, doc);
    defer {
        for (diags) |d| allocator.free(d.message);
        allocator.free(diags);
    }

    const html = try api.emit.html(allocator, doc);
    defer allocator.free(html);

    const bytes = try api.binary.serialize(allocator, doc);
    defer allocator.free(bytes);

    var scan = try api.privacy_scan.scan( doc, allocator);
    defer scan.deinit();

    std.debug.print("mode=parsed\n", .{});
    std.debug.print("roots={d} nodes={d} inlines={d}\n", .{ doc.roots.len, doc.nodes.len, doc.inlines.len });
    std.debug.print("validation={d}\n", .{diags.len});
    std.debug.print("hash=", .{});
    for (api.hash_doc(doc)) |byte| std.debug.print("{x:0>2}", .{byte});
    std.debug.print("\nserialized={d} privacy_findings={d}\n", .{ bytes.len, scan.findings.len });
    std.debug.print("{s}", .{html});
}

fn buildFromParsed(allocator: std.mem.Allocator) !api.CoreDocument {
    const parsed = api.ParsedDocument{
        .metadata = .{ .title = "Parsed Demo" },
        .blocks = &.{
            .{ .section = .{
                .metadata = .{ .id = "intro" },
                .title = "Intro",
                .children = &.{
                    .{ .paragraph = &.{
                        .{ .text = "Hello from the parsed adapter. Visit " },
                        .{ .link = .{ .target = "https://example.com", .label = "example" } },
                    } },
                },
            } },
        },
    };
    return try api.ingest.lowerParsedDocument(allocator, parsed);
}
