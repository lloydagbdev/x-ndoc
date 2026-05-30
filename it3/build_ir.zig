const std = @import("std");
const author = @import("author_ir.zig");

pub const BuildError = std.mem.Allocator.Error || error{
    DuplicateNode,
    EmptyChildren,
    InvalidChildType,
};

pub const Builder = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    fn str(self: *const Self, value: []const u8) BuildError![]const u8 {
        return self.allocator.dupe(u8, value);
    }

    fn optStr(self: *const Self, value: ?[]const u8) BuildError!?[]const u8 {
        if (value) |s| return try self.str(s);
        return null;
    }

    fn allocNodes(self: *const Self, nodes: []const author.Node) BuildError![]author.Node {
        return self.allocator.dupe(author.Node, nodes);
    }

    fn allocInlines(self: *const Self, inlines: []const author.Inline) BuildError![]author.Inline {
        return self.allocator.dupe(author.Inline, inlines);
    }

    fn allocListItems(self: *const Self, items: []const author.ListItem) BuildError![]author.ListItem {
        return self.allocator.dupe(author.ListItem, items);
    }

    fn allocTableRows(self: *const Self, rows: []const author.TableRow) BuildError![]author.TableRow {
        return self.allocator.dupe(author.TableRow, rows);
    }

    fn allocTableCells(self: *const Self, cells: []const author.TableCell) BuildError![]author.TableCell {
        return self.allocator.dupe(author.TableCell, cells);
    }

    fn allocRoles(self: *const Self, roles: []const []const u8) BuildError![]const []const u8 {
        const out = try self.allocator.alloc([]const u8, roles.len);
        for (roles, 0..) |role, i| {
            out[i] = try self.str(role);
        }
        return out;
    }

    fn allocAttrs(self: *const Self, attrs: []const author.KVPair) BuildError![]const author.KVPair {
        const out = try self.allocator.alloc(author.KVPair, attrs.len);
        for (attrs, 0..) |attr, i| {
            out[i] = .{
                .key = try self.str(attr.key),
                .value = try self.str(attr.value),
            };
        }
        return out;
    }

    pub fn metadata(self: *const Self, spec: MetadataSpec) BuildError!author.Metadata {
        return .{
            .id = try self.optStr(spec.id),
            .title = try self.optStr(spec.title),
            .roles = if (spec.roles.len > 0) try self.allocRoles(spec.roles) else &.{},
            .attrs = if (spec.attrs.len > 0) try self.allocAttrs(spec.attrs) else &.{},
        };
    }

    pub fn noopMetadata(self: *const Self) BuildError!author.Metadata {
        _ = self;
        return author.Metadata.noop();
    }

    pub fn document(self: *const Self, meta: author.Metadata, blocks: []const author.Node) BuildError!author.Document {
        return .{
            .metadata = meta,
            .blocks = try self.allocNodes(blocks),
        };
    }

    pub fn section(self: *const Self, meta: author.Metadata, title: ?[]const u8, children: []const author.Node) BuildError!author.Node {
        if (children.len == 0) return error.EmptyChildren;
        for (children) |c| {
            if (!c.isBlock()) return error.InvalidChildType;
        }
        return .{ .section = .{
            .metadata = meta,
            .title = try self.optStr(title),
            .children = try self.allocNodes(children),
        } };
    }

    pub fn paragraph(self: *const Self, content: []const author.Inline) BuildError!author.Node {
        if (content.len == 0) return error.EmptyChildren;
        return .{ .paragraph = .{
            .content = try self.allocInlines(content),
        } };
    }

    pub fn emptyParagraph(self: *const Self) BuildError!author.Node {
        _ = self;
        return .{ .paragraph = .{ .content = &.{} } };
    }

    pub fn list(self: *const Self, kind: author.ListKind, items: []const author.ListItem) BuildError!author.Node {
        if (items.len == 0) return error.EmptyChildren;
        return .{ .list = .{
            .kind = kind,
            .items = try self.allocListItems(items),
        } };
    }

    pub fn listItem(self: *const Self, children: []const author.Node) BuildError!author.ListItem {
        if (children.len == 0) return error.EmptyChildren;
        for (children) |c| {
            if (!c.isBlock()) return error.InvalidChildType;
        }
        return .{ .children = try self.allocNodes(children) };
    }

    pub fn table(self: *const Self, rows: []const author.TableRow) BuildError!author.Node {
        if (rows.len == 0) return error.EmptyChildren;
        return .{ .table = .{
            .rows = try self.allocTableRows(rows),
        } };
    }

    pub fn tableRow(self: *const Self, cells: []const author.TableCell) BuildError!author.TableRow {
        if (cells.len == 0) return error.EmptyChildren;
        return .{ .cells = try self.allocTableCells(cells) };
    }

    pub fn tableCell(self: *const Self, children: []const author.Node) BuildError!author.TableCell {
        if (children.len == 0) return error.EmptyChildren;
        for (children) |c| {
            if (!c.isBlock()) return error.InvalidChildType;
        }
        return .{ .children = try self.allocNodes(children) };
    }

    pub fn genericBlock(self: *const Self, meta: author.Metadata, children: []const author.Node) BuildError!author.Node {
        if (children.len == 0) return error.EmptyChildren;
        for (children) |c| {
            if (!c.isBlock()) return error.InvalidChildType;
        }
        return .{ .block_node = .{
            .metadata = meta,
            .children = try self.allocNodes(children),
        } };
    }

    pub fn diagnostic(self: *const Self, message: []const u8) BuildError!author.Node {
        return .{ .diagnostic = .{
            .message = try self.str(message),
        } };
    }

    pub fn inlineText(self: *const Self, value: []const u8) BuildError!author.Inline {
        return .{ .text = try self.str(value) };
    }

    pub fn inlineLink(self: *const Self, target: []const u8, label: ?[]const u8) BuildError!author.Inline {
        return .{ .link = .{
            .target = try self.str(target),
            .label = try self.optStr(label),
        } };
    }

    pub fn inlineReference(self: *const Self, target: []const u8, label: ?[]const u8) BuildError!author.Inline {
        return .{ .reference = .{
            .target = try self.str(target),
            .label = try self.optStr(label),
        } };
    }

    pub fn inlineAnchor(self: *const Self, name: []const u8) BuildError!author.Inline {
        return .{ .anchor = .{
            .name = try self.str(name),
        } };
    }

    pub fn inlineEmphasis(self: *const Self, content: []const author.Inline) BuildError!author.Inline {
        return .{ .emphasis = try self.allocInlines(content) };
    }

    pub fn inlineStrong(self: *const Self, content: []const author.Inline) BuildError!author.Inline {
        return .{ .strong = try self.allocInlines(content) };
    }
};

pub const MetadataSpec = struct {
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    attrs: []const author.KVPair = &.{},
};
