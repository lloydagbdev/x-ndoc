const std = @import("std");
const api = @import("api.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const events = &[_]api.Event{
        .{ .begin_section = .{ .id = "overview", .title = "Overview" } },
        .{ .begin_paragraph = {} },
        .{ .text = "Hello from the event stream adapter. " },
        .{ .reference = .{ .target = "overview", .label = "self" } },
        .{ .end_paragraph = {} },
        .{ .end_section = {} },
    };

    var doc = try api.ingest.lowerEventStream(allocator, .{ .title = "Event Demo" }, events);
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

    var scan = try api.privacy_scan.scan(doc, allocator);
    defer scan.deinit();

    std.debug.print("mode=events\n", .{});
    std.debug.print("roots={d} nodes={d} inlines={d}\n", .{ doc.roots.len, doc.nodes.len, doc.inlines.len });
    std.debug.print("validation={d}\n", .{diags.len});
    std.debug.print("hash=", .{});
    for (api.hash_doc(doc)) |byte| std.debug.print("{x:0>2}", .{byte});
    std.debug.print("\nserialized={d} privacy_findings={d}\n", .{ bytes.len, scan.findings.len });
    std.debug.print("{s}", .{html});
}
