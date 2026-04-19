//! Vault Program - lazy entrypoint experiment.

const sdk = @import("sdk");

const DEPOSIT: u8 = 0;
const WITHDRAW: u8 = 1;

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    if (context.remaining() != 3) {
        sdk.logMsg("Error: Invalid account layout");
        return error.NotEnoughAccountKeys;
    }

    const owner = context.nextAccountUnchecked().assumeAccount();
    const vault = context.nextAccountUnchecked().assumeAccount();
    const system_program = context.nextAccountUnchecked().assumeAccount();
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (instruction_data.len == 0) {
        sdk.logMsg("Error: Empty instruction data");
        return error.InvalidInstructionData;
    }

    return switch (instruction_data[0]) {
        DEPOSIT => blk: {
            break :blk processDeposit(owner, vault, system_program, program_id, instruction_data[1..]);
        },
        WITHDRAW => blk: {
            break :blk processWithdraw(owner, vault, system_program, program_id);
        },
        else => blk: {
            sdk.logMsg("Error: Unknown instruction discriminator");
            break :blk error.InvalidInstructionData;
        },
    };
}

fn getSystemProgramId() sdk.Pubkey {
    var system_program_id: sdk.Pubkey = undefined;
    sdk.system.getSystemProgramId(&system_program_id);
    return system_program_id;
}

fn processDeposit(
    owner: sdk.LazyAccount,
    vault: sdk.LazyAccount,
    system_program: sdk.LazyAccount,
    program_id: *const sdk.Pubkey,
    data: []const u8,
) sdk.ProgramResult {
    if (!owner.isSigner()) {
        sdk.logMsg("Error: Owner must be signer");
        return error.MissingRequiredSignature;
    }

    var system_program_id = getSystemProgramId();
    if (!sdk.pubkeyEq(vault.owner(), &system_program_id)) {
        sdk.logMsg("Error: Vault must be owned by System Program");
        return error.IncorrectProgramId;
    }

    if (vault.borrowLamportsUnchecked().* != 0) {
        sdk.logMsg("Error: Vault must be empty");
        return error.InvalidAccountData;
    }

    const seed_owner = owner.key().*;
    const seeds = &[_][]const u8{ "vault", &seed_owner };
    var vault_key: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);

    if (!sdk.pubkeyEq(vault.key(), &vault_key)) {
        sdk.logMsg("Error: Invalid vault PDA");
        return error.IncorrectProgramId;
    }

    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    if (data.len != 8) {
        sdk.logMsg("Error: Invalid deposit data length");
        return error.InvalidInstructionData;
    }
    const amount = @as(*align(1) const u64, @ptrCast(data.ptr)).*;
    if (amount == 0) {
        sdk.logMsg("Error: Deposit amount must be greater than 0");
        return error.InvalidInstructionData;
    }

    try sdk.system.transferLazy(owner, vault, amount);
    return {};
}

fn processWithdraw(
    owner: sdk.LazyAccount,
    vault: sdk.LazyAccount,
    system_program: sdk.LazyAccount,
    program_id: *const sdk.Pubkey,
) sdk.ProgramResult {
    if (!owner.isSigner()) {
        sdk.logMsg("Error: Owner must be signer");
        return error.MissingRequiredSignature;
    }

    var system_program_id = getSystemProgramId();
    if (!sdk.pubkeyEq(vault.owner(), &system_program_id)) {
        sdk.logMsg("Error: Vault must be owned by System Program");
        return error.IncorrectProgramId;
    }

    const seed_owner = owner.key().*;
    const seeds = &[_][]const u8{ "vault", &seed_owner };
    var vault_key: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);
    if (!sdk.pubkeyEq(vault.key(), &vault_key)) {
        sdk.logMsg("Error: Invalid vault PDA");
        return error.IncorrectProgramId;
    }
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    const amount = vault.borrowLamportsUnchecked().*;
    if (amount == 0) {
        sdk.logMsg("Error: Vault is empty");
        return error.InsufficientFunds;
    }

    const bump_array = [_]u8{bump};
    const signer_seeds = &[_][]const u8{ "vault", seed_owner[0..], bump_array[0..] };
    try sdk.system.transferSignedLazy(vault, owner, amount, signer_seeds);
    return {};
}
