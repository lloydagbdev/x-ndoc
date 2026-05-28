const common = @import("semantic_ir_common.zig");

pub const NodeId = common.NodeId;
pub const EdgeId = common.EdgeId;
pub const PayloadId = u32;
pub const NodeKind = common.NodeKind;
pub const EdgeKind = common.EdgeKind;
pub const Alignment = common.Alignment;
pub const TableCellKind = common.TableCellKind;

pub const StringRef = struct {
    start: u32,
    len: u32,
};

pub const NodeRange = struct {
    start: u32,
    len: u32,
};

pub const Root = struct {
    node: NodeId,
};

pub const Document = struct {
    roots: []const Root,
    nodes: []const Node,
    child_ids: []const NodeId,
    edges: []const Edge,
    payloads: []const Payload,
    strings: []const u8,
};

pub const Node = struct {
    kind: Kind,
    children: NodeRange = .{ .start = 0, .len = 0 },
    payload: ?PayloadId = null,

    pub const Kind = NodeKind;

    pub fn isFragment(kind: Kind) bool {
        return kind.isFragment();
    }
};

pub const Payload = union(enum) {
    text: StringRef,
    name: StringRef,
    code_block: CodeBlock,
    table: Table,
    table_cell: TableCell,
};

pub const CodeBlock = struct {
    text: StringRef,
    language: ?StringRef = null,
};

pub const Table = struct {
    columns: []const TableColumn = &.{},
};

pub const TableColumn = struct {
    alignment: Alignment = .none,
};

pub const TableCell = struct {
    kind: Kind = .data,
    colspan: u32 = 1,
    rowspan: u32 = 1,

    pub const Kind = TableCellKind;
};

pub const Edge = struct {
    kind: Kind,
    from: NodeId,
    to: Target,

    pub const Kind = EdgeKind;
};

pub const Target = union(enum) {
    node: NodeId,
    external: StringRef,
};
