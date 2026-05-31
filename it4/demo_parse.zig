const std = @import("std");
const api = @import("api.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        "= Parser Demo\n" ++
        "# Overview\n" ++
        "Hello **strong** and *soft* text with [link](https://example.com).\n\n" ++
        "- First item\n" ++
        "- Second item\n\n" ++
        "| A | B |\n" ++
        "| 1 | 2 |\n";

    var doc = try api.parseMiniMarkdown(allocator, source);
    defer doc.deinit();

    const html = try api.emit.html(allocator, doc);
    defer allocator.free(html);

    std.debug.print("mode=parser\n", .{});
    std.debug.print("roots={d} nodes={d} inlines={d}\n", .{ doc.roots.len, doc.nodes.len, doc.inlines.len });
    std.debug.print("{s}", .{html});
}
