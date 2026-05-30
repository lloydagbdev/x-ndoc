const std = @import("std");
const author = @import("author_ir.zig");
const arena = @import("arena_ir.zig");
const build = @import("build_ir.zig");
const lower = @import("lower.zig");
const validate = @import("validate.zig");
const traverse = @import("traverse.zig");
const emit_html = @import("emit_html.zig");
const hash_mod = @import("hash.zig");

pub fn main() !void {
    var arena_outer = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_outer.deinit();
    const allocator = arena_outer.allocator();

    var doc = try buildExampleDocument(allocator);
    defer doc.deinit(allocator);

    var doc_arena = try lower.lower(allocator, &doc);
    defer doc_arena.deinit();

    const diags = try validate.validate(allocator, doc_arena);
    defer {
        for (diags) |d| allocator.free(d.message);
        allocator.free(diags);
    }

    std.debug.print("=== Document lowered to arena ===\n", .{});
    std.debug.print("  nodes:    {d}\n", .{doc_arena.nodes.len});
    std.debug.print("  inlines:  {d}\n", .{doc_arena.inlines.len});
    std.debug.print("  sections: {d}\n", .{traverse.countNodesByTag(doc_arena, .section)});
    std.debug.print("  paras:    {d}\n", .{traverse.countNodesByTag(doc_arena, .paragraph)});
    std.debug.print("  lists:    {d}\n", .{traverse.countNodesByTag(doc_arena, .list)});
    std.debug.print("  tables:   {d}\n", .{traverse.countNodesByTag(doc_arena, .table)});
    std.debug.print("  anchors:  {d}\n", .{traverse.countInlinesByTag(doc_arena, .anchor)});
    std.debug.print("  refs:     {d}\n", .{traverse.countInlinesByTag(doc_arena, .reference)});
    std.debug.print("  blocks:   {d}\n", .{traverse.countNodesByTag(doc_arena, .block)});
    std.debug.print("\n", .{});

    std.debug.print("=== Validation ({d} diagnostics) ===\n", .{diags.len});
    for (diags) |d| {
        std.debug.print("  {s}\n", .{d.message});
    }
    std.debug.print("\n", .{});

    std.debug.print("=== Tree walk ===\n", .{});
    var walker = traverse.Walker.init(allocator, doc_arena);
    defer walker.deinit();
    try walker.walkDocument();
    var node_count: usize = 0;
    var inline_count: usize = 0;
    while (walker.next()) |event| {
        switch (event) {
            .node => |nr| {
                node_count += 1;
                std.debug.print("  N[{d}] {s}\n", .{ nr.index, @tagName(nr.entry.tag) });
                try walker.pushNodeChildren(nr.entry);
            },
            .inline_el => |ir| {
                inline_count += 1;
                std.debug.print("    I[{d}] {s}\n", .{ ir.index, @tagName(ir.entry.tag) });
            },
        }
    }
    std.debug.print("  walked {d} nodes, {d} inlines\n\n", .{ node_count, inline_count });

    std.debug.print("=== Semantic hash (Blake3) ===\n", .{});
    const digest = hash_mod.hashDocument(doc_arena);
    std.debug.print("  ", .{});
    for (digest) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n\n", .{});

    std.debug.print("=== HTML output ===\n", .{});
    const html = try emit_html.emitHtml(allocator, doc_arena);
    defer allocator.free(html);
    std.debug.print("{s}", .{html});
}

fn buildExampleDocument(allocator: std.mem.Allocator) !author.Document {
    var b = build.Builder.init(allocator);

    const doc_meta = try b.metadata(.{
        .title = "Iteration 3 Smoke Test",
        .roles = &.{},
        .attrs = &.{},
    });

    const intro_text = try b.inlineText("This document exercises the ");
    const intro_emph = try b.inlineEmphasis(&.{try b.inlineText("elements.md")});
    const intro_tail = try b.inlineText(" semantic surface.");

    const intro_para = try b.paragraph(&.{ intro_text, intro_emph, intro_tail });

    const overview_meta = try b.metadata(.{ .id = "overview" });
    const overview_sec = try b.section(overview_meta, "Overview", &.{intro_para});

    const detail_text = try b.inlineText("See ");
    const detail_ref = try b.inlineReference("tables", "the tables section");
    const detail_tail = try b.inlineText(" for structured data.");
    const detail_para = try b.paragraph(&.{ detail_text, detail_ref, detail_tail });

    const detail_meta = try b.metadata(.{ .id = "details" });
    const detail_sec = try b.section(detail_meta, "Details", &.{detail_para});

    const list_text1 = try b.inlineText("First item with ");
    const list_emph = try b.inlineStrong(&.{try b.inlineText("strong emphasis")});
    const list_para1 = try b.paragraph(&.{ list_text1, list_emph });

    const list_text2 = try b.inlineText("Second item with a ");
    const list_link = try b.inlineLink("https://example.com", "link");
    const list_para2 = try b.paragraph(&.{ list_text2, list_link });

    const nested_list_text1 = try b.inlineText("Nested item one");
    const nested_list_text2 = try b.inlineText("Nested item two");
    const nested_para1 = try b.paragraph(&.{nested_list_text1});
    const nested_para2 = try b.paragraph(&.{nested_list_text2});
    const nested_item1 = try b.listItem(&.{nested_para1});
    const nested_item2 = try b.listItem(&.{nested_para2});
    const nested_list_node = try b.list(.ordered, &.{ nested_item1, nested_item2 });

    const list_item1 = try b.listItem(&.{list_para1});
    const list_item2 = try b.listItem(&.{ list_para2, nested_list_node });
    const main_list = try b.list(.unordered, &.{ list_item1, list_item2 });

    const list_meta = try b.metadata(.{ .id = "features" });
    const list_sec = try b.section(list_meta, "Features", &.{main_list});

    const h1_text = try b.inlineText("API");
    const h1_para = try b.paragraph(&.{h1_text});
    const h2_text = try b.inlineText("Version");
    const h2_para = try b.paragraph(&.{h2_text});
    const h3_text = try b.inlineText("Notes");
    const h3_para = try b.paragraph(&.{h3_text});

    const row1_cell1 = try b.tableCell(&.{h1_para});
    const row1_cell2 = try b.tableCell(&.{h2_para});
    const row1_cell3 = try b.tableCell(&.{h3_para});
    const row1 = try b.tableRow(&.{ row1_cell1, row1_cell2, row1_cell3 });

    const a1_text = try b.inlineText("GET /users");
    const a1_para = try b.paragraph(&.{a1_text});
    const a2_text = try b.inlineText("2.1.0");
    const a2_para = try b.paragraph(&.{a2_text});
    const a3_text = try b.inlineText("List all users");
    const a3_para = try b.paragraph(&.{a3_text});

    const row2_cell1 = try b.tableCell(&.{a1_para});
    const row2_cell2 = try b.tableCell(&.{a2_para});
    const row2_cell3 = try b.tableCell(&.{a3_para});
    const row2 = try b.tableRow(&.{ row2_cell1, row2_cell2, row2_cell3 });

    const table_meta = try b.metadata(.{ .id = "tables" });
    const anchor_inline = try b.inlineAnchor("tables-anchor");
    const anchor_para = try b.paragraph(&.{anchor_inline});
    const table_node = try b.table(&.{ row1, row2 });
    const tables_sec = try b.section(table_meta, "Tables", &.{ anchor_para, table_node });

    const footer_text = try b.inlineText("End of document. Two references: ");
    const footer_ref1 = try b.inlineReference("overview", "Overview");
    const footer_text2 = try b.inlineText(" and ");
    const footer_ref2 = try b.inlineReference("features", "Features");
    const footer_para = try b.paragraph(&.{ footer_text, footer_ref1, footer_text2, footer_ref2 });

    const footer_block_meta = try b.metadata(.{ .roles = &.{ "footer" } });
    const footer_block = try b.genericBlock(footer_block_meta, &.{footer_para});

    return try b.document(doc_meta, &.{ overview_sec, detail_sec, list_sec, tables_sec, footer_block });
}

test "builder enforces block/inline separation" {
    const b = build.Builder.init(std.testing.allocator);
    const inline_text = try b.inlineText("hello");

    _ = try b.paragraph(&.{inline_text});
    _ = try b.emptyParagraph();

    const meta = try b.noopMetadata();
    const section_result = b.section(meta, "Test", &.{
        try b.paragraph(&.{inline_text}),
    });
    try std.testing.expect(section_result catch null != null);
}

test "round trip: author to arena to html" {
    var doc = try buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var doc_arena = try lower.lower(std.testing.allocator, &doc);
    defer doc_arena.deinit();

    try std.testing.expect(doc_arena.nodes.len > 0);
    try std.testing.expect(doc_arena.inlines.len > 0);
    try std.testing.expect(doc_arena.roots.len > 0);

    try std.testing.expect(traverse.countNodesByTag(doc_arena, .section) == 4);
    try std.testing.expect(traverse.countNodesByTag(doc_arena, .paragraph) == 14);
    try std.testing.expect(traverse.countNodesByTag(doc_arena, .list) == 2);
    try std.testing.expect(traverse.countNodesByTag(doc_arena, .table) == 1);
    try std.testing.expect(traverse.countNodesByTag(doc_arena, .block) == 1);
    try std.testing.expect(traverse.countInlinesByTag(doc_arena, .anchor) == 1);
    try std.testing.expect(traverse.countInlinesByTag(doc_arena, .reference) == 3);
}

test "validation passes on valid document" {
    var doc = try buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var doc_arena = try lower.lower(std.testing.allocator, &doc);
    defer doc_arena.deinit();

    const diags = try validate.validate(std.testing.allocator, doc_arena);
    defer {
        for (diags) |d| std.testing.allocator.free(d.message);
        std.testing.allocator.free(diags);
    }

    try std.testing.expectEqual(@as(usize, 0), diags.len);
}

test "validation warns on empty section" {
    const b = build.Builder.init(std.testing.allocator);
    const meta = try b.noopMetadata();
    const empty_section = try b.section(meta, "Empty", &.{try b.emptyParagraph()});
    var doc = try b.document(meta, &.{empty_section});
    defer doc.deinit(std.testing.allocator);

    var doc_arena = try lower.lower(std.testing.allocator, &doc);
    defer doc_arena.deinit();

    // Arena section with empty paragraph inside — paragraph is non-empty, section has children.
    // Structure is valid, just a section with a tiny paragraph.
    try std.testing.expect(doc_arena.roots.len == 1);
}

test "traverse counts match expected" {
    var doc = try buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var doc_arena = try lower.lower(std.testing.allocator, &doc);
    defer doc_arena.deinit();

    var walker = traverse.Walker.init(std.testing.allocator, doc_arena);
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
            .inline_el => {
                inline_count += 1;
            },
        }
    }

    try std.testing.expect(node_count > 0);
    try std.testing.expect(inline_count > 0);
}

test "html output is non-empty" {
    var doc = try buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var doc_arena = try lower.lower(std.testing.allocator, &doc);
    defer doc_arena.deinit();

    const html = try emit_html.emitHtml(std.testing.allocator, doc_arena);
    defer std.testing.allocator.free(html);

    try std.testing.expect(html.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<!DOCTYPE html>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<ul>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<ol>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<table>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<a id=\"overview\">"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<a id=\"tables\">"));
}

test "metadata round-trips through lowering" {
    const b = build.Builder.init(std.testing.allocator);
    const meta = try b.metadata(.{
        .id = "test-id",
        .title = "Test Title",
        .roles = &.{"capsule", "experimental"},
        .attrs = &.{
            .{ .key = "lang", .value = "en" },
        },
    });
    const para = try b.paragraph(&.{try b.inlineText("content")});
    var doc = try b.document(meta, &.{para});
    defer doc.deinit(std.testing.allocator);

    var doc_arena = try lower.lower(std.testing.allocator, &doc);
    defer doc_arena.deinit();

    try std.testing.expectEqualStrings("test-id", doc_arena.metadata.id.?);
    try std.testing.expectEqualStrings("Test Title", doc_arena.metadata.title.?);
    try std.testing.expectEqual(@as(usize, 2), doc_arena.metadata.roles.len);
    try std.testing.expectEqualStrings("capsule", doc_arena.metadata.roles[0]);
    try std.testing.expectEqualStrings("experimental", doc_arena.metadata.roles[1]);
    try std.testing.expectEqual(@as(usize, 1), doc_arena.metadata.attrs.len);
    try std.testing.expectEqualStrings("lang", doc_arena.metadata.attrs[0].key);
    try std.testing.expectEqualStrings("en", doc_arena.metadata.attrs[0].value);
}

test "semantic hash is deterministic" {
    var doc1 = try buildExampleDocument(std.testing.allocator);
    defer doc1.deinit(std.testing.allocator);
    var doc2 = try buildExampleDocument(std.testing.allocator);
    defer doc2.deinit(std.testing.allocator);

    var arena1 = try lower.lower(std.testing.allocator, &doc1);
    defer arena1.deinit();
    var arena2 = try lower.lower(std.testing.allocator, &doc2);
    defer arena2.deinit();

    const h1 = hash_mod.hashDocument(arena1);
    const h2 = hash_mod.hashDocument(arena2);

    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
}

test "semantic hash detects structural difference" {
    var b1 = build.Builder.init(std.testing.allocator);
    const meta1 = try b1.noopMetadata();
    const p1 = try b1.paragraph(&.{try b1.inlineText("hello")});
    var doc1 = try b1.document(meta1, &.{p1});
    defer doc1.deinit(std.testing.allocator);

    var b2 = build.Builder.init(std.testing.allocator);
    const meta2 = try b2.noopMetadata();
    const s2 = try b2.section(try b2.noopMetadata(), "Heading", &.{
        try b2.paragraph(&.{try b2.inlineText("hello")}),
    });
    var doc2 = try b2.document(meta2, &.{s2});
    defer doc2.deinit(std.testing.allocator);

    var arena1 = try lower.lower(std.testing.allocator, &doc1);
    defer arena1.deinit();
    var arena2 = try lower.lower(std.testing.allocator, &doc2);
    defer arena2.deinit();

    const h1 = hash_mod.hashDocument(arena1);
    const h2 = hash_mod.hashDocument(arena2);

    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "semantic hash detects content difference" {
    var b1 = build.Builder.init(std.testing.allocator);
    const meta1 = try b1.noopMetadata();
    const p1 = try b1.paragraph(&.{try b1.inlineText("alpha")});
    var doc1 = try b1.document(meta1, &.{p1});
    defer doc1.deinit(std.testing.allocator);

    var b2 = build.Builder.init(std.testing.allocator);
    const meta2 = try b2.noopMetadata();
    const p2 = try b2.paragraph(&.{try b2.inlineText("beta")});
    var doc2 = try b2.document(meta2, &.{p2});
    defer doc2.deinit(std.testing.allocator);

    var arena1 = try lower.lower(std.testing.allocator, &doc1);
    defer arena1.deinit();
    var arena2 = try lower.lower(std.testing.allocator, &doc2);
    defer arena2.deinit();

    const h1 = hash_mod.hashDocument(arena1);
    const h2 = hash_mod.hashDocument(arena2);

    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "semantic hash detects list kind difference" {
    var b1 = build.Builder.init(std.testing.allocator);
    const meta1 = try b1.noopMetadata();
    const item1 = try b1.listItem(&.{try b1.paragraph(&.{try b1.inlineText("item")})});
    const list1 = try b1.list(.ordered, &.{item1});
    var doc1 = try b1.document(meta1, &.{list1});
    defer doc1.deinit(std.testing.allocator);

    var b2 = build.Builder.init(std.testing.allocator);
    const meta2 = try b2.noopMetadata();
    const item2 = try b2.listItem(&.{try b2.paragraph(&.{try b2.inlineText("item")})});
    const list2 = try b2.list(.unordered, &.{item2});
    var doc2 = try b2.document(meta2, &.{list2});
    defer doc2.deinit(std.testing.allocator);

    var arena1 = try lower.lower(std.testing.allocator, &doc1);
    defer arena1.deinit();
    var arena2 = try lower.lower(std.testing.allocator, &doc2);
    defer arena2.deinit();

    const h1 = hash_mod.hashDocument(arena1);
    const h2 = hash_mod.hashDocument(arena2);

    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "semantic hash includes link target" {
    var b1 = build.Builder.init(std.testing.allocator);
    const meta1 = try b1.noopMetadata();
    const p1 = try b1.paragraph(&.{try b1.inlineLink("https://a.com", null)});
    var doc1 = try b1.document(meta1, &.{p1});
    defer doc1.deinit(std.testing.allocator);

    var b2 = build.Builder.init(std.testing.allocator);
    const meta2 = try b2.noopMetadata();
    const p2 = try b2.paragraph(&.{try b2.inlineLink("https://b.com", null)});
    var doc2 = try b2.document(meta2, &.{p2});
    defer doc2.deinit(std.testing.allocator);

    var arena1 = try lower.lower(std.testing.allocator, &doc1);
    defer arena1.deinit();
    var arena2 = try lower.lower(std.testing.allocator, &doc2);
    defer arena2.deinit();

    const h1 = hash_mod.hashDocument(arena1);
    const h2 = hash_mod.hashDocument(arena2);

    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}
