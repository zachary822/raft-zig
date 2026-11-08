const Message = @import("types.zig").Message;

const Transport = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    send: *const fn (ptr: *anyopaque, msg: Message) void,
};

pub fn send(t: Transport, msg: Message) void {
    t.vtable.send(t.ptr, msg);
}
