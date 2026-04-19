//! Transfer Owned - apples-to-apples lamport transfer benchmark.
//!
//! This example intentionally mirrors the minimal semantics used by the
//! `transfer-lamports` microbenchmarks in `solana-program-rosetta`:
//! - exactly 2 accounts
//! - no CPI
//! - direct lamport mutation
//! - source account is expected to be owned by this program in the harness
//!
//! It is not meant to be a production UX example like `transfer-sol`; it exists
//! to compare Zignocchio's minimal runtime overhead against Rust and Pinocchio
//! on an equivalent instruction shape.

const sdk = @import("sdk");
const std = @import("std");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(2, processInstruction), .{input});
}

fn processInstruction(
    _: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    if (accounts.len != 2) return error.NotEnoughAccountKeys;
    if (instruction_data.len != 8) return error.InvalidInstructionData;

    const amount = std.mem.readInt(u64, instruction_data[0..8], .little);

    const source = accounts[0].raw;
    const destination = accounts[1].raw;
    source.lamports -= amount;
    destination.lamports += amount;
    return {};
}
