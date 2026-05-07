//! Sysvar helpers inspired by Pinocchio's sysvar module family.
//!
//! These helpers provide a formal API surface for loading fixed-size sysvars
//! directly from the runtime via `sol_get_sysvar`, as well as parsing sysvar
//! account data when the sysvar account is passed explicitly.

const builtin = @import("builtin");
const sdk = @import("../zignocchio.zig");
const syscalls = @import("../syscalls.zig");

const has_solana_tag = @hasField(@import("std").Target.Os.Tag, "solana");

fn isSolanaTarget() bool {
    return comptime if (has_solana_tag) builtin.target.os.tag == .solana else false;
}

pub const clock = @import("clock.zig");
pub const fees = @import("fees.zig");
pub const instructions = @import("instructions.zig");
pub const rent = @import("rent.zig");

/// Return value indicating that `offset + length` exceeded the sysvar data.
pub const OFFSET_LENGTH_EXCEEDS_SYSVAR: u64 = 1;

/// Return value indicating that the sysvar was not found / not supported.
pub const SYSVAR_NOT_FOUND: u64 = 2;

/// Fetch a raw slice of sysvar bytes from the runtime.
///
/// On host targets this returns `error.UnsupportedSysvar` since the runtime
/// syscall is not available there.
pub fn get(dst: []u8, sysvar_id: *const sdk.Pubkey, offset: usize) sdk.ProgramResult {
    if (!isSolanaTarget()) {
        return error.UnsupportedSysvar;
    }

    const result = syscalls.sol_get_sysvar(sysvar_id[0..].ptr, dst.ptr, offset, dst.len);
    return switch (result) {
        sdk.SUCCESS => {},
        OFFSET_LENGTH_EXCEEDS_SYSVAR => error.InvalidArgument,
        SYSVAR_NOT_FOUND => error.UnsupportedSysvar,
        else => error.UnsupportedSysvar,
    };
}
