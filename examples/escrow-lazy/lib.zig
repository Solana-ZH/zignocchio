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
    bump: u8,
    amount: u64,
};

fn verifyEscrowPda(
    escrow_key: *const sdk.Pubkey,
    maker_key: *const sdk.Pubkey,
    bump: u8,
    program_id: *const sdk.Pubkey,
) sdk.ProgramResult {
    var expected_escrow: sdk.Pubkey = undefined;
    const bump_seed = [_]u8{bump};
    const seeds = &[_][]const u8{ "escrow", maker_key[0..32], bump_seed[0..] };
    try sdk.createProgramAddress(seeds, program_id, &expected_escrow);
    if (!sdk.pubkeyEq(escrow_key, &expected_escrow)) {
        sdk.logMsg("Error: Invalid escrow PDA");
        return error.IncorrectProgramId;
    }
}

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    return switch (context.remaining()) {
        2 => blk: {
            break :blk processRefund(context);
        },
        3 => blk: {
            const first = context.nextAccountUnchecked().assumeAccount();
            const second = context.nextAccountUnchecked().assumeAccount();
            const third = context.nextAccountUnchecked().assumeAccount();
            const instruction_data = context.instructionDataUnchecked();
            const program_id = context.programIdUnchecked();

            if (instruction_data.len == 0) {
                sdk.logMsg("Error: Empty instruction data");
                break :blk error.InvalidInstructionData;
            }

            break :blk switch (instruction_data[0]) {
                MAKE => blk2: {
                    break :blk2 processMake(first, second, third, program_id, instruction_data[1..]);
                },
                ACCEPT => blk2: {
                    break :blk2 processAccept(first, second, third, program_id);
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

fn processMake(
    maker: sdk.LazyAccount,
    escrow: sdk.LazyAccount,
    system_program: sdk.LazyAccount,
    program_id: *const sdk.Pubkey,
    data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("Make: Starting");

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
    const amount = @as(*align(1) const u64, @ptrCast(data.ptr + 32)).*;
    if (amount == 0) {
        sdk.logMsg("Error: Amount must be greater than 0");
        return error.InvalidInstructionData;
    }

    var make_logger = sdk.Logger(48).init();
    _ = make_logger.append("Make amount=").append(amount);
    make_logger.log();

    const space: u64 = @sizeOf(EscrowState);
    const rent = try sdk.sysvars.rent.Rent.get();
    const rent_exempt = try rent.tryMinimumBalance(space);
    const lamports = amount + rent_exempt;
    const signers_seeds = &[_][]const u8{ "escrow", &maker_key, &[_]u8{bump} };
    try sdk.system.createAccountSignedLazy(
        maker,
        escrow,
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
    state.bump = bump;
    state.amount = amount;

    sdk.logMsg("Make: Escrow initialized successfully");
    return {};
}

fn processAccept(
    taker: sdk.LazyAccount,
    escrow: sdk.LazyAccount,
    maker: sdk.LazyAccount,
    program_id: *const sdk.Pubkey,
) sdk.ProgramResult {
    if (!taker.isSigner()) return error.MissingRequiredSignature;
    if (!taker.isWritable()) return error.ImmutableAccount;
    if (!escrow.isWritable()) return error.ImmutableAccount;
    if (!sdk.pubkeyEq(escrow.owner(), program_id)) return error.IncorrectProgramId;

    const escrow_data = escrow.borrowMutDataUnchecked();
    if (escrow_data.len < @sizeOf(EscrowState)) return error.AccountDataTooSmall;
    if (escrow_data[0] != EscrowState.DISCRIMINATOR) return error.InvalidAccountData;

    const state = @as(*EscrowState, @ptrCast(@alignCast(escrow_data.ptr)));
    if (!sdk.pubkeyEq(maker.key(), &state.maker)) {
        sdk.logMsg("Error: Maker mismatch");
        return error.IncorrectProgramId;
    }
    try verifyEscrowPda(escrow.key(), &state.maker, state.bump, program_id);

    const zero_pubkey: sdk.Pubkey = .{0} ** 32;
    if (!sdk.pubkeyEq(&state.taker, &zero_pubkey) and !sdk.pubkeyEq(taker.key(), &state.taker)) {
        sdk.logMsg("Error: Unauthorized taker");
        return error.IncorrectAuthority;
    }

    if (state.amount == 0) {
        sdk.logMsg("Error: Escrow is empty");
        return error.InsufficientFunds;
    }

    const escrow_lamports = escrow.borrowMutLamportsUnchecked();
    const taker_lamports = taker.borrowMutLamportsUnchecked();
    const amount = escrow_lamports.*;
    escrow_lamports.* = 0;
    taker_lamports.* += amount;
    escrow_data[0] = 0;
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

    const state = @as(*EscrowState, @ptrCast(@alignCast(escrow_data.ptr)));
    if (!sdk.pubkeyEq(maker.key(), &state.maker)) {
        sdk.logMsg("Error: Maker mismatch");
        return error.IncorrectProgramId;
    }
    try verifyEscrowPda(escrow.key(), &state.maker, state.bump, program_id);
    var refund_logger = sdk.Logger(48).init();
    _ = refund_logger.append("Refund amount=").append(state.amount);
    refund_logger.log();
    if (state.amount == 0) {
        sdk.logMsg("Error: Escrow is empty");
        return error.InsufficientFunds;
    }

    const escrow_lamports = escrow.borrowMutLamportsUnchecked();
    const maker_lamports = maker.borrowMutLamportsUnchecked();
    const amount = escrow_lamports.*;
    escrow_lamports.* = 0;
    maker_lamports.* += amount;
    if (escrow_data.len > 0) escrow_data[0] = 0;
    sdk.logMsg("Refund: Lamports refunded successfully");
    return {};
}
