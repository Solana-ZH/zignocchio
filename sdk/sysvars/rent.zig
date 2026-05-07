//! Rent sysvar helpers.

const builtin = @import("builtin");
const sdk = @import("../zignocchio.zig");
const sysvars = @import("mod.zig");
const std = @import("std");

const has_solana_tag = @hasField(std.Target.Os.Tag, "solana");

fn isSolanaTarget() bool {
    return comptime if (has_solana_tag) builtin.target.os.tag == .solana else false;
}

/// The ID of the rent sysvar.
pub const ID: sdk.Pubkey = .{
    6, 167, 213, 23, 25, 44, 92, 81,
    33, 140, 201, 76, 61, 74, 241, 127,
    88, 218, 238, 8, 155, 161, 253, 68,
    227, 219, 217, 138, 0, 0, 0, 0,
};

pub const DEFAULT_LAMPORTS_PER_BYTE: u64 = 6960;
pub const ACCOUNT_STORAGE_OVERHEAD: u64 = 128;
pub const MAX_PERMITTED_DATA_LENGTH: u64 = 10 * 1024 * 1024;

const CURRENT_EXEMPTION_THRESHOLD: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 64 };
const SIMD0194_EXEMPTION_THRESHOLD: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 240, 63 };
const CURRENT_MAX_LAMPORTS_PER_BYTE: u64 = 879_598_564_933;
const SIMD0194_MAX_LAMPORTS_PER_BYTE: u64 = 1_759_197_129_867;

pub const Rent = extern struct {
    lamports_per_byte: u64,
    exemption_threshold: [8]u8,

    pub const LEN: usize = @sizeOf(Rent);

    pub fn get() sdk.ProgramError!Rent {
        var value: Rent = undefined;
        try sysvars.get(std.mem.asBytes(&value), &ID, 0);
        return value;
    }

    pub fn fromAccountInfo(account: sdk.AccountInfo) sdk.ProgramError!*const Rent {
        if (!sdk.pubkeyEq(account.key(), &ID)) return error.InvalidArgument;
        return fromBytes(account.borrowDataUnchecked());
    }

    pub fn fromBytes(bytes: []const u8) sdk.ProgramError!*const Rent {
        if (bytes.len < LEN) return error.InvalidArgument;
        if ((@intFromPtr(bytes.ptr) & (@alignOf(Rent) - 1)) != 0) return error.InvalidArgument;
        return fromBytesUnchecked(bytes);
    }

    pub fn fromBytesUnchecked(bytes: []const u8) *const Rent {
        return @as(*const Rent, @ptrCast(@alignCast(bytes.ptr)));
    }

    pub fn tryMinimumBalance(self: *const Rent, data_len: usize) sdk.ProgramError!u64 {
        const bytes: u64 = @intCast(data_len);
        if (bytes > MAX_PERMITTED_DATA_LENGTH) return error.InvalidArgument;

        if (std.mem.eql(u8, self.exemption_threshold[0..], SIMD0194_EXEMPTION_THRESHOLD[0..])) {
            if (self.lamports_per_byte > SIMD0194_MAX_LAMPORTS_PER_BYTE) return error.ArithmeticOverflow;
            return (ACCOUNT_STORAGE_OVERHEAD + bytes) * self.lamports_per_byte;
        }

        if (std.mem.eql(u8, self.exemption_threshold[0..], CURRENT_EXEMPTION_THRESHOLD[0..])) {
            if (self.lamports_per_byte > CURRENT_MAX_LAMPORTS_PER_BYTE) return error.ArithmeticOverflow;
            return 2 * (ACCOUNT_STORAGE_OVERHEAD + bytes) * self.lamports_per_byte;
        }

        if (isSolanaTarget()) {
            return error.InvalidArgument;
        }

        const threshold = std.mem.bytesToValue(f64, &self.exemption_threshold);
        const balance = @as(f64, @floatFromInt((ACCOUNT_STORAGE_OVERHEAD + bytes) * self.lamports_per_byte)) * threshold;
        if (!std.math.isFinite(balance) or balance < 0) return error.ArithmeticOverflow;
        return @intFromFloat(balance);
    }
};

test "Rent.tryMinimumBalance uses current default threshold fast path" {
    var bytes: [Rent.LEN]u8 align(@alignOf(Rent)) = [_]u8{0} ** Rent.LEN;
    std.mem.writeInt(u64, bytes[0..8], DEFAULT_LAMPORTS_PER_BYTE, .little);
    @memcpy(bytes[8..16], CURRENT_EXEMPTION_THRESHOLD[0..]);

    const rent = try Rent.fromBytes(bytes[0..]);
    try std.testing.expectEqual(
        @as(u64, 2 * (ACCOUNT_STORAGE_OVERHEAD + 40) * DEFAULT_LAMPORTS_PER_BYTE),
        try rent.tryMinimumBalance(40),
    );
}

test "Rent.fromAccountInfo validates account key" {
    const Layout = extern struct { account: sdk.Account, data: [Rent.LEN]u8 };
    var layout = Layout{
        .account = .{
            .borrow_state = sdk.NON_DUP_MARKER,
            .is_signer = 0,
            .is_writable = 0,
            .executable = 0,
            .resize_delta = 0,
            .key = ID,
            .owner = .{0} ** 32,
            .lamports = 0,
            .data_len = Rent.LEN,
        },
        .data = [_]u8{0} ** Rent.LEN,
    };
    _ = try Rent.fromAccountInfo(.{ .raw = &layout.account });
}
