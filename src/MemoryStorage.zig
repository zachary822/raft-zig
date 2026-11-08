const std = @import("std");
const types = @import("types.zig");
const Allocator = std.mem.Allocator;
const Entry = types.Entry;
const Index = types.Index;
const Term = types.Term;
const HardState = types.HardState;
const Storage = @import("Storage.zig");

const MemoryStorage = @This();

gpa: Allocator,
hard_state: HardState = .{},
log: std.ArrayList(Entry) = .empty,

pub fn init(gpa: Allocator) MemoryStorage {
    return .{ .gpa = gpa };
}

pub fn deinit(self: *MemoryStorage) void {
    for (self.log.items) |e| self.gpa.free(e.data);
    self.log.deinit(self.gpa);
}

pub fn storage(self: *MemoryStorage) Storage {
    return .{ .ptr = self, .vtable = &vtable };
}

const vtable: Storage.VTable = .{
    .hardState = hardState,
    .setHardState = setHardState,
    .lastIndex = lastIndex,
    .term = term,
    .entries = entries,
    .append = append,
    .truncate = truncate,
};

fn cast(ptr: *anyopaque) *MemoryStorage {
    return @ptrCast(@alignCast(ptr));
}

fn hardState(ptr: *anyopaque) HardState {
    return cast(ptr).hard_state;
}

fn setHardState(ptr: *anyopaque, hs: HardState) Storage.Error!void {
    cast(ptr).hard_state = hs;
}

fn lastIndex(ptr: *anyopaque) Index {
    return cast(ptr).log.items.len;
}

fn term(ptr: *anyopaque, index: Index) ?Term {
    const self = cast(ptr);
    if (index == 0) return 0;
    if (index > self.log.items.len) return null;
    return self.log.items[index - 1].term;
}

pub fn entries(ptr: *anyopaque, lo: Index, hi: Index) Storage.Error![]const Entry {
    const self = cast(ptr);
    std.debug.assert(lo >= 1 and lo <= hi and hi <= self.log.items.len + 1);
    return self.log.items[lo - 1 .. hi - 1];
}

fn append(ptr: *anyopaque, new_entries: []const Entry) Storage.Error!void {
    const self = cast(ptr);
    try self.log.ensureUnusedCapacity(self.gpa, new_entries.len);
    for (new_entries) |e| {
        self.log.appendAssumeCapacity(.{
            .term = e.term,
            .index = e.index,
            .data = try self.gpa.dupe(u8, e.data),
        });
    }
}

fn truncate(ptr: *anyopaque, from: Index) Storage.Error!void {
    const self = cast(ptr);
    std.debug.assert(from >= 1);
    if (from > self.log.items.len) return;
    for (self.log.items[from - 1 ..]) |e| self.gpa.free(e.data);
    self.log.shrinkRetainingCapacity(from - 1);
}

test "an empty log" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    const s = mem.storage();

    try std.testing.expectEqual(0, s.lastIndex());
    try std.testing.expectEqual(0, s.term(0));
    try std.testing.expectEqual(0, s.lastTerm());
    try std.testing.expectEqual(null, s.term(1));
}

test "append and read" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    const s = mem.storage();

    try s.append(&.{
        .{ .term = 1, .index = 1, .data = "x=1" },
        .{ .term = 1, .index = 2, .data = "y=2" },
        .{ .term = 2, .index = 3, .data = "x=3" },
    });
    try std.testing.expectEqual(3, s.lastIndex());
    try std.testing.expectEqual(2, s.lastTerm());
    try std.testing.expectEqual(1, s.term(2));

    const got = try s.entries(2, 4);
    try std.testing.expectEqual(2, got.len);
    try std.testing.expectEqualStrings("y=2", got[0].data);
    try std.testing.expectEqualStrings("x=3", got[1].data);
}

test "truncate removes the conflicting suffix" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    const s = mem.storage();

    try s.append(&.{
        .{ .term = 1, .index = 1, .data = "x=1" },
        .{ .term = 2, .index = 2, .data = "y=2" },
        .{ .term = 2, .index = 3, .data = "x=3" },
    });
    try s.truncate(2);
    try std.testing.expectEqual(1, s.lastIndex());
    try std.testing.expectEqual(null, s.term(2));

    // The log can grow again after a truncate.
    try s.append(&.{.{ .term = 3, .index = 2, .data = "z=9" }});
    try std.testing.expectEqual(3, s.lastTerm());
}

test "hard state" {
    var mem: MemoryStorage = .init(std.testing.allocator);
    defer mem.deinit();
    const s = mem.storage();

    try std.testing.expectEqual(HardState{}, s.hardState());
    try s.setHardState(.{ .current_term = 5, .voted_for = 2 });
    try std.testing.expectEqual(HardState{ .current_term = 5, .voted_for = 2 }, s.hardState());
}
