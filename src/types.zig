pub const Term = u64;

pub const Index = u64;

pub const Entry = struct {
    term: Term,
    index: Index,
    data: []const u8,
};
