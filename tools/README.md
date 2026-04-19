# Syscall Generator Tools

This directory contains tools for generating Solana syscall bindings for Zig.

## Files

- **murmur3.zig** - MurmurHash3-32 implementation (matches Solana's syscall hash function)
- **syscall_defs.zig** - Syscall definitions with signatures
- **gen_syscalls.zig** - Generator that creates `sdk/syscalls.zig`

## Usage

Generate the syscalls file:

```bash
zig run tools/gen_syscalls.zig -- sdk/syscalls.zig
```

This creates `sdk/syscalls.zig` with Solana syscalls declared as `extern fn` bindings.

## How It Works

1. Each syscall definition is described in `syscall_defs.zig`
2. The generator emits an `extern fn ... callconv(.c)` declaration for linker-compatible Solana syscall relocations
3. The MurmurHash3-32 value is still computed and kept in comments for reference/debugging

## Testing

Test the MurmurHash implementation:

```bash
cd tools && zig test murmur3.zig
```

This verifies that `"sol_log_"` hashes to `0x207559bd`.

## Adding New Syscalls

To add syscalls, edit `syscall_defs.zig` and add a new entry to the `syscalls` array:

```zig
.{
    .name = "sol_new_syscall",
    .signature = "fn(u64, [*]const u8) u64",
    .params = &[_]Param{
        .{ .name = "arg1", .type = "u64" },
        .{ .name = "arg2", .type = "[*]const u8" },
    },
    .return_type = "u64",
},
```

Then regenerate `sdk/syscalls.zig`.
