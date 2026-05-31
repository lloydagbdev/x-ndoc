const std = @import("std");
const author = @import("author_ir.zig");
const build = @import("build_ir.zig");

pub fn buildExampleDocument(allocator: std.mem.Allocator) !author.Document {
    var b = build.Builder.init(allocator);

    const doc_meta = try b.metadata(.{ .title = "Iteration 4 Smoke Test" });

    const intro_para = try b.paragraph(&.{
        try b.inlineText("This document exercises the "),
        try b.inlineEmphasis(&.{try b.inlineText("it4 core")}),
        try b.inlineText(" runtime."),
    });
    const overview_sec = try b.section(try b.metadata(.{ .id = "overview" }), "Overview", &.{intro_para});

    const list_item1 = try b.listItem(&.{try b.paragraph(&.{ try b.inlineText("First item with "), try b.inlineStrong(&.{try b.inlineText("strong emphasis")}) })});
    const nested_item1 = try b.listItem(&.{try b.paragraph(&.{try b.inlineText("Nested item one")})});
    const nested_item2 = try b.listItem(&.{try b.paragraph(&.{try b.inlineText("Nested item two")})});
    const nested_list = try b.list(.ordered, &.{ nested_item1, nested_item2 });
    const list_item2 = try b.listItem(&.{
        try b.paragraph(&.{ try b.inlineText("Second item with a "), try b.inlineLink("https://example.com", "link") }),
        nested_list,
    });
    const features_sec = try b.section(try b.metadata(.{ .id = "features" }), "Features", &.{try b.list(.unordered, &.{ list_item1, list_item2 })});

    const row1 = try b.tableRow(&.{
        try b.tableCell(&.{try b.paragraph(&.{try b.inlineText("API")})}),
        try b.tableCell(&.{try b.paragraph(&.{try b.inlineText("Version")})}),
    });
    const row2 = try b.tableRow(&.{
        try b.tableCell(&.{try b.paragraph(&.{try b.inlineText("GET /users")})}),
        try b.tableCell(&.{try b.paragraph(&.{try b.inlineText("2.1.0")})}),
    });
    const table_sec = try b.section(try b.metadata(.{ .id = "tables" }), "Tables", &.{
        try b.paragraph(&.{try b.inlineAnchor("tables-anchor")}),
        try b.table(&.{ row1, row2 }),
    });

    const footer = try b.genericBlock(try b.metadata(.{ .roles = &.{"footer"} }), &.{try b.paragraph(&.{
        try b.inlineText("See "),
        try b.inlineReference("overview", "Overview"),
        try b.inlineText(" and "),
        try b.inlineReference("features", "Features"),
    })});

    return try b.document(doc_meta, &.{ overview_sec, features_sec, table_sec, footer });
}

pub fn hexLower(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const chars = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, i| {
        out[i * 2] = chars[byte >> 4];
        out[i * 2 + 1] = chars[byte & 0x0f];
    }
    return out;
}
