//! Fees sysvar helpers.
//!
//! Unlike fixed-layout sysvars such as `Clock` and `Rent`, the fees sysvar
//! historically relied on a dedicated runtime syscall. Here we expose a stable
//! parsing layer and attempt runtime loading through the generic `sol_get_sysvar`
//! path. If the runtime does not expose this sysvar through `sol_get_sysvar`,
//! callers will receive `error.UnsupportedSysvar`.

const sdk = @import("../zignocchio.zig");
const sysvars = @import("mod.zig");
const clock = @import("clock.zig");
const std = @import("std");

/// The ID of the fees sysvar.
pub const ID: sdk.Pubkey = .{
    6, 167, 213, 23, 24, 226, 90, 141,
    131, 80, 60, 37, 26, 122, 240, 113,
    38, 253, 114, 0, 223, 111, 196, 237,
    82, 106, 156, 144, 0, 0, 0, 0,
};

pub const DEFAULT_TARGET_LAMPORTS_PER_SIGNATURE: u64 = 10_000;
pub const DEFAULT_TARGET_SIGNATURES_PER_SLOT: u64 = 50 * clock.DEFAULT_MS_PER_SLOT;
pub const DEFAULT_BURN_PERCENT: u8 = 50;

pub const FeeCalculator = struct {
    lamports_per_signature: u64,

    pub fn new(lamports_per_signature: u64) FeeCalculator {
        return .{ .lamports_per_signature = lamports_per_signature };
    }
};

pub const FeeRateGovernor = struct {
    lamports_per_signature: u64,
    target_lamports_per_signature: u64,
    target_signatures_per_slot: u64,
    min_lamports_per_signature: u64,
    max_lamports_per_signature: u64,
    burn_percent: u8,

    pub fn createFeeCalculator(self: *const FeeRateGovernor) FeeCalculator {
        return FeeCalculator.new(self.lamports_per_signature);
    }

    pub fn burn(self: *const FeeRateGovernor, fees: u64) struct { unburned: u64, burned: u64 } {
        const burned = fees * self.burn_percent / 100;
        return .{ .unburned = fees - burned, .burned = burned };
    }
};

pub const Fees = struct {
    fee_calculator: FeeCalculator,
    fee_rate_governor: FeeRateGovernor,

    /// bincode-style serialized length used by the sysvar account / syscall.
    pub const LEN: usize = 8 + 8 + 8 + 8 + 8 + 8 + 1;

    pub fn init(fee_calculator: FeeCalculator, fee_rate_governor: FeeRateGovernor) Fees {
        return .{ .fee_calculator = fee_calculator, .fee_rate_governor = fee_rate_governor };
    }

    pub fn get() sdk.ProgramError!Fees {
        var bytes: [LEN]u8 = undefined;
        try sysvars.get(bytes[0..], &ID, 0);
        return fromBytes(bytes[0..]);
    }

    pub fn fromAccountInfo(account: sdk.AccountInfo) sdk.ProgramError!Fees {
        if (!sdk.pubkeyEq(account.key(), &ID)) return error.InvalidArgument;
        return fromBytes(account.borrowDataUnchecked());
    }

    pub fn fromBytes(bytes: []const u8) sdk.ProgramError!Fees {
        if (bytes.len < LEN) return error.InvalidArgument;

        return .{
            .fee_calculator = .{
                .lamports_per_signature = std.mem.readInt(u64, bytes[0..8], .little),
            },
            .fee_rate_governor = .{
                .lamports_per_signature = std.mem.readInt(u64, bytes[8..16], .little),
                .target_lamports_per_signature = std.mem.readInt(u64, bytes[16..24], .little),
                .target_signatures_per_slot = std.mem.readInt(u64, bytes[24..32], .little),
                .min_lamports_per_signature = std.mem.readInt(u64, bytes[32..40], .little),
                .max_lamports_per_signature = std.mem.readInt(u64, bytes[40..48], .little),
                .burn_percent = bytes[48],
            },
        };
    }
};

test "Fees.fromBytes parses bincode-style layout" {
    var bytes: [Fees.LEN]u8 = [_]u8{0} ** Fees.LEN;
    std.mem.writeInt(u64, bytes[0..8], 5000, .little);
    std.mem.writeInt(u64, bytes[8..16], 5000, .little);
    std.mem.writeInt(u64, bytes[16..24], DEFAULT_TARGET_LAMPORTS_PER_SIGNATURE, .little);
    std.mem.writeInt(u64, bytes[24..32], DEFAULT_TARGET_SIGNATURES_PER_SLOT, .little);
    std.mem.writeInt(u64, bytes[32..40], 1000, .little);
    std.mem.writeInt(u64, bytes[40..48], 10_000, .little);
    bytes[48] = DEFAULT_BURN_PERCENT;

    const fees = try Fees.fromBytes(bytes[0..]);
    try std.testing.expectEqual(@as(u64, 5000), fees.fee_calculator.lamports_per_signature);
    try std.testing.expectEqual(@as(u64, 5000), fees.fee_rate_governor.lamports_per_signature);
    try std.testing.expectEqual(@as(u64, DEFAULT_TARGET_LAMPORTS_PER_SIGNATURE), fees.fee_rate_governor.target_lamports_per_signature);
    try std.testing.expectEqual(@as(u64, DEFAULT_TARGET_SIGNATURES_PER_SLOT), fees.fee_rate_governor.target_signatures_per_slot);
    try std.testing.expectEqual(@as(u8, DEFAULT_BURN_PERCENT), fees.fee_rate_governor.burn_percent);
}

test "FeeRateGovernor burn splits fees" {
    const governor = FeeRateGovernor{
        .lamports_per_signature = 0,
        .target_lamports_per_signature = 0,
        .target_signatures_per_slot = 0,
        .min_lamports_per_signature = 0,
        .max_lamports_per_signature = 0,
        .burn_percent = 50,
    };
    const burned = governor.burn(100);
    try std.testing.expectEqual(@as(u64, 50), burned.unburned);
    try std.testing.expectEqual(@as(u64, 50), burned.burned);
}

test "Fees.fromAccountInfo validates sysvar key" {
    const Layout = extern struct { account: sdk.Account, data: [Fees.LEN]u8 };
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
            .data_len = Fees.LEN,
        },
        .data = [_]u8{0} ** Fees.LEN,
    };
    _ = try Fees.fromAccountInfo(.{ .raw = &layout.account });
}
