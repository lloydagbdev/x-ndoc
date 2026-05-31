const std = @import("std");

pub const KVPair = struct {
    key: []const u8,
    value: []const u8,
};

pub const Metadata = struct {
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    attrs: []const KVPair = &.{},

    pub fn noop() Metadata {
        return .{};
    }

    pub fn free(self: *Metadata, allocator: std.mem.Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.title) |t| allocator.free(t);
        for (self.roles) |r| allocator.free(r);
        allocator.free(self.roles);
        for (self.attrs) |a| {
            allocator.free(a.key);
            allocator.free(a.value);
        }
        allocator.free(self.attrs);
        self.* = .{};
    }
};

pub const ListKind = enum {
    ordered,
    unordered,
    task,
    description,
};

pub const Link = struct {
    target: []const u8,
    label: ?[]const u8 = null,

    pub fn free(self: *Link, allocator: std.mem.Allocator) void {
        allocator.free(self.target);
        if (self.label) |l| allocator.free(l);
        self.* = undefined;
    }
};

pub const Reference = struct {
    target: []const u8,
    label: ?[]const u8 = null,

    pub fn free(self: *Reference, allocator: std.mem.Allocator) void {
        allocator.free(self.target);
        if (self.label) |l| allocator.free(l);
        self.* = undefined;
    }
};

pub const Anchor = struct {
    name: []const u8,

    pub fn free(self: *Anchor, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const Diagnostic = struct {
    message: []const u8,

    pub fn free(self: *Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        self.* = undefined;
    }
};

pub const Inline = union(enum) {
    text: []const u8,
    link: Link,
    reference: Reference,
    anchor: Anchor,
    emphasis: []Inline,
    strong: []Inline,

    pub fn free(self: *Inline, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text => |s| allocator.free(s),
            .link => |*l| l.free(allocator),
            .reference => |*r| r.free(allocator),
            .anchor => |*a| a.free(allocator),
            .emphasis => |content| {
                for (content) |*c| c.free(allocator);
                allocator.free(content);
            },
            .strong => |content| {
                for (content) |*c| c.free(allocator);
                allocator.free(content);
            },
        }
        self.* = undefined;
    }
};

pub const Section = struct {
    metadata: Metadata,
    title: ?[]const u8,
    children: []Node,

    pub fn free(self: *Section, allocator: std.mem.Allocator) void {
        self.metadata.free(allocator);
        if (self.title) |t| allocator.free(t);
        for (self.children) |*c| c.free(allocator);
        allocator.free(self.children);
        self.* = undefined;
    }
};

pub const Paragraph = struct {
    content: []Inline,

    pub fn free(self: *Paragraph, allocator: std.mem.Allocator) void {
        for (self.content) |*c| c.free(allocator);
        allocator.free(self.content);
        self.* = undefined;
    }
};

pub const ListItem = struct {
    children: []Node,

    pub fn free(self: *ListItem, allocator: std.mem.Allocator) void {
        for (self.children) |*c| c.free(allocator);
        allocator.free(self.children);
        self.* = undefined;
    }
};

pub const List = struct {
    kind: ListKind,
    items: []ListItem,

    pub fn free(self: *List, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.free(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const TableRow = struct {
    cells: []TableCell,

    pub fn free(self: *TableRow, allocator: std.mem.Allocator) void {
        for (self.cells) |*c| c.free(allocator);
        allocator.free(self.cells);
        self.* = undefined;
    }
};

pub const TableCell = struct {
    children: []Node,

    pub fn free(self: *TableCell, allocator: std.mem.Allocator) void {
        for (self.children) |*c| c.free(allocator);
        allocator.free(self.children);
        self.* = undefined;
    }
};

pub const Table = struct {
    rows: []TableRow,

    pub fn free(self: *Table, allocator: std.mem.Allocator) void {
        for (self.rows) |*r| r.free(allocator);
        allocator.free(self.rows);
        self.* = undefined;
    }
};

pub const Block = struct {
    metadata: Metadata,
    children: []Node,

    pub fn free(self: *Block, allocator: std.mem.Allocator) void {
        self.metadata.free(allocator);
        for (self.children) |*c| c.free(allocator);
        allocator.free(self.children);
        self.* = undefined;
    }
};

pub const Node = union(enum) {
    section: Section,
    paragraph: Paragraph,
    list: List,
    table: Table,
    block_node: Block,
    inline_node: Inline,
    diagnostic: Diagnostic,

    pub fn free(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .section => |*s| s.free(allocator),
            .paragraph => |*p| p.free(allocator),
            .list => |*l| l.free(allocator),
            .table => |*t| t.free(allocator),
            .block_node => |*b| b.free(allocator),
            .inline_node => |*i| i.free(allocator),
            .diagnostic => |*d| d.free(allocator),
        }
    }

    pub fn isBlock(self: Node) bool {
        return switch (self) {
            .section, .paragraph, .list, .table, .block_node => true,
            .inline_node, .diagnostic => false,
        };
    }

    pub fn isInline(self: Node) bool {
        return switch (self) {
            .inline_node => true,
            else => false,
        };
    }
};

pub const Document = struct {
    metadata: Metadata,
    blocks: []Node,

    pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        self.metadata.free(allocator);
        for (self.blocks) |*b| b.free(allocator);
        allocator.free(self.blocks);
        self.* = undefined;
    }
};
