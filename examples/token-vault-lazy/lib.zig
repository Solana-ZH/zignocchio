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

    return switch (context.remaining()) {
        6 => blk: {
            var accounts = [_]sdk.AccountInfo{
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
            };
            const instruction_data = context.instructionDataUnchecked();
            const program_id = context.programIdUnchecked();
            if (instruction_data.len == 0) return error.InvalidInstructionData;
            if (instruction_data[0] != initialize.DISCRIMINATOR) return error.InvalidInstructionData;
            sdk.logMsg("Token Vault: Routing to Initialize");
            break :blk initialize.process(program_id, &accounts);
        },
        4 => blk: {
            var accounts = [_]sdk.AccountInfo{
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
                context.nextAccountUnchecked().assumeAccount().toAccountInfo(),
            };
            const instruction_data = context.instructionDataUnchecked();
            const program_id = context.programIdUnchecked();
            if (instruction_data.len == 0) return error.InvalidInstructionData;
            break :blk switch (instruction_data[0]) {
                deposit.DISCRIMINATOR => blk2: {
                    sdk.logMsg("Token Vault: Routing to Deposit");
                    const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};
                    break :blk2 deposit.process(program_id, &accounts, data);
                },
                withdraw.DISCRIMINATOR => blk2: {
                    sdk.logMsg("Token Vault: Routing to Withdraw");
                    break :blk2 withdraw.process(program_id, &accounts);
                },
                else => blk2: {
                    sdk.logMsg("Error: Unknown instruction discriminator");
                    break :blk2 error.InvalidInstructionData;
                },
            };
        },
        else => blk: {
            sdk.logMsg("Error: Empty instruction data");
            break :blk error.InvalidInstructionData;
        },
    };
}
