//! Experimental Pinocchio-style lazy entrypoint utilities.
//!
//! Unlike the regular entrypoint path, this module does not eagerly deserialize
//! all accounts up front. It keeps a cursor over the runtime input buffer and
//! yields thin account wrappers on demand.

const errors = @import("errors.zig");
const types = @import("types.zig");

const Pubkey = types.Pubkey;
const Account = types.Account;
const NON_DUP_MARKER = types.NON_DUP_MARKER;
const MAX_PERMITTED_DATA_INCREASE = types.MAX_PERMITTED_DATA_INCREASE;
const BPF_ALIGN_OF_U128 = types.BPF_ALIGN_OF_U128;

const STATIC_ACCOUNT_DATA: usize = @sizeOf(Account) + MAX_PERMITTED_DATA_INCREASE;

inline fn alignPointer(ptr: usize) usize {
    return (ptr + (BPF_ALIGN_OF_U128 - 1)) & ~(BPF_ALIGN_OF_U128 - 1);
}

inline fn skipAccount(ptr: [*]u8) [*]u8 {
    const account_ptr = @as(*Account, @ptrCast(@alignCast(ptr)));
    var next = ptr + @sizeOf(u64);
    if (account_ptr.borrow_state == NON_DUP_MARKER) {
        next += STATIC_ACCOUNT_DATA;
        next += @as(usize, @intCast(account_ptr.data_len));
        next = @ptrFromInt(alignPointer(@intFromPtr(next)));
    }
    return next;
}

/// Thin zero-copy account wrapper for lazy/cursor-based programs.
pub const LazyAccount = struct {
    raw: *Account,

    pub inline fn toAccountInfo(self: LazyAccount) types.AccountInfo {
        return .{ .raw = self.raw };
    }

    pub inline fn key(self: LazyAccount) *const Pubkey {
        return &self.raw.key;
    }

    pub inline fn owner(self: LazyAccount) *const Pubkey {
        return &self.raw.owner;
    }

    pub inline fn isSigner(self: LazyAccount) bool {
        return self.raw.is_signer != 0;
    }

    pub inline fn isWritable(self: LazyAccount) bool {
        return self.raw.is_writable != 0;
    }

    pub inline fn executable(self: LazyAccount) bool {
        return self.raw.executable != 0;
    }

    pub inline fn dataLen(self: LazyAccount) usize {
        return @intCast(self.raw.data_len);
    }

    pub inline fn dataPtr(self: LazyAccount) [*]u8 {
        return @ptrFromInt(@intFromPtr(self.raw) + @sizeOf(Account));
    }

    pub inline fn borrowDataUnchecked(self: LazyAccount) []const u8 {
        return self.dataPtr()[0..self.dataLen()];
    }

    pub inline fn borrowMutDataUnchecked(self: LazyAccount) []u8 {
        return self.dataPtr()[0..self.dataLen()];
    }

    pub inline fn borrowLamportsUnchecked(self: LazyAccount) *const u64 {
        return &self.raw.lamports;
    }

    pub inline fn borrowMutLamportsUnchecked(self: LazyAccount) *u64 {
        return &self.raw.lamports;
    }
};

/// Account yielded by the lazy cursor. Duplicate accounts are surfaced as their
/// original account index instead of being eagerly resolved.
pub const MaybeAccount = union(enum) {
    Account: LazyAccount,
    Duplicated: u8,

    pub inline fn assumeAccount(self: MaybeAccount) LazyAccount {
        return switch (self) {
            .Account => |account| account,
            .Duplicated => unreachable,
        };
    }
};

/// Cursor over the Solana entrypoint input buffer.
pub const EntryContext = struct {
    buffer: [*]u8,
    remaining_accounts_count: u64,

    pub inline fn load(input: [*]u8) EntryContext {
        return .{
            .buffer = input + @sizeOf(u64),
            .remaining_accounts_count = @as(*const u64, @ptrCast(@alignCast(input))).*,
        };
    }

    pub inline fn remaining(self: *const EntryContext) u64 {
        return self.remaining_accounts_count;
    }

    /// Read the next account and decrement `remaining()`.
    pub inline fn nextAccount(self: *EntryContext) errors.ProgramError!MaybeAccount {
        if (self.remaining_accounts_count == 0) return error.NotEnoughAccountKeys;
        self.remaining_accounts_count -= 1;
        return self.readAccount();
    }

    /// Read the next account without decrementing `remaining()`.
    pub inline fn nextAccountUnchecked(self: *EntryContext) MaybeAccount {
        return self.readAccount();
    }

    /// Read instruction data once all accounts have been consumed.
    pub inline fn instructionData(self: *const EntryContext) errors.ProgramError![]const u8 {
        if (self.remaining_accounts_count != 0) return error.InvalidInstructionData;
        return self.instructionDataUnchecked();
    }

    /// Read instruction data from the current cursor position.
    pub inline fn instructionDataUnchecked(self: *const EntryContext) []const u8 {
        const data_len = @as(*const u64, @ptrCast(@alignCast(self.buffer))).*;
        const data_ptr = self.buffer + @sizeOf(u64);
        return data_ptr[0..@intCast(data_len)];
    }

    /// Read instruction data without consuming accounts by temporarily scanning
    /// over the remaining serialized accounts.
    pub inline fn peekInstructionDataUnchecked(self: *const EntryContext) []const u8 {
        var ptr = self.buffer;
        var accounts_left = self.remaining_accounts_count;
        while (accounts_left != 0) : (accounts_left -= 1) {
            ptr = skipAccount(ptr);
        }
        const data_len = @as(*const u64, @ptrCast(@alignCast(ptr))).*;
        const data_ptr = ptr + @sizeOf(u64);
        return data_ptr[0..@intCast(data_len)];
    }

    /// Read the program id once all accounts have been consumed.
    pub inline fn programId(self: *const EntryContext) errors.ProgramError!*const Pubkey {
        if (self.remaining_accounts_count != 0) return error.InvalidInstructionData;
        return self.programIdUnchecked();
    }

    /// Read the program id from the current cursor position.
    pub inline fn programIdUnchecked(self: *const EntryContext) *const Pubkey {
        const data_len = @as(*const u64, @ptrCast(@alignCast(self.buffer))).*;
        return @as(*const Pubkey, @ptrCast(@alignCast(self.buffer + @sizeOf(u64) + @as(usize, @intCast(data_len)))));
    }

    inline fn readAccount(self: *EntryContext) MaybeAccount {
        const account_ptr = @as(*Account, @ptrCast(@alignCast(self.buffer)));
        self.buffer = skipAccount(self.buffer);

        if (account_ptr.borrow_state == NON_DUP_MARKER) {
            return .{ .Account = .{ .raw = account_ptr } };
        }

        return .{ .Duplicated = account_ptr.borrow_state };
    }
};

/// Collect all remaining accounts into an `AccountInfo` slice, resolving
/// duplicates against accounts already seen in the output buffer.
pub inline fn collectAccountInfos(
    context: *EntryContext,
    out: []types.AccountInfo,
) errors.ProgramError![]types.AccountInfo {
    const total: usize = @intCast(context.remaining());
    if (total > out.len) return error.NotEnoughAccountKeys;

    var i: usize = 0;
    while (i < total) : (i += 1) {
        const maybe = try context.nextAccount();
        out[i] = switch (maybe) {
            .Account => |account| account.toAccountInfo(),
            .Duplicated => |dup_index| blk: {
                if (dup_index >= i) return error.InvalidAccountData;
                break :blk out[dup_index];
            },
        };
    }

    return out[0..total];
}

pub const EntrypointFn = *const fn (context: *EntryContext) errors.ProgramResult;

pub fn entrypoint(
    comptime process_instruction: EntrypointFn,
) fn ([*]u8) callconv(.c) u64 {
    return struct {
        fn entry(input: [*]u8) callconv(.c) u64 {
            var context = EntryContext.load(input);
            process_instruction(&context) catch |err| {
                return errors.errorToU64(err);
            };
            return errors.SUCCESS;
        }
    }.entry;
}
