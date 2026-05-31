const std = @import("std");
const build = @import("build_ir.zig");
const core = @import("core_ir.zig");
const lower = @import("lower.zig");
const validate_mod = @import("validate.zig");
const traverse = @import("traverse.zig");
const emit_html = @import("emit_html.zig");
const hash_mod = @import("hash.zig");
const api = @import("api.zig");
const serialize_mod = @import("serialize.zig");
const privacy_mod = @import("privacy.zig");
const transform_mod = @import("transform.zig");
const smoke = @import("smoke_support.zig");

pub fn main() !void {
    return @import("smoke_main.zig").main();
}

test "lowering preserves direct child topology" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try lower.lower(std.testing.allocator, &doc);
    defer core_doc.deinit();

    try std.testing.expectEqual(@as(usize, 4), core_doc.roots.len);

    const features = core_doc.sections[1];
    try std.testing.expectEqual(@as(u32, 1), features.child_count);
    const features_list_idx = core.nodeChildren(core_doc, features.first_child_ref.?, features.child_count)[0];
    try std.testing.expectEqual(core.NodeTag.list, core_doc.nodes[features_list_idx].tag);

    const list_data = core_doc.lists[core_doc.nodes[features_list_idx].index];
    try std.testing.expectEqual(@as(u32, 2), list_data.child_count);

    const second_item_idx = core.nodeChildren(core_doc, list_data.first_child_ref.?, list_data.child_count)[1];
    const second_item = core_doc.list_items[core_doc.nodes[second_item_idx].index];
    try std.testing.expectEqual(@as(u32, 2), second_item.child_count);
}

test "walker visits exact counts" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try lower.lower(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var walker = traverse.Walker.init(std.testing.allocator, core_doc);
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

    try std.testing.expectEqual(core_doc.nodes.len, node_count);
    try std.testing.expectEqual(core_doc.inlines.len, inline_count);
}

test "html does not duplicate nested content" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try lower.lower(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const html = try emit_html.emitHtml(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<em>it4 core</em>"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, html, 1, "it4 core<em>it4 core</em>"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, html, "Nested item one"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, html, "GET /users"));
}

test "validation passes on smoke document" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try lower.lower(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const diags = try validate_mod.validate(std.testing.allocator, core_doc);
    defer {
        for (diags) |d| std.testing.allocator.free(d.message);
        std.testing.allocator.free(diags);
    }

    try std.testing.expectEqual(@as(usize, 0), diags.len);
}

test "semantic hash is deterministic" {
    var doc1 = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc1.deinit(std.testing.allocator);
    var doc2 = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc2.deinit(std.testing.allocator);

    var core1 = try lower.lower(std.testing.allocator, &doc1);
    defer core1.deinit();
    var core2 = try lower.lower(std.testing.allocator, &doc2);
    defer core2.deinit();

    const h1 = hash_mod.hashDocument(core1);
    const h2 = hash_mod.hashDocument(core2);
    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
}

test "validation reports duplicate identifiers" {
    var b = build.Builder.init(std.testing.allocator);
    const doc_meta = try b.metadata(.{ .title = "dup test" });
    const sec1 = try b.section(try b.metadata(.{ .id = "same" }), "One", &.{try b.paragraph(&.{try b.inlineText("a")})});
    const sec2 = try b.section(try b.metadata(.{ .id = "same" }), "Two", &.{try b.paragraph(&.{try b.inlineText("b")})});
    var doc = try b.document(doc_meta, &.{ sec1, sec2 });
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const diags = try api.validateDocument(std.testing.allocator, core_doc);
    defer {
        for (diags) |d| std.testing.allocator.free(d.message);
        std.testing.allocator.free(diags);
    }

    try std.testing.expect(diags.len >= 1);
    try std.testing.expect(std.mem.containsAtLeast(u8, diags[0].message, 1, "Duplicate section id"));
}

test "validation reports unresolved reference" {
    var b = build.Builder.init(std.testing.allocator);
    const doc_meta = try b.metadata(.{ .title = "ref test" });
    const sec = try b.section(try b.metadata(.{ .id = "overview" }), "Overview", &.{try b.paragraph(&.{
        try b.inlineText("See "),
        try b.inlineReference("missing", "Missing"),
    })});
    var doc = try b.document(doc_meta, &.{sec});
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const diags = try api.validateDocument(std.testing.allocator, core_doc);
    defer {
        for (diags) |d| std.testing.allocator.free(d.message);
        std.testing.allocator.free(diags);
    }

    try std.testing.expect(diags.len >= 1);

    var found = false;
    for (diags) |d| {
        if (std.mem.containsAtLeast(u8, d.message, 1, "Unresolved reference 'missing'")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "serialize round-trip preserves hash and html" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const before_hash = api.hashDocument(core_doc);
    const before_html = try api.emitHtml(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(before_html);

    const bytes = try api.serializeDocument(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(bytes);

    const report = try api.validateSerialized(bytes);
    try std.testing.expectEqual(core_doc.nodes.len, report.node_count);
    try std.testing.expectEqual(core_doc.inlines.len, report.inline_count);

    var rt_doc = try api.deserializeDocument(std.testing.allocator, bytes);

    const after_hash = api.hashDocument(rt_doc);
    const after_html = try api.emitHtml(std.testing.allocator, rt_doc);
    defer std.testing.allocator.free(after_html);

    try std.testing.expect(std.mem.eql(u8, &before_hash, &after_hash));
    try std.testing.expectEqualStrings(before_html, after_html);

    rt_doc.deinit();
}

test "privacy scan finds urls and references" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var scan = try api.scanDocumentPrivacy(core_doc, std.testing.allocator);
    defer scan.deinit();

    try std.testing.expect(scan.findings.len >= 1);

    var found_url = false;
    for (scan.findings) |finding| {
        if (finding.kind == .url and std.mem.eql(u8, finding.text, "https://example.com")) {
            found_url = true;
            break;
        }
    }
    try std.testing.expect(found_url);
}

test "privacy public policy redacts email and api key" {
    var findings = try std.testing.allocator.alloc(privacy_mod.Finding, 2);
    defer std.testing.allocator.free(findings);
    findings[0] = .{ .kind = .email, .location = .{ .text_inline = 0 }, .offset = 0, .length = 7, .text = "a@b.com" };
    findings[1] = .{ .kind = .api_key, .location = .{ .text_inline = 1 }, .offset = 0, .length = 4, .text = "sk-x" };

    const entries = try api.applyPrivacyPolicy(findings, privacy_mod.publicPolicy, std.testing.allocator);
    defer std.testing.allocator.free(entries);

    try std.testing.expectEqual(@as(usize, 2), entries.len);
}

test "serialized validate rejects duplicate identifiers semantically" {
    var b = build.Builder.init(std.testing.allocator);
    const meta = try b.metadata(.{ .title = "dup" });
    const sec1 = try b.section(try b.metadata(.{ .id = "same" }), "One", &.{try b.paragraph(&.{try b.inlineText("a")})});
    const sec2 = try b.section(try b.metadata(.{ .id = "same" }), "Two", &.{try b.paragraph(&.{try b.inlineText("b")})});
    var doc = try b.document(meta, &.{ sec1, sec2 });
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const bytes = try api.serializeDocument(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectError(error.SemanticInvalid, api.validateSerialized(bytes));
}

test "serialized validate rejects unresolved references semantically" {
    var b = build.Builder.init(std.testing.allocator);
    const meta = try b.metadata(.{ .title = "ref" });
    const sec = try b.section(try b.metadata(.{ .id = "overview" }), "Overview", &.{try b.paragraph(&.{try b.inlineReference("missing", "Missing")})});
    var doc = try b.document(meta, &.{sec});
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const bytes = try api.serializeDocument(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectError(error.SemanticInvalid, api.validateSerialized(bytes));
}

test "transform rename identifier updates references" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var renamed = try transform_mod.renameIdentifier(std.testing.allocator, core_doc, "overview", "summary");
    defer renamed.deinit();

    try std.testing.expect(std.mem.eql(u8, renamed.sections[0].metadata.id.?, "summary"));

    var found = false;
    for (renamed.references) |reference| {
        if (std.mem.eql(u8, reference.target, "summary")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "transform retitle section updates emitted html" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var retitled = try transform_mod.retitleSection(std.testing.allocator, core_doc, "overview", "Summary");
    defer retitled.deinit();

    const html = try api.emitHtml(std.testing.allocator, retitled);
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Summary</h1>"));
}

test "transform replace text updates emitted html" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.replaceCoreText(std.testing.allocator, core_doc, "Nested item one", "Nested alpha");
    defer changed.deinit();

    const html = try api.emitHtml(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Nested alpha"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, html, 1, "Nested item one"));
}

test "transform update link target preserves label" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.updateCoreLinkTarget(std.testing.allocator, core_doc, "https://example.com", "https://example.org/docs");
    defer changed.deinit();

    try std.testing.expect(std.mem.eql(u8, changed.links[0].target, "https://example.org/docs"));

    const html = try api.emitHtml(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "href=\"https://example.org/docs\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, ">link</a>"));
}

test "transform retarget reference can make document invalid" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.retargetCoreReference(std.testing.allocator, core_doc, "overview", "missing-target");
    defer changed.deinit();

    const diags = try api.validateDocument(std.testing.allocator, changed);
    defer {
        for (diags) |d| std.testing.allocator.free(d.message);
        std.testing.allocator.free(diags);
    }

    var found = false;
    for (diags) |d| {
        if (std.mem.containsAtLeast(u8, d.message, 1, "Unresolved reference 'missing-target'")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "transform add root section appends new root" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.rewrite.addRootSection(std.testing.allocator, core_doc, .{
        .id = "appendix",
        .title = "Appendix",
        .text = "Extra notes",
    });
    defer changed.deinit();

    try std.testing.expectEqual(core_doc.roots.len + 1, changed.roots.len);

    const html = try api.emit.html(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Appendix</h1>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Extra notes"));
}

test "transform remove root section by id prunes emitted output" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.rewrite.removeRootSectionById(std.testing.allocator, core_doc, "tables");
    defer changed.deinit();

    try std.testing.expectEqual(core_doc.roots.len - 1, changed.roots.len);

    const html = try api.emit.html(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);
    try std.testing.expect(!std.mem.containsAtLeast(u8, html, 1, "<h1>Tables</h1>"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, html, 1, "<table>"));
}

test "transform reorder roots changes document order" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.rewrite.reorderRoots(std.testing.allocator, core_doc, &.{ 2, 0, 1, 3 });
    defer changed.deinit();

    const html = try api.emit.html(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);

    const idx_tables = std.mem.indexOf(u8, html, "<h1>Tables</h1>").?;
    const idx_overview = std.mem.indexOf(u8, html, "<h1>Overview</h1>").?;
    try std.testing.expect(idx_tables < idx_overview);
}

test "transform insert root section at position changes order" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.insertRootCoreSectionAt(std.testing.allocator, core_doc, 1, .{
        .id = "between",
        .title = "Between",
        .text = "Inserted root",
    });
    defer changed.deinit();

    const html = try api.emit.html(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);
    const idx_between = std.mem.indexOf(u8, html, "<h1>Between</h1>").?;
    const idx_features = std.mem.indexOf(u8, html, "<h1>Features</h1>").?;
    try std.testing.expect(idx_between < idx_features);
}

test "golden html smoke output matches expected" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const html = try api.emit.html(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);

    try std.testing.expectEqualStrings(
        "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>Iteration 4 Smoke Test</title>\n</head>\n<body>\n<h1>Overview</h1>\n<a id=\"overview\"></a>\n<p>This document exercises the <em>it4 core</em> runtime.</p>\n<h1>Features</h1>\n<a id=\"features\"></a>\n<ul>\n<li><p>First item with <strong>strong emphasis</strong></p>\n</li>\n<li><p>Second item with a <a href=\"https://example.com\">link</a></p>\n<ol>\n<li><p>Nested item one</p>\n</li>\n<li><p>Nested item two</p>\n</li>\n</ol>\n</li>\n</ul>\n<h1>Tables</h1>\n<a id=\"tables\"></a>\n<p><a id=\"tables-anchor\"></a></p>\n<table>\n<tr><td><p>API</p>\n</td><td><p>Version</p>\n</td></tr>\n<tr><td><p>GET /users</p>\n</td><td><p>2.1.0</p>\n</td></tr>\n</table>\n<div><p>See <a href=\"#overview\">Overview</a> and <a href=\"#features\">Features</a></p>\n</div>\n</body>\n</html>\n",
        html,
    );
}

test "golden serialization smoke digest is stable" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    const bytes = try api.binary.serialize(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 1544), bytes.len);

    var digest: [std.crypto.hash.Blake3.digest_length]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(bytes);
    hasher.final(&digest);

    const hex = try smoke.hexLower(std.testing.allocator, &digest);
    defer std.testing.allocator.free(hex);
    try std.testing.expectEqualStrings("36a86ee53b7af642361718c96bb74595a19109582b7e3bc8a6d7a53347456bea", hex);
}

test "transform remove section by id prunes nested subtree" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.rewrite.removeSectionById(std.testing.allocator, core_doc, "features");
    defer changed.deinit();

    const html = try api.emit.html(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);
    try std.testing.expect(!std.mem.containsAtLeast(u8, html, 1, "<h1>Features</h1>"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, html, 1, "Nested item one"));
}

test "transform append child section adds nested section" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.rewrite.appendChildSection(std.testing.allocator, core_doc, .{
        .parent_id = "overview",
        .id = "overview-child",
        .title = "Overview Child",
        .text = "Nested overview notes",
    });
    defer changed.deinit();

    var found_title = false;
    for (changed.sections) |section| {
        if (section.title != null and std.mem.eql(u8, section.title.?, "Overview Child")) {
            found_title = true;
            break;
        }
    }
    try std.testing.expect(found_title);

    const html = try api.emit.html(std.testing.allocator, changed);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Nested overview notes"));
}

test "transform insert child section at beginning precedes existing content" {
    var doc = try smoke.buildExampleDocument(std.testing.allocator);
    defer doc.deinit(std.testing.allocator);

    var core_doc = try api.lowerDocument(std.testing.allocator, &doc);
    defer core_doc.deinit();

    var changed = try api.insertCoreChildSectionAt(std.testing.allocator, core_doc, .{
        .parent_id = "overview",
        .id = "overview-first",
        .title = "First Child",
        .text = "Leading child",
        .position = 0,
    });
    defer changed.deinit();

    var overview: ?core.SectionData = null;
    for (changed.sections) |section| {
        if (section.metadata.id != null and std.mem.eql(u8, section.metadata.id.?, "overview")) {
            overview = section;
            break;
        }
    }
    try std.testing.expect(overview != null);

    const first_child_idx = core.nodeChildren(changed, overview.?.first_child_ref.?, overview.?.child_count)[0];
    try std.testing.expectEqual(core.NodeTag.section, changed.nodes[first_child_idx].tag);

    const first_child = changed.sections[changed.nodes[first_child_idx].index];
    try std.testing.expectEqualStrings("First Child", first_child.title.?);
}

test "adapter lowers parsed document into core" {
    const parsed = api.ParsedDocument{
        .metadata = .{ .title = "Parsed Doc" },
        .blocks = &.{
            .{ .section = .{
                .metadata = .{ .id = "intro" },
                .title = "Intro",
                .children = &.{
                    .{ .paragraph = &.{
                        .{ .text = "Parsed content" },
                        .{ .reference = .{ .target = "intro", .label = "self" } },
                    } },
                },
            } },
        },
    };

    var core_doc = try api.ingest.lowerParsedDocument(std.testing.allocator, parsed);
    defer core_doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), core_doc.roots.len);
    try std.testing.expectEqual(@as(usize, 1), core_doc.sections.len);

    const html = try api.emit.html(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Intro</h1>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Parsed content"));
}

test "event stream lowers into core" {
    const events = &[_]api.Event{
        .{ .begin_section = .{ .id = "intro", .title = "Intro" } },
        .{ .begin_paragraph = {} },
        .{ .text = "Event content" },
        .{ .reference = .{ .target = "intro", .label = "jump" } },
        .{ .end_paragraph = {} },
        .{ .end_section = {} },
    };

    var core_doc = try api.lowerEventStream(std.testing.allocator, .{ .title = "Event Doc" }, events);
    defer core_doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), core_doc.sections.len);
    const html = try api.emit.html(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Intro</h1>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Event content"));
}

test "event stream supports lists tables and inline nesting" {
    const events = &[_]api.Event{
        .{ .begin_section = .{ .id = "mixed", .title = "Mixed" } },
        .{ .begin_paragraph = {} },
        .{ .begin_strong = {} },
        .{ .text = "Strong" },
        .{ .end_strong = {} },
        .{ .text = " and " },
        .{ .begin_emphasis = {} },
        .{ .text = "emph" },
        .{ .end_emphasis = {} },
        .{ .end_paragraph = {} },
        .{ .begin_list = .unordered },
        .{ .begin_list_item = {} },
        .{ .begin_paragraph = {} },
        .{ .text = "Item one" },
        .{ .end_paragraph = {} },
        .{ .end_list_item = {} },
        .{ .end_list = {} },
        .{ .begin_table = {} },
        .{ .begin_table_row = {} },
        .{ .begin_table_cell = {} },
        .{ .begin_paragraph = {} },
        .{ .text = "A1" },
        .{ .end_paragraph = {} },
        .{ .end_table_cell = {} },
        .{ .begin_table_cell = {} },
        .{ .begin_paragraph = {} },
        .{ .text = "B1" },
        .{ .end_paragraph = {} },
        .{ .end_table_cell = {} },
        .{ .end_table_row = {} },
        .{ .end_table = {} },
        .{ .end_section = {} },
    };

    var core_doc = try api.lowerEventStream(std.testing.allocator, .{ .title = "Rich Events" }, events);
    defer core_doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), core_doc.lists.len);
    try std.testing.expectEqual(@as(usize, 1), core_doc.tables.len);

    const html = try api.emit.html(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<strong>Strong</strong>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<em>emph</em>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<ul>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<table>"));
}

test "mini markdown parser targets ingest pipeline" {
    const source =
        "= Mini Doc\n" ++
        "# Overview\n" ++
        "Hello **strong** and *soft* text with [link](https://example.com).\n\n" ++
        "- First item\n" ++
        "- Second item\n\n" ++
        "| A | B |\n" ++
        "| 1 | 2 |\n";

    var core_doc = try api.parseMiniMarkdown(std.testing.allocator, source);
    defer core_doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), core_doc.sections.len);
    try std.testing.expectEqual(@as(usize, 1), core_doc.lists.len);
    try std.testing.expectEqual(@as(usize, 1), core_doc.tables.len);

    const html = try api.emit.html(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<strong>strong</strong>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<em>soft</em>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "href=\"https://example.com\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<table>"));
}

test "mini markdown parser supports nested lists" {
    const source =
        "= Nested Lists\n" ++
        "# Items\n" ++
        "- Top\n" ++
        "  - Child one\n" ++
        "  - Child two\n" ++
        "- Bottom\n";

    var core_doc = try api.parseMiniMarkdown(std.testing.allocator, source);
    defer core_doc.deinit();

    try std.testing.expectEqual(@as(usize, 2), core_doc.lists.len);

    const html = try api.emit.html(std.testing.allocator, core_doc);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Child one"));
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 2, "<ul>"));
}
