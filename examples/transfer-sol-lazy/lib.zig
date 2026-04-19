//! Transfer SOL - lazy entrypoint experiment.
//!
//! Same external semantics as `transfer-sol`, but uses the experimental
//! Pinocchio-style lazy cursor to isolate entrypoint/account-loading overhead.

const sdk = @import("sdk");
const system = sdk.system;

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    if (context.remaining() != 3) return error.NotEnoughAccountKeys;

    const from = context.nextAccountUnchecked().assumeAccount();
    const to_maybe = context.nextAccountUnchecked();
    const system_program = context.nextAccountUnchecked().assumeAccount();
    const instruction_data = context.instructionDataUnchecked();
    if (instruction_data.len != 8) return error.InvalidInstructionData;

    const amount = @as(*align(1) const u64, @ptrCast(instruction_data.ptr)).*;
    if (amount == 0) return error.InvalidInstructionData;
    if (!from.isSigner()) return error.MissingRequiredSignature;
    if (!from.isWritable()) return error.ImmutableAccount;

    var system_program_id: sdk.Pubkey = undefined;
    system.getSystemProgramId(&system_program_id);
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        return error.IncorrectProgramId;
    }

    switch (to_maybe) {
        .Account => |to| {
            if (!to.isWritable()) return error.ImmutableAccount;
            try system.transferLazy(from, to, amount);
        },
        .Duplicated => |dup_index| {
            if (dup_index != 0) return error.InvalidArgument;
            try system.transferLazy(from, from, amount);
        },
    }

    return {};
}
