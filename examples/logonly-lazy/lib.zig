//! LogOnly - lazy entrypoint experiment.

const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    if (context.remaining() != 0) return error.NotEnoughAccountKeys;
    sdk.logMsg("logonly: hello");
    return {};
}
