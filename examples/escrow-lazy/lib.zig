//! Escrow Program - lazy entrypoint experiment.

const sdk = @import("sdk");
const std = @import("std");

const MAKE: u8 = 0;
const ACCEPT: u8 = 1;
const REFUND: u8 = 2;

const EscrowState = extern struct {
    pub const DISCRIMINATOR: u8 = 0xE5;

    discriminator: u8,
    maker: sdk.Pubkey,
    taker: sdk.Pubkey,
    amount: u64,
};

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Escrow program: Starting");

    const instruction_data = context.peekInstructionDataUnchecked();
    if (instruction_data.len == 0) {
        sdk.logMsg("Error: Empty instruction data");
        return error.InvalidInstructionData;
    }

    return switch (instruction_data[0]) {
        MAKE => blk: {
            sdk.logMsg("Escrow: Routing to Make");
            break :blk processMake(context);
        },
        ACCEPT => blk: {
            sdk.logMsg("Escrow: Routing to Accept");
            break :blk processAccept(context);
        },
        REFUND => blk: {
            sdk.logMsg("Escrow: Routing to Refund");
            break :blk processRefund(context);
        },
        else => blk: {
            sdk.logMsg("Error: Unknown instruction discriminator");
            break :blk error.InvalidInstructionData;
        },
    };
}

fn processMake(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Make: Starting");
    if (context.remaining() < 3) {
        sdk.logMsg("Error: Not enough accounts for make");
        return error.NotEnoughAccountKeys;
    }

    const maker = context.nextAccountUnchecked().assumeAccount();
    const escrow = context.nextAccountUnchecked().assumeAccount();
    const system_program = context.nextAccountUnchecked().assumeAccount();
    const instruction_data = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();
    const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};

    if (!maker.isSigner()) return error.MissingRequiredSignature;
    if (!escrow.isWritable()) return error.ImmutableAccount;

    var system_program_id: sdk.Pubkey = undefined;
    sdk.system.getSystemProgramId(&system_program_id);
    if (!sdk.pubkeyEq(escrow.owner(), &system_program_id)) return error.IncorrectProgramId;
    if (escrow.borrowLamportsUnchecked().* != 0) {
        sdk.logMsg("Error: Escrow must be empty");
        return error.AccountAlreadyInitialized;
    }

    const maker_key = maker.key().*;
    const seeds = &[_][]const u8{ "escrow", &maker_key };
    var expected_escrow: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_escrow, &bump);
    if (!sdk.pubkeyEq(escrow.key(), &expected_escrow)) {
        sdk.logMsg("Error: Invalid escrow PDA");
        return error.IncorrectProgramId;
    }
    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) {
        sdk.logMsg("Error: Invalid system program");
        return error.IncorrectProgramId;
    }

    if (data.len != 40) {
        sdk.logMsg("Error: Invalid make data length");
        return error.InvalidInstructionData;
    }
    var taker: sdk.Pubkey = undefined;
    @memcpy(&taker, data[0..32]);
    const amount = std.mem.readInt(u64, data[32..40], .little);
    if (amount == 0) {
        sdk.logMsg("Error: Amount must be greater than 0");
        return error.InvalidInstructionData;
    }

    sdk.logMsg("Make: Validated accounts and data");
    sdk.logMsg("Make amount:");
    sdk.logU64(amount);

    const space: u64 = @sizeOf(EscrowState);
    const rent_exempt = ((space / 256) + 1) * 6960;
    const lamports = amount + rent_exempt;
    const signers_seeds = &[_][]const u8{ "escrow", &maker_key, &[_]u8{bump} };
    try sdk.system.createAccountSigned(
        maker.toAccountInfo(),
        escrow.toAccountInfo(),
        program_id,
        space,
        lamports,
        signers_seeds,
    );

    sdk.logMsg("Make: Escrow account created");

    const escrow_data = escrow.borrowMutDataUnchecked();
    if (escrow_data.len < @sizeOf(EscrowState)) {
        sdk.logMsg("Error: Escrow data too small");
        return error.AccountDataTooSmall;
    }
    const state = @as(*EscrowState, @ptrCast(@alignCast(escrow_data.ptr)));
    state.discriminator = EscrowState.DISCRIMINATOR;
    state.maker = maker_key;
    state.taker = taker;
    state.amount = amount;

    sdk.logMsg("Make: Escrow initialized successfully");
    return {};
}

fn processAccept(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Accept: Starting");
    if (context.remaining() < 3) {
        sdk.logMsg("Error: Not enough accounts for accept");
        return error.NotEnoughAccountKeys;
    }

    const taker = context.nextAccountUnchecked().assumeAccount();
    const escrow = context.nextAccountUnchecked().assumeAccount();
    const maker = context.nextAccountUnchecked().assumeAccount();
    _ = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (!taker.isSigner()) return error.MissingRequiredSignature;
    if (!taker.isWritable()) return error.ImmutableAccount;
    if (!escrow.isWritable()) return error.ImmutableAccount;
    if (!sdk.pubkeyEq(escrow.owner(), program_id)) return error.IncorrectProgramId;

    const escrow_data = escrow.borrowMutDataUnchecked();
    if (escrow_data.len < @sizeOf(EscrowState)) return error.AccountDataTooSmall;
    if (escrow_data[0] != EscrowState.DISCRIMINATOR) return error.InvalidAccountData;

    const maker_key = maker.key().*;
    const seeds = &[_][]const u8{ "escrow", &maker_key };
    var expected_escrow: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_escrow, &bump);
    if (!sdk.pubkeyEq(escrow.key(), &expected_escrow)) {
        sdk.logMsg("Error: Invalid escrow PDA");
        return error.IncorrectProgramId;
    }

    const state = @as(*EscrowState, @ptrCast(@alignCast(escrow_data.ptr)));
    const zero_pubkey: sdk.Pubkey = .{0} ** 32;
    if (!sdk.pubkeyEq(&state.taker, &zero_pubkey) and !sdk.pubkeyEq(taker.key(), &state.taker)) {
        sdk.logMsg("Error: Unauthorized taker");
        return error.IncorrectAuthority;
    }

    sdk.logMsg("Accept: Validated accounts");
    sdk.logMsg("Accept amount:");
    sdk.logU64(state.amount);
    if (state.amount == 0) {
        sdk.logMsg("Error: Escrow is empty");
        return error.InsufficientFunds;
    }

    const amount = escrow.borrowMutLamportsUnchecked().*;
    escrow.borrowMutLamportsUnchecked().* = 0;
    taker.borrowMutLamportsUnchecked().* += amount;
    if (escrow_data.len > 0) escrow_data[0] = 0;

    sdk.logMsg("Accept: Lamports transferred successfully");
    return {};
}

fn processRefund(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    sdk.logMsg("Refund: Starting");
    if (context.remaining() < 2) {
        sdk.logMsg("Error: Not enough accounts for refund");
        return error.NotEnoughAccountKeys;
    }

    const maker = context.nextAccountUnchecked().assumeAccount();
    const escrow = context.nextAccountUnchecked().assumeAccount();
    _ = context.instructionDataUnchecked();
    const program_id = context.programIdUnchecked();

    if (!maker.isSigner()) return error.MissingRequiredSignature;
    if (!maker.isWritable()) return error.ImmutableAccount;
    if (!escrow.isWritable()) return error.ImmutableAccount;
    if (!sdk.pubkeyEq(escrow.owner(), program_id)) return error.IncorrectProgramId;

    const escrow_data = escrow.borrowMutDataUnchecked();
    if (escrow_data.len < @sizeOf(EscrowState)) return error.AccountDataTooSmall;
    if (escrow_data[0] != EscrowState.DISCRIMINATOR) return error.InvalidAccountData;

    const maker_key = maker.key().*;
    const seeds = &[_][]const u8{ "escrow", &maker_key };
    var expected_escrow: sdk.Pubkey = undefined;
    var bump: u8 = undefined;
    try sdk.findProgramAddress(seeds, program_id, &expected_escrow, &bump);
    if (!sdk.pubkeyEq(escrow.key(), &expected_escrow)) {
        sdk.logMsg("Error: Invalid escrow PDA");
        return error.IncorrectProgramId;
    }

    const state = @as(*EscrowState, @ptrCast(@alignCast(escrow_data.ptr)));
    sdk.logMsg("Refund: Validated accounts");
    sdk.logMsg("Refund amount:");
    sdk.logU64(state.amount);
    if (state.amount == 0) {
        sdk.logMsg("Error: Escrow is empty");
        return error.InsufficientFunds;
    }

    const amount = escrow.borrowMutLamportsUnchecked().*;
    escrow.borrowMutLamportsUnchecked().* = 0;
    maker.borrowMutLamportsUnchecked().* += amount;
    if (escrow_data.len > 0) escrow_data[0] = 0;
    sdk.logMsg("Refund: Lamports refunded successfully");
    return {};
}
