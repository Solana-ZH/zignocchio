//! PDA Storage - lazy entrypoint experiment.

const sdk = @import("sdk");

const DISCRIMINATOR_INIT = 0;
const DISCRIMINATOR_UPDATE = 1;
const STORAGE_SEED = "storage";

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("PDA Storage: starting");

    return switch (context.remaining()) {
        4 => try initStorage(context),
        2 => try updateStorage(context),
        else => blk: {
            sdk.logMsg("Error: Invalid account layout");
            break :blk error.InvalidInstructionData;
        },
    };
}

fn initStorage(context: *sdk.lazy.EntryContext) sdk.ProgramResult {

    const payer = context.nextAccountUnchecked().assumeAccount();
    const storage_pda = context.nextAccountUnchecked().assumeAccount();
    const user = context.nextAccountUnchecked().assumeAccount();
    _ = context.nextAccountUnchecked();
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (!payer.isSigner()) return error.MissingRequiredSignature;
    if (!user.isSigner()) return error.MissingRequiredSignature;
    if (!payer.isWritable()) return error.ImmutableAccount;
    if (!storage_pda.isWritable()) return error.ImmutableAccount;

    if (instruction_data.len < 9) {
        sdk.logMsg("Error: Instruction data too short for init");
        return error.InvalidInstructionData;
    }
    const initial_value = @as(*align(1) const u64, @ptrCast(instruction_data.ptr + 1)).*;

    const seeds = &[_][]const u8{ STORAGE_SEED, user.key()[0..32] };
    var expected_pda: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_pda, &bump);
    if (!sdk.pubkeyEq(storage_pda.key(), &expected_pda)) {
        sdk.logMsg("Error: Invalid PDA");
        return error.InvalidArgument;
    }

    const signer_seeds = &[_][]const u8{ STORAGE_SEED, user.key()[0..32], &[_]u8{bump} };
    try sdk.system.createAccountSignedLazy(
        payer,
        storage_pda,
        program_id,
        40,
        1_200_000,
        signer_seeds,
    );

    const data = storage_pda.borrowMutDataUnchecked();
    if (data.len < 40) {
        sdk.logMsg("Error: Account data too small");
        return error.AccountDataTooSmall;
    }
    @memcpy(data[0..32], user.key()[0..32]);
    @as(*align(1) u64, @ptrCast(data.ptr + 32)).* = initial_value;

    sdk.logMsg("PDA Storage: initialized with value");
    sdk.logU64(initial_value);
    return {};
}

fn updateStorage(context: *sdk.lazy.EntryContext) sdk.ProgramResult {

    const storage_pda = context.nextAccountUnchecked().assumeAccount();
    const user = context.nextAccountUnchecked().assumeAccount();
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (!user.isSigner()) return error.MissingRequiredSignature;
    if (!storage_pda.isWritable()) return error.ImmutableAccount;

    if (instruction_data.len < 9) {
        sdk.logMsg("Error: Instruction data too short for update");
        return error.InvalidInstructionData;
    }
    const new_value = @as(*align(1) const u64, @ptrCast(instruction_data.ptr + 1)).*;

    const seeds = &[_][]const u8{ STORAGE_SEED, user.key()[0..32] };
    var expected_pda: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_pda, &bump);
    if (!sdk.pubkeyEq(storage_pda.key(), &expected_pda)) {
        sdk.logMsg("Error: Invalid PDA");
        return error.InvalidArgument;
    }

    const data = storage_pda.borrowMutDataUnchecked();
    if (data.len < 40) {
        sdk.logMsg("Error: Account data too small");
        return error.AccountDataTooSmall;
    }
    if (!sdk.pubkeyEq(data[0..32], user.key())) {
        sdk.logMsg("Error: User does not own this storage");
        return error.IllegalOwner;
    }
    @as(*align(1) u64, @ptrCast(data.ptr + 32)).* = new_value;

    sdk.logMsg("PDA Storage: updated to value");
    sdk.logU64(new_value);
    return {};
}
