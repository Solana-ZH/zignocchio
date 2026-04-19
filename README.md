# Solana BPF Programs with Zig

Build Solana programs in Zig using one of two back-ends:

| Backend | Compiler | Pipeline | Zig version | CU / size |
|---------|----------|----------|-------------|-----------|
| **`elf2sbpf`** (default) | stock Zig 0.16 | bitcode → bpfel → [elf2sbpf][e2] | any 0.16 | worse than baseline (no CU optimizer) |
| **`fork-sbf`** (opt-in) | [solana-zig fork][fork] | direct `sbf-solana` native build | 0.16.0-dev.0+cf5f8113c | best (matches solana-zig v1.52 baseline) |

[e2]: https://github.com/DaviRain-Su/elf2sbpf
[fork]: https://github.com/DaviRain-Su/solana-zig-bootstrap/tree/solana-1.52-zig0.16

Select with `-Dbackend=elf2sbpf` (default) or `-Dbackend=fork-sbf`.

## Features

- ✅ Uses standard Zig BPF target (no custom forks)
- ✅ Zero external dependencies for the default (elf2sbpf) build
- ✅ **Zignocchio SDK** - Full-featured Zig SDK for Solana
- ✅ LLVM bitcode generation via `-femit-llvm-bc`
- ✅ Direct syscall invocation via function pointers
- ✅ Auto-generated syscall bindings with MurmurHash3
- ✅ Automated build pipeline with `zig build`
- ✅ Jest-based integration tests with solana-test-validator

## Prerequisites

**elf2sbpf build pipeline (required):**

```bash
# Install Zig 0.16.0 or later
# (get it from https://ziglang.org/download/)

# Install elf2sbpf (pure Zig, no Rust toolchain needed)
git clone https://github.com/DaviRain-Su/elf2sbpf && cd elf2sbpf
zig build -p ~/.local
export PATH="$HOME/.local/bin:$PATH"
cd ..

# Or, if elf2sbpf is cloned next to this repo, use it in place:
export PATH="$(cd ../elf2sbpf/zig-out/bin && pwd):$PATH"

# Install Node.js for testing
```

That's it — no Rust toolchain, no `cargo install`, no `libLLVM.so`
symlink, and no `LD_LIBRARY_PATH` juggling.

## Building

```bash
# Build an example
zig build -Dexample=hello

# Point to a non-PATH elf2sbpf binary
zig build -Dexample=hello -Delf2sbpf-bin=/path/to/elf2sbpf

# If elf2sbpf is checked out in the parent directory
zig build -Dexample=hello -Delf2sbpf-bin=../elf2sbpf/zig-out/bin/elf2sbpf
```

This generates:
1. `entrypoint.bc` - LLVM bitcode from Zig source
2. `zig-out/lib/{example}.o` - BPF ELF (elf2sbpf back-end only;
   intermediate that `elf2sbpf` consumes)
3. `zig-out/lib/{example}.so` - Final Solana program

## fork-sbf backend (opt-in)

If you have the [solana-zig fork][fork] installed, pass
`-Dbackend=fork-sbf` to the solana-zig fork Zig binary to skip the
`zig cc` + `elf2sbpf` pipeline entirely. The fork's built-in LLVM SBF
target produces `.so` in one step:

```bash
SOLANA_ZIG=/path/to/solana-zig-bootstrap/out-smoke/host/bin/zig
"$SOLANA_ZIG" build -Dexample=escrow -Dbackend=fork-sbf
```

Optional `-Dsbf-cpu=generic|v1|v2|v3` (default `v2`) selects the SBF
feature set. Note: `v2+` uses the SBF-specific opcode encoding
(`mem_encoding`, `no_lddw`, etc.), which requires an Agave 4.x+ runtime
with SBF feature gates enabled — the default `mollusk-svm 0.12.1-agave-4.0`
loader in `tests_rust/` does not yet configure these, so fork-sbf output
cannot currently be executed through the local mollusk integration tests.
Rosetta (which uses `solana-program-test`) runs fork-sbf programs fine.

### `.so` size comparison (bytes)

Measured on the 9 built-in examples:

| example         | elf2sbpf | fork-sbf v2 |
|-----------------|---------:|------------:|
| hello           |    1 192 |       1 408 |
| noop            |      304 |       1 128 |
| logonly         |    1 184 |       1 408 |
| counter         |    3 344 |       3 352 |
| transfer-sol    |    4 384 |       3 760 |
| pda-storage     |    8 728 |       5 920 |
| vault           |   12 256 |       8 024 |
| escrow          |   18 616 |       9 752 |
| token-vault     |   20 496 |      10 720 |

### CU consumption comparison (mollusk-svm)

Per the integration tests in `tests_rust/examples/`, measured via
`eprintln!("[CU] ...")` right after `mollusk.process_instruction`:

| test                                       | elf2sbpf | fork-sbf v2 |
|--------------------------------------------|---------:|------------:|
| hello                                      |      107 |           * |
| counter (increment)                        |      969 |           * |
| escrow (make_and_accept)                   |    8 053 |           * |
| escrow (make_and_refund)                   |   17 053 |           * |
| escrow (accept_by_unauthorized)            |    8 053 |           * |
| pda_storage (init_and_update)              |    4 730 |           * |
| pda_storage (wrong_signer_fails)           |    6 230 |           * |
| transfer_sol (happy)                       |    3 013 |           * |
| vault (deposit_happy)                      |    6 669 |           * |

`*` = fork-sbf programs cannot currently be loaded by mollusk-svm
0.12.1-agave-4.0's default `BPFLoaderUpgradeable` — SBF v2 opcodes
fail verification (`RelativeJumpOutOfBounds`). Solana-program-rosetta's
`solana-program-test` harness does load them successfully; see that
repo's README for fork-sbf CU numbers (they match the `solana-zig`
official v1.52.0 baseline within ±0 CU).

> An opt-in `--peephole` pass existed in earlier elf2sbpf and was
> explored here for CU optimization. It was rolled back upstream
> 2026-04-19 after exposing a miscompile on escrow's control flow
> (`Access violation at 0xfffffffffffffe98`). The column is removed
> from this README; the current elf2sbpf only offers the default
> byte-equivalent path.

### Key takeaways

- **Trivially small programs** (`hello`, `noop`, `logonly`): fork-sbf's
  `.so` is ~1.1 KB larger due to SBF v2 metadata floor.
- **Medium programs** (`counter`, `transfer-sol`): roughly break-even
  on size; CU mostly unchanged.
- **Heavy Pubkey-manipulating programs** (`pda-storage`, `vault`,
  `escrow`, `token-vault`): **fork-sbf wins 30–50 % on size** because
  the SBF LLVM backend emits unaligned u64 loads/stores as single
  instructions (`mem_encoding`) and folds syscalls via `static_syscalls`.
- **For optimal CU, use the fork-sbf backend** — elf2sbpf is the
  zero-dependency path for stock Zig users who can't install the fork.

## Testing

```bash
npm install
npm test
```

Tests will:
- Build the program
- Start solana-test-validator
- Deploy the program
- Execute and verify "Hello world!" log output

## How It Works

### 1. Auto-Generated Syscall Bindings

All Solana syscalls are auto-generated from definitions using MurmurHash3-32:

```bash
zig run tools/gen_syscalls.zig -- src/syscalls.zig
```

This creates function pointers for all syscalls:

```zig
const syscalls = @import("syscalls.zig");
syscalls.log(&message);  // Calls sol_log_ with hash 0x207559bd
```

The hash `0x207559bd` is computed as `murmur3_32("sol_log_", 0)` and
resolved by the Solana VM at runtime via `call -0x1`.

### 2. Inline String Data

To avoid back-end-specific rodata stripping quirks, string data is
inlined as byte arrays:

```zig
const message = [_]u8{'H','e','l','l','o',' ','w','o','r','l','d','!'};
```

### 3. Build Pipeline

Three stages, pure Zig + `elf2sbpf`:

```bash
# 1. Zig → LLVM bitcode
zig build-lib -target bpfel-freestanding -femit-llvm-bc=entrypoint.bc

# 2. zig cc → BPF ELF (LLVM honors Solana's 4KB stack)
zig cc -target bpfel-freestanding -mcpu=v2 -O2 \
       -mllvm -bpf-stack-size=4096 \
       -c entrypoint.bc -o entrypoint.o

# 3. elf2sbpf → Solana SBPF .so
elf2sbpf entrypoint.o program.so
```


## Zignocchio SDK

This project includes **Zignocchio**, a zero-dependency SDK for building Solana programs in Zig, inspired by [Pinocchio](https://github.com/anza-xyz/pinocchio).

### Quick Example

```zig
const sdk = @import("sdk/zignocchio.zig");

export fn entrypoint(input: [*]u8) u64 {
    return @call(.always_inline, sdk.createEntrypoint(processInstruction), .{input});
}

fn processInstruction(
    program_id: *const sdk.Pubkey,
    accounts: []sdk.AccountInfo,
    instruction_data: []const u8,
) sdk.ProgramResult {
    sdk.logMsg("Hello from Zignocchio!");

    const account = accounts[0];
    var data = try account.tryBorrowMutData();
    defer data.release();

    data.value[0] = 42;

    return .{};
}
```

### SDK Features

- **Zero-copy input deserialization** - Direct memory access to Solana's input buffer
- **RAII borrow tracking** - Safe mutable access with automatic cleanup
- **Type-safe API** - Strong typing for all Solana primitives
- **PDAs** - Program Derived Address functions
- **CPI** - Cross-program invocation support
- **Efficient** - Bit-packed borrow state, optimized syscalls

See [`sdk/README.md`](sdk/README.md) for complete documentation and [`examples/`](examples/) for working programs.

## Project Structure

```
.
├── build.zig              # Automated elf2sbpf-based build pipeline
├── build.zig.zon          # Zero dependencies
├── sdk/                   # Zignocchio SDK
│   ├── zignocchio.zig     # Main SDK module
│   ├── types.zig          # Core types (Pubkey, AccountInfo)
│   ├── entrypoint.zig     # Input deserialization
│   ├── syscalls.zig       # Auto-generated syscalls
│   ├── pda.zig            # Program Derived Addresses
│   ├── cpi.zig            # Cross-program invocation
│   ├── allocator.zig      # BumpAllocator
│   ├── log.zig            # Logging utilities
│   └── errors.zig         # Error types
├── examples/              # Example programs
│   ├── hello.zig          # Minimal example (default build target)
│   ├── counter.zig        # Full-featured example
│   ├── hello.test.ts      # Tests for hello program
│   ├── counter.test.ts    # Tests for counter program
│   └── README.md          # Examples documentation
└── tools/
    ├── murmur3.zig        # MurmurHash3-32 implementation
    ├── syscall_defs.zig   # Syscall definitions
    └── gen_syscalls.zig   # Syscall generator
```

## License

MIT
