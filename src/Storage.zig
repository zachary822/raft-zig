const types = @import("types.zig");
const Entry = types.Entry;
const Index = types.Index;
const Term = types.Term;
const HardState = types.HardState;

const Storage = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const Error = error{ OutOfMemory, StorageFailure };

pub const VTable = struct {
    hardState: *const fn (ptr: *anyopaque) HardState,
    /// the new hard state must be durable before function returns
    setHardState: *const fn (ptr: *anyopaque, hs: HardState) Error!void,
    /// index of last entry, 0 if empty
    lastIndex: *const fn (ptr: *anyopaque) Index,
    /// term of entry at index
    term: *const fn (ptr: *anyopaque, index: Index) ?Term,
    /// entry from lo up to, but not including hi
    entries: *const fn (ptr: *anyopaque, lo: Index, hi: Index) Error![]const Entry,
    /// add entries to the end of the log
    append: *const fn (ptr: *anyopaque, new_entries: []const Entry) Error!void,
    /// remove every entry after `from`
    truncate: *const fn (ptr: *anyopaque, from: Index) Error!void,
};

pub fn hardState(s: Storage) HardState {
    return s.vtable.hardState(s.ptr);
}

pub fn setHardState(s: Storage, hs: HardState) Error!void {
    return s.vtable.setHardState(s.ptr, hs);
}

pub fn lastIndex(s: Storage) Index {
    return s.vtable.lastIndex(s.ptr);
}

pub fn term(s: Storage, index: Index) ?Term {
    return s.vtable.term(s.ptr, index);
}

pub fn lastTerm(s: Storage) Term {
    return s.term(s.lastIndex()).?;
}

pub fn entries(s: Storage, lo: Index, hi: Index) Error![]const Entry {
    return s.vtable.entries(s.ptr, lo, hi);
}

pub fn append(s: Storage, new_entries: []const Entry) Error!void {
    return s.vtable.append(s.ptr, new_entries);
}

pub fn truncate(s: Storage, from: Index) Error!void {
    return s.vtable.truncate(s.ptr, from);
}
