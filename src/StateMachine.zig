const Entry = @import("types.zig").Entry;

const StateMachine = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    apply: *const fn (ptr: *anyopaque, entry: Entry) void,
};

pub fn apply(sm: StateMachine, entry: Entry) void {
    sm.vtable.apply(sm.ptr, entry);
}
