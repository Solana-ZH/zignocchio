# Solana BPF Programs with Zig

Build Solana programs in Zig using the standard BPF target and an
**[elf2sbpf](https://github.com/DaviRain-Su/elf2sbpf)**-based build
pipeline. The toolchain stays simple: Zig emits LLVM bitcode, `zig cc`
produces a BPF ELF object with Solana's 4 KB stack limit, and
`elf2sbpf` converts that object into the final Solana SBPF program.

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
```

This generates:
1. `entrypoint.bc` - LLVM bitcode from Zig source
2. `zig-out/lib/{example}.o` - BPF ELF (elf2sbpf back-end only;
   intermediate that `elf2sbpf` consumes)
3. `zig-out/lib/{example}.so` - Final Solana program

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
