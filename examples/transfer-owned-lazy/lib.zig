//! Transfer Owned Lazy - experimental benchmark using Zignocchio's lazy cursor.
//!
//! This variant uses `sdk.lazy.EntryContext` to more closely match Pinocchio's
//! cursor-based account access pattern and isolate entrypoint/account-loading
//! overhead from the actual transfer logic.

const sdk = @import("sdk");

const EntryContext = sdk.lazy.EntryContext;

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *EntryContext) sdk.ProgramResult {
    if (context.remaining() != 2) return error.NotEnoughAccountKeys;

    const source = context.nextAccountUnchecked().assumeAccount();
    const destination_maybe = context.nextAccountUnchecked();
    const instruction_data = context.instructionDataUnchecked();
    const amount = @as(*align(1) const u64, @ptrCast(instruction_data.ptr)).*;
    if (destination_maybe == .Account) {
        const destination = destination_maybe.Account;
        source.borrowMutLamportsUnchecked().* -= amount;
        destination.borrowMutLamportsUnchecked().* += amount;
    }
    return {};
}
