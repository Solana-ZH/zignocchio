//! Transfer SOL - Minimal Zignocchio Example
//!
//! This is the simplest possible Solana program that demonstrates:
//! - Signer validation using guard helpers
//! - Writable account checks
//! - System Program CPI for lamport transfers
//!
//! ## Instruction
//! - `0` - Transfer lamports from signer to recipient
//!   - Instruction data: `amount: u64` (8 bytes, little-endian)
//!   - Accounts:
//!     0. `[signer, writable]` from — source of lamports
//!     1. `[writable]` to — destination for lamports
//!     2. `[]` system_program — System Program ID

const sdk = @import("sdk");
const guard = sdk.guard;
const system = sdk.system;
const std = @import("std");

/// Program entrypoint
export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypointWithMaxAccounts(3, processInstruction), .{input});
}

/// Process instruction
fn processInstruction(
    _: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    if (instruction_data.len != 8) {
        return error.InvalidInstructionData;
    }
    const amount = std.mem.readInt(u64, instruction_data[0..8], .little);
    if (amount == 0) {
        return error.InvalidInstructionData;
    }

    if (accounts.len < 3) {
        return error.NotEnoughAccountKeys;
    }

    const from = accounts[0];
    const to = accounts[1];
    const system_program = accounts[2];

    try guard.assert_signer(from);
    try guard.assert_writable(from);
    try guard.assert_writable(to);

    var system_program_id: sdk.Pubkey = undefined;
    system.getSystemProgramId(&system_program_id);
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        return error.IncorrectProgramId;
    }

    try system.transfer(from, to, amount);
    return {};
}
