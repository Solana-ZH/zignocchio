//! Token Vault Program - lazy entrypoint experiment.

const sdk = @import("sdk");
const initialize = @import("initialize.zig");
const deposit = @import("deposit.zig");
const withdraw = @import("withdraw.zig");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Token Vault program: Starting");

    var account_buffer: [10]sdk.AccountInfo = undefined;
    const accounts = try sdk.lazy.collectAccountInfos(context, &account_buffer);
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (instruction_data.len == 0) {
        sdk.logMsg("Error: Empty instruction data");
        return error.InvalidInstructionData;
    }

    return switch (instruction_data[0]) {
        deposit.DISCRIMINATOR => blk: {
            sdk.logMsg("Token Vault: Routing to Deposit");
            const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};
            break :blk deposit.process(program_id, accounts, data);
        },
        withdraw.DISCRIMINATOR => blk: {
            sdk.logMsg("Token Vault: Routing to Withdraw");
            break :blk withdraw.process(program_id, accounts);
        },
        initialize.DISCRIMINATOR => blk: {
            sdk.logMsg("Token Vault: Routing to Initialize");
            break :blk initialize.process(program_id, accounts);
        },
        else => blk: {
            sdk.logMsg("Error: Unknown instruction discriminator");
            break :blk error.InvalidInstructionData;
        },
    };
}
