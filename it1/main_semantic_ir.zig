const std = @import("std");
const semantic_ir = @import("semantic_ir.zig");
const html = @import("semantic_ir_html.zig");
const markdown = @import("semantic_ir_markdown.zig");
const ops = @import("semantic_ir_ops.zig");
const index = @import("semantic_ir_index.zig");

const Document = semantic_ir.Document;
const Builder = semantic_ir.Builder;

const OutputFormat = enum {
    html,
    markdown,
};

fn parseOutputFormat(value: []const u8) !OutputFormat {
    if (std.mem.eql(u8, value, "html")) return .html;
    if (std.mem.eql(u8, value, "markdown") or std.mem.eql(u8, value, "md")) return .markdown;
    return error.UnknownOutputFormat;
}

fn writeUsage() void {
    std.debug.print("usage: main_semantic_ir [html|markdown]\n", .{});
}

fn sampleDoc(allocator: std.mem.Allocator) !Document {
    var builder = Builder.init(allocator);
    errdefer builder.deinit();

    const title_text = try builder.text("Low level document IR");
    const heading = try builder.block(.heading, &.{title_text}, "intro");

    const see_text = try builder.text("See ");
    const xref_label = try builder.text("the title above");
    const xref = try builder.inlineNode(.reference, &.{xref_label});
    const footnote_intro = try builder.text(", and note this footnote");
    const footnote_label = try builder.text("1");
    const footnote_ref = try builder.inlineNode(.reference, &.{footnote_label});
    const cite_intro = try builder.text(", plus these citations ");
    const cite_label_one = try builder.text("knuth84");
    const cite_ref_one = try builder.inlineNode(.reference, &.{cite_label_one});
    const cite_label_two = try builder.text("lamport94");
    const cite_ref_two = try builder.inlineNode(.reference, &.{cite_label_two});
    const cite_group = try builder.inlineNode(.reference_group, &.{ cite_ref_one, cite_ref_two });
    const para_tail = try builder.text(", before the list.");
    const paragraph = try builder.block(.paragraph, &.{ see_text, xref, footnote_intro, footnote_ref, cite_intro, cite_group, para_tail }, null);

    const item_one_text = try builder.text("Containment stays tree-shaped.");
    const item_one_para = try builder.block(.paragraph, &.{item_one_text}, null);
    const item_one = try builder.block(.list_item, &.{item_one_para}, null);

    const item_two_text = try builder.text("References live in edges.");
    const item_two_para = try builder.block(.paragraph, &.{item_two_text}, null);
    const item_two = try builder.block(.list_item, &.{item_two_para}, null);
    const list = try builder.block(.list, &.{ item_one, item_two }, null);

    const shared_quote_text = try builder.text("A reusable transcluded block can stay outside the main tree and still be projected where needed.");
    const shared_quote_para = try builder.block(.paragraph, &.{shared_quote_text}, null);
    const shared_quote = try builder.block(.quote, &.{shared_quote_para}, "shared-quote");
    const include_block = try builder.block(.include, &.{}, null);

    const note_intro = try builder.text("A footnote definition can carry ");
    const note_strong_text = try builder.text("full block content");
    const note_strong = try builder.inlineNode(.strong, &.{note_strong_text});
    const note_tail = try builder.text(", not just plain text.");
    const note_para = try builder.block(.paragraph, &.{ note_intro, note_strong, note_tail }, null);
    const footnote_def = try builder.block(.footnote_def, &.{note_para}, "fn-1");

    const bib_text = try builder.text("Donald E. Knuth. Literate Programming. 1984.");
    const bib_para = try builder.block(.paragraph, &.{bib_text}, null);
    const bibliography_def = try builder.block(.bibliography_def, &.{bib_para}, "bib-knuth84");
    const bib_text_two = try builder.text("Leslie Lamport. LaTeX: A Document Preparation System. 1994.");
    const bib_para_two = try builder.block(.paragraph, &.{bib_text_two}, null);
    const bibliography_def_two = try builder.block(.bibliography_def, &.{bib_para_two}, "bib-lamport94");

    const section = try builder.block(.section, &.{ heading, paragraph, list, include_block, footnote_def, bibliography_def, bibliography_def_two }, null);
    const doc_node = try builder.block(.document, &.{section}, null);

    try builder.edge(.xref, xref, .{ .node = heading });
    try builder.edge(.footnote_ref, footnote_ref, .{ .node = footnote_def });
    try builder.edge(.cite, cite_ref_one, .{ .node = bibliography_def });
    try builder.edge(.cite, cite_ref_two, .{ .node = bibliography_def_two });
    try builder.edge(.include, include_block, .{ .node = shared_quote });
    try builder.addRoot(doc_node);

    return try builder.finish();
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const format = if (args.len >= 2) blk: {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            writeUsage();
            return;
        }
        break :blk parseOutputFormat(args[1]) catch {
            writeUsage();
            return error.UnknownOutputFormat;
        };
    } else .html;

    const doc = try sampleDoc(init.arena.allocator());

    var output: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer output.deinit();

    switch (format) {
        .html => try html.emit(&output.writer, doc),
        .markdown => try markdown.emit(&output.writer, doc),
    }

    try std.Io.File.stdout().writeStreamingAll(init.io, output.written());
}

test "parse output format accepts html and markdown" {
    try std.testing.expectEqual(OutputFormat.html, try parseOutputFormat("html"));
    try std.testing.expectEqual(OutputFormat.markdown, try parseOutputFormat("markdown"));
    try std.testing.expectEqual(OutputFormat.markdown, try parseOutputFormat("md"));
    try std.testing.expectError(error.UnknownOutputFormat, parseOutputFormat("pdf"));
}

test "html emission gives immediate readable output" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const doc = try sampleDoc(std.testing.allocator);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    try html.emit(&output.writer, doc);

    try std.testing.expectEqualStrings(
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Low level document IR</title><style>body{max-width:70ch;margin:40px auto;padding:0 16px;font:16px/1.5 system-ui,sans-serif;}h1,h2,h3,h4,h5,h6{line-height:1.2;}code,pre{font-family:ui-monospace,SFMono-Regular,monospace;}pre{padding:12px;overflow:auto;background:#f6f8fa;border-radius:6px;}a{text-decoration:none;}a:hover{text-decoration:underline;}blockquote{margin:0;padding-left:1rem;border-left:3px solid #d0d7de;color:#57606a;}.footnotes{margin-top:32px;padding-top:16px;border-top:1px solid #d0d7de;}.footnotes ol{padding-left:20px;}</style></head><body><section><h2 id=\"intro\">Low level document IR</h2><p>See <a href=\"#intro\">the title above</a>, and note this footnote<sup><a href=\"#fn-1\">1</a></sup>, plus these citations <cite>[<a href=\"#bib-knuth84\">knuth84</a>; <a href=\"#bib-lamport94\">lamport94</a>]</cite>, before the list.</p><ul><li><p>Containment stays tree-shaped.</p></li><li><p>References live in edges.</p></li></ul><blockquote><p>A reusable transcluded block can stay outside the main tree and still be projected where needed.</p></blockquote><section class=\"footnotes\"><ol><li id=\"fn-1\"><p>A footnote definition can carry <strong>full block content</strong>, not just plain text.</p></li></ol></section><section class=\"bibliography\"><div id=\"bib-knuth84\"><p>Donald E. Knuth. Literate Programming. 1984.</p></div></section><section class=\"bibliography\"><div id=\"bib-lamport94\"><p>Leslie Lamport. LaTeX: A Document Preparation System. 1994.</p></div></section></section></body></html>",
        output.written(),
    );
}

test "markdown emission gives immediate readable output" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const doc = try sampleDoc(std.testing.allocator);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    try markdown.emit(&output.writer, doc);

    try std.testing.expectEqualStrings(
        "## Low level document IR\n\nSee [the title above](#intro), and note this footnote[^1], plus these citations [@knuth84; @lamport94], before the list.\n\n- Containment stays tree-shaped.\n- References live in edges.\n\n> A reusable transcluded block can stay outside the main tree and still be projected where needed.\n\n\n[^1]: A footnote definition can carry **full block content**, not just plain text.\n\n[@knuth84]: Donald E. Knuth. Literate Programming. 1984.\n\n[@lamport94]: Leslie Lamport. LaTeX: A Document Preparation System. 1994.\n",
        output.written(),
    );
}

test "flatten includes preserves markdown output" {
    var output_a: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output_a.deinit();
    var output_b: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output_b.deinit();

    const doc = try sampleDoc(std.testing.allocator);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    const flat = try ops.flattenIncludes(std.testing.allocator, doc);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, flat);

    try markdown.emit(&output_a.writer, doc);
    try markdown.emit(&output_b.writer, flat);

    try std.testing.expectEqualStrings(output_a.written(), output_b.written());
}

test "sample doc index exposes names and definitions" {
    const doc = try sampleDoc(std.testing.allocator);
    defer semantic_ir.owned.deinitDocument(std.testing.allocator, doc);

    var doc_index = try index.build(std.testing.allocator, doc);
    defer doc_index.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?semantic_ir.NodeId, @intCast(semantic_ir.lookupNodeByName(doc, "intro").?)), doc_index.lookup("intro"));
    try std.testing.expectEqual(@as(?semantic_ir.NodeId, @intCast(semantic_ir.lookupNodeByName(doc, "fn-1").?)), doc_index.lookup("fn-1"));
    try std.testing.expectEqual(@as(?semantic_ir.NodeId, @intCast(semantic_ir.lookupNodeByName(doc, "bib-knuth84").?)), doc_index.lookup("bib-knuth84"));
    try std.testing.expectEqual(@as(usize, 1), doc_index.footnotes.len);
    try std.testing.expectEqual(@as(usize, 2), doc_index.bibliography.len);
    try std.testing.expectEqual(@as(usize, 1), doc_index.includes.len);
}
