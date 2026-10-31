//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const MemoryStorage = @import("MemoryStorage.zig");

test {
    _ = MemoryStorage;
}
