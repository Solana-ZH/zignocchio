# Zignocchio

Build Solana programs in Zig with the `solana-zig` fork and a direct sBPF pipeline.

## Status

- **Primary build path:** direct `sbf-solana-none`
- **Required compiler:** `solana-zig` fork
- **Default artifact path:** `zig-out/lib/{example}.so`
- **Default SBF CPU:** `baseline`

This repository no longer uses `elf2sbpf` or `sbpf-linker` as active build backends.
Historical comparison data is kept in [`docs/backend-comparison.md`](docs/backend-comparison.md), the current direct-SBF CU snapshot is summarized in [`docs/cu-summary.md`](docs/cu-summary.md), a Pinocchio parity / gap analysis is tracked in [`docs/pinocchio-gap-analysis.md`](docs/pinocchio-gap-analysis.md), and the current allocator / panic / entrypoint recipes live in [`docs/runtime-composition.md`](docs/runtime-composition.md).

## Prerequisites

```bash
# solana-zig fork binary
export SOLANA_ZIG=/path/to/solana-zig-bootstrap/out/host/bin/zig

# Node.js for Jest / TS integration tests
npm install
```

You can also use `ZIG=/path/to/fork/zig` if you prefer.

## Building

```bash
# Build the default example
SOLANA_ZIG=/path/to/fork/zig bash tools/with-solana-zig.sh build

# Build a specific example directly with the fork compiler
"$SOLANA_ZIG" build -Dexample=hello

# Or invoke through the helper so the fork is always selected
SOLANA_ZIG=/path/to/fork/zig bash tools/with-solana-zig.sh build -Dexample=hello
```

Examples currently included:

- `hello`
- `counter`
- `transfer-sol`
- `pda-storage`
- `vault`
- `token-vault`
- `escrow`
- `noop`
- `logonly`

## Build options

```bash
# Override SBF CPU model
"$SOLANA_ZIG" build -Dexample=hello -Dsbf-cpu=baseline
"$SOLANA_ZIG" build -Dexample=hello -Dsbf-cpu=v1
"$SOLANA_ZIG" build -Dexample=hello -Dsbf-cpu=v2
```

Supported CPU values:

- `baseline` (default)
- `generic`
- `v1`
- `v2`
- `v3`

`v2+` requires a runtime with the corresponding SBF feature gates enabled.
For maximum harness compatibility, this repo defaults to `baseline`.

## Testing

```bash
# All direct-SBF CI checks
SOLANA_ZIG=/path/to/fork/zig bash tools/ci-fork-sbf.sh

# Individual groups
npm run test:examples:litesvm
npm run test:client
npm run test:rust
npm run test:agave
npm run test:examples:surfpool
```

`tools/ci-fork-sbf.sh` runs:

- example builds
- Zig unit tests
- LiteSVM example tests
- client tests
- Rust Mollusk tests
- Agave `program-test` tests
- surfpool tests when available in `PATH`

## How the build works

The build is now a direct native SBF build:

1. `build.zig` resolves `sbf-solana-none`
2. the program is compiled with the fork Zig toolchain
3. a custom `bpf.ld` linker script strips unsupported sections
4. the final shared object is installed to `zig-out/lib/{example}.so`

## Syscalls

Syscalls are generated from [`tools/syscall_defs.zig`](tools/syscall_defs.zig) by [`tools/gen_syscalls.zig`](tools/gen_syscalls.zig).

Important detail: generated bindings are now emitted as **`extern fn` syscall declarations**, not magic function-pointer hashes. The MurmurHash3 values are still kept in comments for reference, but the linker now emits Solana-compatible syscall relocations such as `sol_log_`.

Generate bindings with:

```bash
zig run tools/gen_syscalls.zig -- sdk/syscalls.zig
```

## Zignocchio SDK

This repo includes **Zignocchio**, a Zig SDK for Solana programs with:

- zero-copy input deserialization
- typed `AccountInfo` access
- PDA helpers
- CPI helpers
- guard helpers
- schema helpers
- lazy entrypoint helpers
- formal sysvar helpers (`clock`, `rent`, `instructions`, `fees`)
- runtime composition helpers (`sdk.runtime`, `sdk.NoAllocator`)
- fixed-buffer logging ergonomics (`sdk.Logger`, `sdk.LogArgument`)
- SPL Token helpers

See:

- [`sdk/zignocchio.zig`](sdk/zignocchio.zig)
- [`docs/runtime-composition.md`](docs/runtime-composition.md)
- [`AGENTS.md`](AGENTS.md)
- [`examples/`](examples/)

## Runtime composition modes

Zignocchio now exposes explicit runtime composition points instead of treating allocator / panic behavior as implicit glue.

### 1. Standard zero-copy entrypoint

```zig
const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypoint(processInstruction), .{input});
}
```

### 2. Lazy / cursor-based entrypoint

```zig
const sdk = @import("sdk");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
}
```

### 3. No-allocation path with explicit panic forwarding

```zig
const std = @import("std");
const sdk = @import("sdk");

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    sdk.runtime.noStdPanic(msg, trace, ret_addr);
}

fn useScratch() void {
    const scratch = sdk.NoAllocator.allocateUnchecked([64]u8, 0);
    scratch.* = [_]u8{0} ** 64;
}
```

### 4. Formal sysvars

```zig
const rent = try sdk.sysvars.rent.Rent.get();
const minimum_balance = try rent.tryMinimumBalance(space);
const clock = try sdk.sysvars.clock.Clock.get();
_ = clock;
```

### 5. Fixed-buffer logger

```zig
var logger = sdk.Logger(64).init();
_ = logger.append("amount=").appendWithArgs(amount, &.{.{ .Precision = 9 }});
logger.log();
```

For the fuller standard / lazy / no-allocation recipes, see [`docs/runtime-composition.md`](docs/runtime-composition.md).

## Historical backend/CU summary

The old two-backend comparison is preserved for reference in [`docs/backend-comparison.md`](docs/backend-comparison.md).
High-level takeaways from that work:

- inside this repo's old artifact comparison, **`fork-sbf` usually produced smaller `.so` files**
- in the old comparison script, **`fork-sbf` was usually slightly faster to build**
- in cross-project runtime tests (`solana-program-rosetta`), **direct SBF Zig generally beat Zig `sbpf-linker` on meaningful CU cases**
- **Pinocchio/Rust was still strongest** on the tested `transfer-lamports` and `cpi` workloads

Those numbers were useful for deciding the build direction, but the repo now treats direct SBF as the mainline path.

## Project structure

```text
.
├── build.zig              # Direct-SBF build pipeline
├── sdk/                   # Zignocchio SDK
├── examples/              # Example programs
├── client/                # TS helpers and adapters
├── tests_rust/            # Mollusk / CU probes
├── tests_agave/           # Agave program-test coverage
├── tools/                 # Build and codegen helpers
└── docs/                  # Architecture and historical notes
```

## License

MIT
