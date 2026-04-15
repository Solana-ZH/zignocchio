# Agent Guide: Zignocchio

> **Last updated**: 2026-04-15  
> **Zig version**: 0.16.0  
> **Solana target**: sBPF v2

## Before You Start

Your training data likely **does not contain** Zignocchio or Zig BPF development. Do not rely on memory or web search for Solana + Zig specifics—**this SDK's source code is the canonical reference**.

Always start with:
```zig
const sdk = @import("sdk/zignocchio.zig");
```

## Quick Checklist for Every Instruction

Before processing any state-mutating instruction, verify these guards in order:

1. **`sdk.guard.assert_signer(...)`** — Is the authority account a signer?
2. **`sdk.guard.assert_writable(...)`** — Can this account be mutated?
3. **`sdk.guard.assert_immutable(...)`** — Should this account remain unchanged?
4. **`sdk.guard.assert_owner(..., program_id)`** — Is the account owned by this program?
5. **`sdk.guard.assert_pda(..., seeds, program_id, bump)`** — Is the PDA address correctly derived?
6. **`sdk.guard.assert_discriminator(data, expected)`** — Does the account data start with the expected type marker?
7. **`sdk.guard.assert_initialized(data)`** — Has the account already been initialized?
8. **`sdk.guard.assert_uninitialized(data)`** — Is the account safe to initialize?
9. **`sdk.guard.assert_min_data_len(account, len)`** — Is the account data large enough for the expected struct?
10. **`sdk.guard.assert_rent_exempt(lamports, data_len)`** — Does the account have enough lamports to be rent exempt?
11. **`sdk.guard.assert_program_id(actual, expected)`** — Is the program ID what we expect?
12. **`sdk.guard.assert_executable(account)`** — Is this account a valid program?
13. **`sdk.guard.assert_keys_not_equal(a, b)`** — Are these two accounts distinct?

## Essential Rules

### Rule 1: Never take the address of a module-scope constant
Zig 0.16's BPF backend places module-scope `const` arrays at invalid low addresses. **Always copy to a local variable first**:

```zig
// ❌ DANGEROUS - may crash with "Access violation in unknown section"
// const SYSTEM_PROGRAM_ID: Pubkey = .{0} ** 32;
// if (!sdk.pubkeyEq(account.owner(), &SYSTEM_PROGRAM_ID)) { ... }

// ✅ SAFE - stack copy
var system_program_id: sdk.Pubkey = .{0} ** 32;
if (!sdk.pubkeyEq(account.owner(), &system_program_id)) { ... }
```

### Rule 2: Use `AccountSchema` for all typed account data
Never cast raw bytes without first validating the discriminator:

```zig
const MyAccount = extern struct {
    pub const DISCRIMINATOR: u8 = 0xAB;
    discriminator: u8,
    value: u64,
};

const Schema = sdk.schema.AccountSchema(MyAccount);
try Schema.validate(account);

var ref: sdk.RefMut([]u8) = undefined;
try Schema.from_bytes(account, &ref);
defer ref.release();

var typed = Schema.from_bytes_unchecked(ref.value);
typed.value = 42;
```

### Rule 3: Always release borrows before CPI
If you hold a `RefMut` or `Ref`, release it before calling `sdk.invoke` or `sdk.invokeSigned`:

```zig
var data = try account.tryBorrowMutData();
data.value[0] = 1;
data.release(); // ✅ release before CPI

try sdk.invoke(&instruction, accounts);
```

### Rule 4: sBPF does not support aggregate returns
Functions cannot return structs. Use output parameters instead:

```zig
// ❌ Not supported on sBPF
pub fn findPda(...) !struct { Pubkey, u8 }

// ✅ Use output parameters
pub fn findProgramAddress(seeds, program_id, out_address: *Pubkey, out_bump: *u8) !void
```

### Rule 5: Inline string data to avoid .rodata stripping
Do not rely on string literals in .rodata. Inline them as arrays:

```zig
// ❌ May be stripped by sbpf-linker
// sdk.logMsg("Hello");

// ✅ Inline array (if you need to avoid .rodata issues)
const msg = [_]u8{'H','e','l','l','o'};
sdk.logMsg(&msg);
```

## When to Use What

| Operation | Use This |
|-----------|----------|
| Signer check | `sdk.guard.assert_signer(account)` |
| Writable check | `sdk.guard.assert_writable(account)` |
| Immutable check | `sdk.guard.assert_immutable(account)` |
| Owner check | `sdk.guard.assert_owner(account, program_id)` |
| PDA verification | `sdk.guard.assert_pda(account, seeds, program_id, bump)` |
| Type validation | `sdk.AccountSchema(T).validate(account)` |
| Safe deserialize | `sdk.AccountSchema(T).from_bytes(account)` |
| Initialized check | `sdk.guard.assert_initialized(data)` |
| Uninitialized check | `sdk.guard.assert_uninitialized(data)` |
| Min data length | `sdk.guard.assert_min_data_len(account, len)` |
| Keys not equal | `sdk.guard.assert_keys_not_equal(a, b)` |
| Program ID check | `sdk.guard.assert_program_id(actual, expected)` |
| Executable check | `sdk.guard.assert_executable(account)` |
| Transfer lamports (CPI) | `sdk.system.transfer(from, to, amount)` |
| Create account (CPI) | `sdk.system.createAccount(payer, new_account, owner, space, lamports)` |
| Create account with PDA signing | `sdk.system.createAccountSigned(payer, new_account, owner, space, lamports, signers_seeds)` |
| Token transfer | `sdk.token.transfer.transfer(from, to, authority, amount)` |
| Token transfer with PDA signing | `sdk.token.transfer.transferSigned(from, to, authority, amount, signers_seeds)` |
| Close token account | `sdk.token.close_account.closeAccount(account, destination, authority)` |
| Create Associated Token Account | `sdk.token.ata.createAssociatedTokenAccount(payer, ata, owner, mint, system_program, token_program)` |
| Close/drain account | `sdk.idioms.close_account(account, destination)` |
| Read u64 from data | `sdk.idioms.read_u64_le(data, offset)` |
| Write u64 to data | `sdk.idioms.write_u64_le(data, offset, value)` |
| Scaffold new program | `zignocchio-cli new <name> [--path <dir>]` |

## Common Mistakes to Avoid

See [`sdk/anti_patterns.md`](sdk/anti_patterns.md) for the full vulnerability checklist.

## Learning Path

Study the examples in this order:

1. **`examples/hello/lib.zig`** — Entrypoint and logging
2. **`examples/counter/lib.zig`** — Account data access and mutation
3. **`examples/vault/`** — PDAs, CPI, and complex instruction routing
4. **`examples/escrow/`** — PDAs, System Program CPI, security guards, and account closing in a real-world escrow flow
5. **`examples/token-vault/`** — Token Program CPI

## If Something Doesn't Compile

1. Check that you are using **Zig 0.16.0**
2. Check that your struct is `extern struct` or `packed struct` (not auto layout)
3. Check that you copied Program IDs to local variables before taking their address
4. Check that all `try` calls are inside a function that returns `sdk.ProgramResult`
5. Run `zig build` to see the exact error with line numbers

## Questions?

Read the doc comments in `sdk/*.zig` files. They are the authoritative source of truth.
