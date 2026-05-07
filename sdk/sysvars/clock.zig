//! Clock sysvar helpers.

const sdk = @import("../zignocchio.zig");
const sysvars = @import("mod.zig");

/// The ID of the clock sysvar.
pub const ID: sdk.Pubkey = .{
    6, 167, 213, 23, 24, 199, 116, 201,
    40, 86, 99, 152, 105, 29, 94, 182,
    139, 94, 184, 163, 155, 75, 109, 92,
    115, 85, 91, 33, 0, 0, 0, 0,
};

pub const Slot = u64;
pub const Epoch = u64;
pub const UnixTimestamp = i64;

pub const DEFAULT_TICKS_PER_SLOT: u64 = 64;
pub const DEFAULT_TICKS_PER_SECOND: u64 = 160;
pub const DEFAULT_MS_PER_SLOT: u64 = 1_000 * DEFAULT_TICKS_PER_SLOT / DEFAULT_TICKS_PER_SECOND;

pub const Clock = extern struct {
    slot: Slot,
    epoch_start_timestamp: UnixTimestamp,
    epoch: Epoch,
    leader_schedule_epoch: Epoch,
    unix_timestamp: UnixTimestamp,

    pub const LEN: usize = @sizeOf(Clock);

    pub fn get() sdk.ProgramError!Clock {
        var value: Clock = undefined;
        try sysvars.get(std.mem.asBytes(&value), &ID, 0);
        return value;
    }

    pub fn fromAccountInfo(account: sdk.AccountInfo) sdk.ProgramError!*const Clock {
        if (!sdk.pubkeyEq(account.key(), &ID)) return error.InvalidArgument;
        return fromBytes(account.borrowDataUnchecked());
    }

    pub fn fromBytes(bytes: []const u8) sdk.ProgramError!*const Clock {
        if (bytes.len < LEN) return error.InvalidArgument;
        if ((@intFromPtr(bytes.ptr) & (@alignOf(Clock) - 1)) != 0) return error.InvalidArgument;
        return fromBytesUnchecked(bytes);
    }

    pub fn fromBytesUnchecked(bytes: []const u8) *const Clock {
        return @as(*const Clock, @ptrCast(@alignCast(bytes.ptr)));
    }
};

const std = @import("std");

test "Clock.fromBytes parses valid aligned bytes" {
    var bytes: [Clock.LEN]u8 align(@alignOf(Clock)) = [_]u8{0} ** Clock.LEN;
    std.mem.writeInt(u64, bytes[0..8], 42, .little);
    std.mem.writeInt(i64, bytes[8..16], 7, .little);
    std.mem.writeInt(u64, bytes[16..24], 5, .little);
    std.mem.writeInt(u64, bytes[24..32], 6, .little);
    std.mem.writeInt(i64, bytes[32..40], 1234, .little);

    const clock = try Clock.fromBytes(bytes[0..]);
    try std.testing.expectEqual(@as(u64, 42), clock.slot);
    try std.testing.expectEqual(@as(i64, 7), clock.epoch_start_timestamp);
    try std.testing.expectEqual(@as(u64, 5), clock.epoch);
    try std.testing.expectEqual(@as(u64, 6), clock.leader_schedule_epoch);
    try std.testing.expectEqual(@as(i64, 1234), clock.unix_timestamp);
}

test "Clock.fromAccountInfo validates account key" {
    const bytes: [Clock.LEN]u8 align(@alignOf(Clock)) = [_]u8{0} ** Clock.LEN;
    const Layout = extern struct { account: sdk.Account, data: [Clock.LEN]u8 };
    var layout = Layout{ .account = .{
        .borrow_state = sdk.NON_DUP_MARKER,
        .is_signer = 0,
        .is_writable = 0,
        .executable = 0,
        .resize_delta = 0,
        .key = ID,
        .owner = .{0} ** 32,
        .lamports = 0,
        .data_len = bytes.len,
    }, .data = bytes };
    const info = sdk.AccountInfo{ .raw = &layout.account };
    _ = try Clock.fromAccountInfo(info);
}
