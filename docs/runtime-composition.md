# Runtime Composition

> Current mainline: direct-SBF (`sbf-solana-none`) with the `solana-zig` fork.

This document defines the current Zignocchio runtime-composition story after the recent Pinocchio-parity work.

## Goals

Make the following explicit and reusable:

- which entrypoint style to use
- how allocator behavior is chosen
- how panic behavior is chosen
- when to use sysvar helpers instead of hand-rolled constants
- when to use fixed-buffer logging instead of many small ad hoc log syscalls

---

## 1. Recommended modes

### A. Standard program path

Use this when:

- you want the normal zero-copy `[]AccountInfo` flow
- you are not chasing the absolute lowest CU on entrypoint/account parsing
- you want the most ergonomic starting point

```zig
const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypoint(processInstruction), .{input});
}

fn processInstruction(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    _ = program_id;
    _ = accounts;
    _ = instruction_data;
    return {};
}
```

### B. Lazy / cursor-based fast path

Use this when:

- entrypoint/account parsing overhead matters
- you want Pinocchio-style lazy account traversal
- you can keep the handler on the thin `sdk.lazy` path instead of immediately rebuilding old abstractions

```zig
const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    const maybe_account = try context.nextAccount();
    _ = maybe_account;
    return {};
}
```

### C. No-allocation path

Use this when:

- you want allocation attempts to fail loudly
- you want a stronger "thin runtime-facing program" contract
- you want to manually reserve scratch memory in the Solana heap window

```zig
const std = @import("std");
const sdk = @import("sdk");

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    sdk.runtime.noStdPanic(msg, trace, ret_addr);
}

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}

fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
    _ = context;
    const scratch = sdk.NoAllocator.allocateUnchecked([128]u8, 0);
    scratch.* = [_]u8{0} ** 128;
    return {};
}
```

---

## 2. Allocator choices

### Default bump allocator

Zignocchio already exposes `sdk.BumpAllocator`.

Use this when:

- you genuinely need dynamic allocation
- the program design benefits more from ergonomics than from a hard no-allocation guarantee

### No-allocation allocator

Zignocchio now exposes:

- `sdk.runtime.NoAllocator`
- `sdk.NoAllocator`

Key APIs:

- `sdk.NoAllocator.allocateUnchecked(T, offset)`
- `sdk.NoAllocator.calculateOffset(T, offset)`
- `sdk.runtime.NoAllocator.allocator()`

Behavior:

- dynamic allocations panic immediately
- `free` is a no-op
- manual heap reservations remain available

### Recommendation

- Prefer **normal program code without dynamic allocation by convention**.
- Use `NoAllocator` when you want that rule to become an explicit contract.
- Use `BumpAllocator` only when allocation is truly intentional.

---

## 3. Panic choices

Zig does not mirror Rust's `default_panic_handler!` / `nostd_panic_handler!` macro model exactly, so Zignocchio exposes plain helper functions instead.

Current helpers:

- `sdk.runtime.defaultPanic(...)`
- `sdk.runtime.noStdPanic(...)`

Current behavior on Solana target:

- log `"** PANICKED **"`
- log the panic message
- trap

Current behavior on host target:

- trap

### Recommended program-level forwarding

```zig
const std = @import("std");
const sdk = @import("sdk");

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    sdk.runtime.noStdPanic(msg, trace, ret_addr);
}
```

### Recommendation

- For direct-SBF programs, prefer forwarding root `panic(...)` to `sdk.runtime.noStdPanic(...)` when you want explicit runtime ownership.
- If a program does not define its own root `panic(...)`, that is still valid; the helper is an opt-in composition point.

---

## 4. Sysvars

Zignocchio now exposes a formal `sdk.sysvars` family:

- `sdk.sysvars.clock`
- `sdk.sysvars.rent`
- `sdk.sysvars.instructions`
- `sdk.sysvars.fees`

### Prefer this

```zig
const rent = try sdk.sysvars.rent.Rent.get();
const minimum_balance = try rent.tryMinimumBalance(space);
```

### Avoid this where practical

```zig
const rent_exempt = ((space / 256) + 1) * 6960;
```

Reason:

- sysvar-backed code is closer to actual runtime semantics
- it avoids hard-coded approximations becoming the de facto SDK style

### Host behavior

On host targets, raw sysvar runtime loading returns `error.UnsupportedSysvar` because the runtime syscall is not available there.

This means:

- `*.get()` is correct for on-chain code
- `fromAccountInfo(...)` / `fromBytes(...)` are the better fit for host-side parsing tests

---

## 5. Logging style

Zignocchio now exposes a fixed-buffer append-style logger:

- `sdk.Logger(N)`
- `sdk.LogArgument`

Example:

```zig
var logger = sdk.Logger(96).init();
_ = logger
    .append("deposit amount=")
    .appendWithArgs(amount, &.{.{ .Precision = 9 }})
    .append(" owner=")
    .appendPubkeyHex(owner.key());
logger.log();
```

Recommendation:

- use `sdk.logMsg(...)` / `sdk.logU64(...)` for the smallest simple messages
- use `sdk.Logger(N)` when a message would otherwise take multiple log syscalls
- strip success-path logs from the hottest benchmark paths unless the log is part of the intended program UX

---

## 6. Recommended combinations

### Most ergonomic default

- `sdk.createEntrypoint(...)`
- normal zero-copy `[]AccountInfo`
- no custom panic override unless needed
- `sdk.sysvars.*` for runtime-backed values

### Performance-focused fast path

- `sdk.createLazyEntrypoint(...)`
- stay on `sdk.lazy` / raw-account access where possible
- use raw/lazy CPI helpers in hot paths
- only rebuild `AccountInfo` collections when it is worth it

### Hard no-allocation mode

- `sdk.createLazyEntrypoint(...)` or `sdk.createEntrypoint(...)`
- root `panic(...)` forwards to `sdk.runtime.noStdPanic(...)`
- use `sdk.NoAllocator.allocateUnchecked(...)` for manual scratch
- treat any dynamic allocation as a design error

---

## 7. Current limitations

These pieces are now present, but the story is still intentionally simple:

- there is not yet a single declarative Zig macro family equivalent to Pinocchio's Rust macros
- `defaultPanic` and `noStdPanic` currently share the same implementation
- `fees` support is exposed as a formal module, but runtime availability may still vary by environment
- not every existing example has been rewritten to use `sdk.sysvars.*` yet

---

## 8. Practical guidance for this repo

When adding new examples or templates:

1. start with the standard entrypoint unless there is a clear fast-path reason not to
2. use `sdk.sysvars.rent` instead of hand-rolled rent constants when practical
3. use `sdk.runtime.noStdPanic(...)` if you want explicit panic ownership
4. use `sdk.NoAllocator` only when you want a real no-allocation contract, not as cosmetic decoration

This keeps the default ergonomics simple while preserving a clear route to the thinner Pinocchio-style fast path.
