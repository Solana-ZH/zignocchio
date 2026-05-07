//! Counter Program - lazy entrypoint experiment.

const sdk = @import("sdk");
const std = @import("std");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Counter program: starting");

    if (context.remaining() != 1) {
        sdk.logMsg("Error: Not enough accounts");
        return error.NotEnoughAccountKeys;
    }

    const counter_account = context.nextAccountUnchecked().assumeAccount();
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (!counter_account.isWritable()) {
        sdk.logMsg("Error: Counter account not writable");
        return error.ImmutableAccount;
    }

    if (!sdk.pubkeyEq(counter_account.owner(), program_id)) {
        sdk.logMsg("Error: Counter account not owned by program");
        return error.IncorrectProgramId;
    }

    if (counter_account.dataLen() < 8) {
        sdk.logMsg("Error: Counter account too small");
        return error.AccountDataTooSmall;
    }

    const data = counter_account.borrowMutDataUnchecked();
    const counter_ptr = @as(*u64, @ptrCast(@alignCast(data.ptr)));
    const current = counter_ptr.*;

    var current_logger = sdk.Logger(48).init();
    _ = current_logger.append("Current counter value=").append(current);
    current_logger.log();

    if (instruction_data.len > 0) {
        const operation = instruction_data[0];
        switch (operation) {
            0 => {
                if (current == std.math.maxInt(u64)) {
                    sdk.logMsg("Error: Counter overflow");
                    return error.ArithmeticOverflow;
                }
                counter_ptr.* = current + 1;
                sdk.logMsg("Incremented counter");
            },
            1 => {
                if (current == 0) {
                    sdk.logMsg("Error: Counter underflow");
                    return error.ArithmeticOverflow;
                }
                counter_ptr.* = current - 1;
                sdk.logMsg("Decremented counter");
            },
            2 => {
                counter_ptr.* = 0;
                sdk.logMsg("Reset counter");
            },
            else => {
                sdk.logMsg("Error: Unknown operation");
                return error.InvalidInstructionData;
            },
        }
    } else {
        if (current == std.math.maxInt(u64)) {
            sdk.logMsg("Error: Counter overflow");
            return error.ArithmeticOverflow;
        }
        counter_ptr.* = current + 1;
        sdk.logMsg("Incremented counter (default)");
    }

    var new_logger = sdk.Logger(48).init();
    _ = new_logger.append("New counter value=").append(counter_ptr.*);
    new_logger.log();
    return {};
}
