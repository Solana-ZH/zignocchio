//! Vault Program - lazy entrypoint experiment.

const sdk = @import("sdk");
const std = @import("std");

const DEPOSIT: u8 = 0;
const WITHDRAW: u8 = 1;

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Vault program: Starting");

    const instruction_data = context.peekInstructionDataUnchecked();
    if (instruction_data.len == 0) {
        sdk.logMsg("Error: Empty instruction data");
        return error.InvalidInstructionData;
    }

    return switch (instruction_data[0]) {
        DEPOSIT => blk: {
            sdk.logMsg("Vault: Routing to Deposit");
            break :blk processDeposit(context);
        },
        WITHDRAW => blk: {
            sdk.logMsg("Vault: Routing to Withdraw");
            break :blk processWithdraw(context);
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

fn processDeposit(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Deposit: Starting");
    sdk.logMsg("Deposit validate: checking account count");
    if (context.remaining() < 3) {
        sdk.logMsg("Error: Not enough accounts for deposit");
        return error.NotEnoughAccountKeys;
    }

    sdk.logMsg("Deposit validate: getting accounts");
    const owner = context.nextAccountUnchecked().assumeAccount();
    const vault = context.nextAccountUnchecked().assumeAccount();
    const system_program = context.nextAccountUnchecked().assumeAccount();
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();
    const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};

    sdk.logMsg("Deposit validate: checking owner signer");
    if (!owner.isSigner()) {
        sdk.logMsg("Error: Owner must be signer");
        return error.MissingRequiredSignature;
    }

    sdk.logMsg("Deposit validate: checking vault owner");
    var system_program_id = getSystemProgramId();
    if (!sdk.pubkeyEq(vault.owner(), &system_program_id)) {
        sdk.logMsg("Error: Vault must be owned by System Program");
        return error.IncorrectProgramId;
    }

    sdk.logMsg("Deposit validate: checking vault lamports");
    if (vault.borrowLamportsUnchecked().* != 0) {
        sdk.logMsg("Error: Vault must be empty");
        return error.InvalidAccountData;
    }

    sdk.logMsg("Deposit validate: deriving PDA");
    const seed_owner = owner.key().*;
    const seeds = &[_][]const u8{ "vault", &seed_owner };
    var vault_key: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);

    sdk.logMsg("Deposit validate: checking vault PDA");
    if (!sdk.pubkeyEq(vault.key(), &vault_key)) {
        sdk.logMsg("Error: Invalid vault PDA");
        return error.IncorrectProgramId;
    }

    sdk.logMsg("Deposit validate: checking system program");
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    if (data.len != 8) {
        sdk.logMsg("Error: Invalid deposit data length");
        return error.InvalidInstructionData;
    }
    const amount = std.mem.readInt(u64, data[0..8], .little);
    if (amount == 0) {
        sdk.logMsg("Error: Deposit amount must be greater than 0");
        return error.InvalidInstructionData;
    }

    sdk.logMsg("Deposit validate: done");
    sdk.logMsg("Deposit: Validated accounts and data");
    sdk.logMsg("Deposit amount:");
    sdk.logU64(amount);

    try sdk.system.transferLazy(owner, vault, amount);
    sdk.logMsg("Deposit: Transfer completed successfully");
    return {};
}

fn processWithdraw(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Withdraw: Starting");
    if (context.remaining() < 3) {
        sdk.logMsg("Error: Not enough accounts for withdraw");
        return error.NotEnoughAccountKeys;
    }

    const owner = context.nextAccountUnchecked().assumeAccount();
    const vault = context.nextAccountUnchecked().assumeAccount();
    const system_program = context.nextAccountUnchecked().assumeAccount();
    _ = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

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
    sdk.logMsg("Withdraw: Validated accounts");
    sdk.logMsg("Withdraw amount:");
    sdk.logU64(amount);
    if (amount == 0) {
        sdk.logMsg("Error: Vault is empty");
        return error.InsufficientFunds;
    }

    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 2, .little);
    std.mem.writeInt(u64, ix_data[4..12], amount, .little);
    const account_metas = [_]sdk.AccountMeta{
        .{ .pubkey = vault.key(), .is_signer = true, .is_writable = true },
        .{ .pubkey = owner.key(), .is_signer = false, .is_writable = true },
    };
    const instruction = sdk.Instruction{
        .program_id = &system_program_id,
        .accounts = &account_metas,
        .data = &ix_data,
    };
    const bump_array = [_]u8{bump};
    const signer_seeds = &[_][]const u8{ "vault", seed_owner[0..], bump_array[0..] };
    try sdk.invokeSigned(&instruction, &[_]sdk.AccountInfo{ vault.toAccountInfo(), owner.toAccountInfo() }, signer_seeds);
    sdk.logMsg("Withdraw: Transfer completed successfully");
    return {};
}
