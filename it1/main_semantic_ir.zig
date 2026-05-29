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

    const code_text = try builder.text("fn main() {\n    std.debug.print(\"hello\\n\", .{});\n}");
    const code_block = try builder.block(.code_block, &.{code_text}, null);

    const sub_title_text = try builder.text("Going Deeper");
    const sub_heading = try builder.block(.heading, &.{sub_title_text}, null);

    const intro_text = try builder.text("Inline markup like ");
    const emph_text = try builder.text("emphasis");
    const emph = try builder.inlineNode(.emphasis, &.{emph_text});
    const mid_text = try builder.text(" and ");
    const cs_text = try builder.codeSpan("code_span");
    const mid2_text = try builder.text(" is supported, as are ");
    const link_label = try builder.text("external links");
    const link_ref = try builder.inlineNode(.reference, &.{link_label});
    const tail_text = try builder.text(".");
    const detail_para = try builder.block(.paragraph, &.{ intro_text, emph, mid_text, cs_text, mid2_text, link_ref, tail_text }, null);

    const nest_intro_text = try builder.text("Nesting works");
    const nest_intro_para = try builder.block(.paragraph, &.{nest_intro_text}, null);
    const sub_level_text = try builder.text("Level two");
    const sub_level_para = try builder.block(.paragraph, &.{sub_level_text}, null);
    const sub_item = try builder.block(.list_item, &.{sub_level_para}, null);
    const sub_level_two_text = try builder.text("Also level two");
    const sub_level_two_para = try builder.block(.paragraph, &.{sub_level_two_text}, null);
    const sub_item_two = try builder.block(.list_item, &.{sub_level_two_para}, null);
    const sub_list = try builder.block(.list, &.{ sub_item, sub_item_two }, null);
    const nest_item = try builder.block(.list_item, &.{ nest_intro_para, sub_list }, null);
    const flat_intro_text = try builder.text("Flat too");
    const flat_intro_para = try builder.block(.paragraph, &.{flat_intro_text}, null);
    const flat_item = try builder.block(.list_item, &.{flat_intro_para}, null);
    const nested_list = try builder.block(.list, &.{ nest_item, flat_item }, null);

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

    const section_one = try builder.block(.section, &.{
        heading,       paragraph, list, code_block, sub_heading, detail_para, nested_list,
        include_block,
    }, null);

    const ov_text = try builder.text("Iteration 1 Feature Overview");
    const ov_heading = try builder.block(.heading, &.{ov_text}, "it1-overview");

    const ov_see = try builder.text("This IR prototype defines a low-level semantic document graph built on ");
    const ov_strong_text = try builder.text("nodes");
    const ov_strong = try builder.inlineNode(.strong, &.{ov_strong_text});
    const ov_mid1 = try builder.text(" and ");
    const ov_emph_text = try builder.text("edges");
    const ov_emph = try builder.inlineNode(.emphasis, &.{ov_emph_text});
    const ov_mid2 = try builder.text(". See ");
    const ov_xref_label = try builder.text("the introduction");
    const ov_xref = try builder.inlineNode(.reference, &.{ov_xref_label});
    const ov_mid3 = try builder.text(" for context.");
    const ov_para = try builder.block(.paragraph, &.{ ov_see, ov_strong, ov_mid1, ov_emph, ov_mid2, ov_xref, ov_mid3 }, null);

    const blk_text = try builder.text("Block kinds group structural content: document, section, heading, paragraph, list, list_item, quote, code_block, include, footnote_def, bibliography_def.");
    const blk_para = try builder.block(.paragraph, &.{blk_text}, null);
    const blk_item = try builder.block(.list_item, &.{blk_para}, null);
    const inl_text = try builder.text("Inline kinds carry phrasing: text, emphasis, strong, code_span, reference, reference_group. References use outgoing edges to point at targets.");
    const inl_para = try builder.block(.paragraph, &.{inl_text}, null);
    const inl_item = try builder.block(.list_item, &.{inl_para}, null);
    const edg_text = try builder.text("Edge kinds define relationships: link, xref, cite, footnote_ref, include. Targets are either nodes or external URLs.");
    const edg_para = try builder.block(.paragraph, &.{edg_text}, null);
    const edg_item = try builder.block(.list_item, &.{edg_para}, null);
    const xfm_text = try builder.text("Transform passes mutate the graph after validation: flattenIncludes, collectDefinitionsToDocumentEnd, renumberReferences.");
    const xfm_para = try builder.block(.paragraph, &.{xfm_text}, null);
    const xfm_item = try builder.block(.list_item, &.{xfm_para}, null);
    const ov_list = try builder.block(.list, &.{ blk_item, inl_item, edg_item, xfm_item }, null);

    const ov_summary = try builder.text("Emitters (HTML, Markdown) are lossy projections for inspection. The IR is the source of truth.");
    const ov_summary_para = try builder.block(.paragraph, &.{ov_summary}, null);

    const section_two = try builder.block(.section, &.{
        ov_heading, ov_para, ov_list, ov_summary_para,
    }, null);

    const doc_node = try builder.block(.document, &.{ section_one, section_two, footnote_def, bibliography_def, bibliography_def_two }, null);

    try builder.edge(.xref, xref, .{ .node = heading });
    try builder.edge(.footnote_ref, footnote_ref, .{ .node = footnote_def });
    try builder.edge(.cite, cite_ref_one, .{ .node = bibliography_def });
    try builder.edge(.cite, cite_ref_two, .{ .node = bibliography_def_two });
    try builder.edge(.include, include_block, .{ .node = shared_quote });
    try builder.edge(.link, link_ref, .{ .external = "https://example.com" });
    try builder.edge(.xref, ov_xref, .{ .node = heading });
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
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Low level document IR</title><style>\n*{margin:0;padding:0;box-sizing:border-box}\nbody{max-width:70ch;margin:40px auto;padding:0 20px;font:16px/1.6 system-ui,-apple-system,sans-serif;color:#1a1a1a;background:#fafafa}\nh1,h2,h3,h4{line-height:1.3;color:#111;margin-top:1.5em;margin-bottom:.4em}\nh2{border-bottom:1px solid #e0e0e0;padding-bottom:.25em}\np{margin-bottom:.8em}\nul,ol{margin:.6em 0;padding-left:1.5em}\nli{margin:.15em 0}\na{color:#2563eb;text-decoration:none}\na:hover,a:focus{text-decoration:underline}\ncode,pre{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.92em}\npre{padding:14px 16px;overflow-x:auto;background:#f0f0f0;border-radius:8px;line-height:1.45;margin:.8em 0}\ncode{background:#eee;padding:2px 5px;border-radius:4px}\npre code{background:none;padding:0;border-radius:0}\nblockquote{margin:.8em 0;padding-left:1rem;border-left:4px solid #d0d7de;color:#555}\nsection{margin:1.5em 0}\nsection.footnotes{margin-top:3em;padding-top:1em;border-top:2px solid #e0e0e0}\nsection.footnotes ol{padding-left:1.2em}\nsection.footnotes li{margin:.6em 0}\nsection.bibliography{margin-top:1em;padding:.8em 1em;background:#f0f4ff;border-radius:8px;border-left:4px solid #2563eb}\nsection.bibliography div{margin:.3em 0}\nsup{font-size:.75em}\ncite{font-style:normal}\n</style></head><body><section><h2 id=\"intro\">Low level document IR</h2><p>See <a href=\"#intro\">the title above</a>, and note this footnote<sup><a href=\"#fn-1\">1</a></sup>, plus these citations <cite>[<a href=\"#bib-knuth84\">knuth84</a>; <a href=\"#bib-lamport94\">lamport94</a>]</cite>, before the list.</p><ul><li><p>Containment stays tree-shaped.</p></li><li><p>References live in edges.</p></li></ul><pre><code>fn main() {\n    std.debug.print(&quot;hello\\n&quot;, .{});\n}</code></pre><h2>Going Deeper</h2><p>Inline markup like <em>emphasis</em> and <code>code_span</code> is supported, as are <a href=\"https://example.com\">external links</a>.</p><ul><li><p>Nesting works</p><ul><li><p>Level two</p></li><li><p>Also level two</p></li></ul></li><li><p>Flat too</p></li></ul><blockquote><p>A reusable transcluded block can stay outside the main tree and still be projected where needed.</p></blockquote></section><section><h2 id=\"it1-overview\">Iteration 1 Feature Overview</h2><p>This IR prototype defines a low-level semantic document graph built on <strong>nodes</strong> and <em>edges</em>. See <a href=\"#intro\">the introduction</a> for context.</p><ul><li><p>Block kinds group structural content: document, section, heading, paragraph, list, list_item, quote, code_block, include, footnote_def, bibliography_def.</p></li><li><p>Inline kinds carry phrasing: text, emphasis, strong, code_span, reference, reference_group. References use outgoing edges to point at targets.</p></li><li><p>Edge kinds define relationships: link, xref, cite, footnote_ref, include. Targets are either nodes or external URLs.</p></li><li><p>Transform passes mutate the graph after validation: flattenIncludes, collectDefinitionsToDocumentEnd, renumberReferences.</p></li></ul><p>Emitters (HTML, Markdown) are lossy projections for inspection. The IR is the source of truth.</p></section><section class=\"footnotes\"><ol><li id=\"fn-1\"><p>A footnote definition can carry <strong>full block content</strong>, not just plain text.</p></li></ol></section><section class=\"bibliography\"><div id=\"bib-knuth84\"><p>Donald E. Knuth. Literate Programming. 1984.</p></div></section><section class=\"bibliography\"><div id=\"bib-lamport94\"><p>Leslie Lamport. LaTeX: A Document Preparation System. 1994.</p></div></section></body></html>",
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
        "## Low level document IR\n\nSee [the title above](#intro), and note this footnote[^1], plus these citations [@knuth84; @lamport94], before the list.\n\n- Containment stays tree-shaped.\n- References live in edges.\n\n```\nfn main() {\n    std.debug.print(\"hello\\n\", .{});\n}\n```\n\n## Going Deeper\n\nInline markup like *emphasis* and `code_span` is supported, as are [external links](https://example.com).\n\n- Nesting works\n- Level two\n- Also level two\n\n- Flat too\n\n> A reusable transcluded block can stay outside the main tree and still be projected where needed.\n\n\n## Iteration 1 Feature Overview\n\nThis IR prototype defines a low-level semantic document graph built on **nodes** and *edges*. See [the introduction](#intro) for context.\n\n- Block kinds group structural content: document, section, heading, paragraph, list, list_item, quote, code_block, include, footnote_def, bibliography_def.\n- Inline kinds carry phrasing: text, emphasis, strong, code_span, reference, reference_group. References use outgoing edges to point at targets.\n- Edge kinds define relationships: link, xref, cite, footnote_ref, include. Targets are either nodes or external URLs.\n- Transform passes mutate the graph after validation: flattenIncludes, collectDefinitionsToDocumentEnd, renumberReferences.\n\nEmitters (HTML, Markdown) are lossy projections for inspection. The IR is the source of truth.\n\n[^1]: A footnote definition can carry **full block content**, not just plain text.\n\n[@knuth84]: Donald E. Knuth. Literate Programming. 1984.\n\n[@lamport94]: Leslie Lamport. LaTeX: A Document Preparation System. 1994.\n",
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
