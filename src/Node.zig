const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Index = types.Index;
const Message = types.Message;
const NodeId = types.NodeId;
const Term = types.Term;
const Storage = @import("Storage.zig");
const Transport = @import("Transport.zig");
const StateMachine = @import("StateMachine.zig");

const Node = @This();

pub const Role = enum { follower, candidate, leader };

pub const Config = struct {
    id: NodeId,
    peers: []const NodeId,
    election_timeout_min: u32 = 10,
    election_timeout_max: u32 = 20,
    heartbeat_interval: u32 = 2,
    seed: u64 = 0,
};

gpa: Allocator,
config: Config,
storage: Storage,
transport: Transport,
state_machine: StateMachine,
prng: std.Random.DefaultPrng,

role: Role = .follower,
current_term: Term,
voted_for: ?NodeId,
leader_id: ?NodeId = null,

commit_index: Index = 0,
last_applied: Index = 0,

elapsed: u32 = 0,
election_timeout: u32 = 0,

pub fn init(
    gpa: Allocator,
    config: Config,
    storage: Storage,
    transport: Transport,
    state_machine: StateMachine,
) Allocator.Error!Node {
    std.debug.assert(config.election_timeout_min <= config.election_timeout_max);
    std.debug.assert(config.heartbeat_interval < config.election_timeout_min);
    std.debug.assert(std.mem.indexOfScalar(NodeId, config.peers, config.id) != null);

    const hs = storage.hardState();
    var node: Node = .{
        .gpa = gpa,
        .config = config,
        .storage = storage,
        .transport = transport,
        .state_machine = state_machine,
        .prng = .init(config.seed),
        .current_term = hs.current_term,
        .voted_for = hs.voted_for,
    };

    node.config.peers = try gpa.dupe(NodeId, config.peers);
    node.resetElectionTimer();
    return node;
}

pub fn deinit(self: *Node) void {
    self.gpa.free(self.config.peers);
}

pub fn tick(self: *Node) Storage.Error!void {
    self.elapsed += 1;
    // start election if elapse reaches election_timeout
}

/// the number of nodes that make a majority
pub fn quorum(self: *const Node) usize {
    return self.config.peers.len / 2 + 1;
}

fn resetElectionTimer(self: *Node) void {
    self.elapsed = 0;
    self.election_timeout = self.prng.random().intRangeAtMost(
        u32,
        self.config.election_timeout_min,
        self.config.election_timeout_max,
    );
}

pub fn step(self: *Node, msg: Message) Storage.Error!void {
    if (msg.term > self.current_term)
        try self.becomeFollower(msg.term);

    switch (msg.body) {
        .append_entries => {},
        .append_entries_response => {},
        .request_vote => {},
        .request_vote_response => {},
    }
}

fn becomeFollower(self: *Node, term: Term) Storage.Error!void {
    std.debug.assert(term >= self.current_term);
    if (term > self.current_term) {
        self.current_term = term;
        self.voted_for = null;
        self.leader_id = null;
        try self.persistHardState();
    }
    self.role = .follower;
}

fn persistHardState(self: *Node) Storage.Error!void {
    return self.storage.setHardState(.{
        .current_term = self.current_term,
        .voted_for = self.voted_for,
    });
}

// tests

const MemoryStorage = @import("MemoryStorage.zig");

/// A Transport and a StateMachine that do nothing.
const nop = struct {
    fn send(_: *anyopaque, _: Message) void {}
    fn apply(_: *anyopaque, _: types.Entry) void {}
    var dummy: u8 = 0;
    const transport: Transport = .{ .ptr = &dummy, .vtable = &.{ .send = send } };
    const state_machine: StateMachine = .{ .ptr = &dummy, .vtable = &.{ .apply = apply } };
};

fn testNode(mem: *MemoryStorage) !Node {
    return .init(
        std.testing.allocator,
        .{ .id = 1, .peers = &.{ 1, 2, 3 } },
        mem.storage(),
        nop.transport,
        nop.state_machine,
    );
}

/// A heartbeat from node 2, with the given term.
fn heartbeat(term: Term) Message {
    return .{ .from = 2, .to = 1, .term = term, .body = .{ .append_entries = .{
        .prev_log_index = 0,
        .prev_log_term = 0,
        .entries = &.{},
        .leader_commit = 0,
    } } };
}

test "a new node is a follower" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    var node = try testNode(&mem);
    defer node.deinit();

    try std.testing.expectEqual(Role.follower, node.role);
    try std.testing.expectEqual(0, node.current_term);
    try std.testing.expectEqual(2, node.quorum());
    try std.testing.expect(node.election_timeout >= 10 and node.election_timeout <= 20);
}

test "a restarted node loads its term and vote" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    try mem.storage().setHardState(.{ .current_term = 7, .voted_for = 3 });

    var node = try testNode(&mem);
    defer node.deinit();

    try std.testing.expectEqual(7, node.current_term);
    try std.testing.expectEqual(3, node.voted_for);
}

test "a higher term makes a leader step down" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    var node = try testNode(&mem);
    defer node.deinit();
    node.role = .leader;
    node.current_term = 2;
    node.voted_for = 1;

    try node.step(heartbeat(5));

    try std.testing.expectEqual(Role.follower, node.role);
    try std.testing.expectEqual(5, node.current_term);
    try std.testing.expectEqual(null, node.voted_for);
    // The new term is on "disk" too.
    try std.testing.expectEqual(5, mem.hard_state.current_term);
}

test "a lower term changes nothing" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    var node = try testNode(&mem);
    defer node.deinit();
    node.role = .leader;
    node.current_term = 5;

    try node.step(heartbeat(3));

    try std.testing.expectEqual(Role.leader, node.role);
    try std.testing.expectEqual(5, node.current_term);
}
