pub const Term = u64;

pub const Index = u64;

pub const Entry = struct {
    term: Term,
    index: Index,
    data: []const u8,
};

pub const NodeId = u64;

pub const HardState = struct {
    current_term: Term = 0,
    voted_for: ?NodeId = null,
};

pub const RequestVote = struct {
    last_log_index: Index,
    last_log_term: Term,
};

pub const RequestVoteResponse = struct {
    vote_granted: bool,
};

pub const AppendEntries = struct {
    prev_log_index: Index,
    prev_log_term: Term,
    entries: []const Entry,
    leader_commit: Index,
};

pub const AppendEntriesResponse = struct {
    success: bool,
    match_index: Index,
};

pub const Message = struct {
    from: NodeId,
    to: NodeId,
    /// sender's current term
    term: Term,
    body: Body,

    pub const Body = union(enum) {
        request_vote: RequestVote,
        request_vote_response: RequestVoteResponse,
        append_entries: AppendEntries,
        append_entries_response: AppendEntriesResponse,
    };
};
