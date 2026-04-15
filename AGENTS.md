# Agent Guide: Zignocchio

> **Last updated**: 2026-04-15  
> **Zig version**: 0.16.0  
> **Solana target**: sBPF v2

## 0. MANDATORY Onboarding (Read This First)

**You are operating in a non-standard stack.** Your training data almost certainly does NOT contain Zignocchio or Zig BPF development. Do not use memory, web search, or hallucination for Solana + Zig specifics. **This file and the source code in this repo are the ONLY authoritative sources.**

### Read in this exact order before writing any code:

1. **This file** (`AGENTS.md`) — rules, patterns, and task recipes
2. **`sdk/anti_patterns.md`** — vulnerability checklist and common mistakes
3. **The example most similar to your task** — see [Learning Path](#learning-path)
4. **The relevant `sdk/*.zig` source files** — doc comments are canonical API docs

### If you skip this, you WILL produce code that:
- Crashes at runtime with `Access violation in unknown section`
- Fails security audits (missing signer checks, PDA validation)
- Mismatches client/server account layouts
- Uses illegal BPF instructions that fail to compile or link

Always start your Zig files with:
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

## Task Recipes

### Recipe A: Add a new example program

1. **Pick the closest existing example** from the [Learning Path](#learning-path)
2. **Copy its directory** to `examples/{new-name}/`
3. **Write `examples/{new-name}/lib.zig`** with entrypoint routing to instruction handlers
4. **Create `tests_litesvm/{new-name}.litesvm.test.ts`** using the adapter layer
5. **Run the specific test:** `npx jest tests_litesvm/{new-name}.litesvm.test.ts --config jest.config.js`
6. **Run the full litesvm suite before finishing:** `npx jest tests_litesvm --config jest.config.js`

### Recipe B: Add a new SDK module

1. **Create `sdk/{module}.zig`**
2. **Add doc comments to EVERY public function** — these are the API docs
3. **Add inline unit tests** at the bottom using `test "..." { ... }`
4. **Export from `sdk/zignocchio.zig`**
5. **Run `zig build test`** to verify compilation and tests
6. **Update `sdk/README.md`** with a brief description

### Recipe C: Write a litesvm integration test

1. **Import the adapter:** `import { startLitesvm, deployProgramToLitesvm, sendTransaction, getAccount, setAccount, airdrop } from '../client/src/litesvm';`
2. **Start a fresh context:** `const ctx = startLitesvm(); const svm = ctx.svm; const payer = ctx.payer;`
3. **For SPL Token tests:** use `ctx.svm.withDefaultPrograms()`
4. **Deploy:** `const programId = deployProgramToLitesvm(svm, { exampleName: 'your-example' });`
5. **Fund accounts:** `airdrop(svm, user.publicKey, 1_000_000_000n);`
6. **Pre-create 0-lamport PDAs** with `setAccount(svm, pda, { data: new Uint8Array(0), executable: false, lamports: 0n, owner: SystemProgram.programId, space: 0n });`
7. **Assert success:** `expect(result.constructor.name).toBe('TransactionMetadata')`
8. **Assert failures:** `await expect(...).rejects.toThrow()`

---

## Decision Trees

### Which example should I copy?

| Your program needs... | Copy this example |
|-----------------------|-------------------|
| Just logs / basic entrypoint | `examples/hello/` |
| Read/write custom account data | `examples/counter/` |
| Transfer SOL via System Program | `examples/transfer-sol/` |
| PDA + SOL storage | `examples/vault/` |
| PDA + arbitrary data storage per user | `examples/pda-storage/` |
| SPL Token transfers | `examples/token-vault/` |
| Multi-instruction flow with security | `examples/escrow/` |

### Which CPI helper should I use?

| Operation | Helper |
|-----------|--------|
| Transfer lamports | `sdk.system.transfer(from, to, amount)` |
| Create account | `sdk.system.createAccount(payer, new_account, owner, space, lamports)` |
| Create account with PDA signer | `sdk.system.createAccountSigned(..., signer_seeds)` |
| Token transfer | `sdk.token.transfer.transfer(from, to, authority, amount)` |
| Token transfer with PDA signer | `sdk.token.transfer.transferSigned(...)` |
| Close token account | `sdk.token.close_account.closeAccount(...)` |
| Create ATA | `sdk.token.ata.createAssociatedTokenAccount(...)` |
| Close/drain any account | `sdk.idioms.close_account(account, destination)` |

---

## Debug Playbook

| Error | Cause | Fix |
|-------|-------|-----|
| `Access violation in unknown section` | Address of module-scope constant passed to syscall/CPI | Copy to local `var` on stack first |
| `Illegal instruction` / `Illegal BPF instruction` | Aggregate returns or `.{}` struct init | Use explicit fields or output parameters |
| `unable to load 'lib.zig': FileNotFound` | Running `zig build` from wrong directory | Run from repo root |
| `Do not know how to serialize a BigInt` | Jest multi-worker + litesvm bigint | `maxWorkers: 1` (already set) |
| Program not found / wrong behavior in litesvm | Stale `.so` from different example | `build.zig` now uses per-example names; rebuild with `-Dexample=` |
| `MissingRequiredSignature` in litesvm | Signer not registered on transaction | Adapter handles this; check `sendTransaction` params |
| `IncorrectProgramId` on token account | Compared owner to module-scope constant | Use `sdk.token.getTokenProgramId(&local_var)` |
| Test expects `FailedTransactionMetadata` | Adapter now throws on failure | Use `await expect(...).rejects.toThrow()` |

---

## Pre-Submit Checklist

Before declaring any task complete, run these commands in order:

```bash
# 1. Zig compilation for the example you changed
zig build -Dexample=<name>

# 2. Zig unit tests for any SDK module you changed
zig build test

# 3. TypeScript compilation for the client package
cd client && npx tsc --noEmit && cd ..

# 4. The specific litesvm test(s) you added or modified
npx jest tests_litesvm/<name>.litesvm.test.ts --config jest.config.js

# 5. FULL litesvm test suite (mandatory)
npx jest tests_litesvm --config jest.config.js
```

**If any of these fail, the task is NOT complete.**

---

## Naming and Structure Conventions

### Zig files
- Entrypoint: `lib.zig`
- Instruction handlers: `{instruction_name}.zig`
- Discriminators: `pub const DISCRIMINATOR: u8 = N;`
- Account validation structs: `{Instruction}Accounts`
- Data parsing structs: `{Instruction}Data`

### TypeScript tests
- litesvm tests: `tests_litesvm/{example_name}.litesvm.test.ts`
- Do NOT put litesvm tests in `examples/`

### Commits
- Use conventional commits: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`
- Include scope: `feat(sdk): add assert_executable guard`

---

## Testing with litesvm

All integration tests have been migrated from `surfpool` to `litesvm` for speed and reliability. When writing or modifying tests, follow these patterns.

### Test File Location
- litesvm tests: `tests_litesvm/{example}.litesvm.test.ts`
- surfpool tests: `examples/{example}.test.ts` (legacy, kept as fallback)

### Basic litesvm Test Structure

```typescript
import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  getAccount,
  setAccount,
  airdrop,
} from '../client/src/litesvm';
import { Keypair, TransactionInstruction } from '@solana/web3.js';

describe('litesvm my-example', () => {
  let programId: ReturnType<typeof deployProgramToLitesvm>;
  let payer: Keypair;
  let svm: ReturnType<typeof startLitesvm>['svm'];

  beforeAll(() => {
    const ctx = startLitesvm();
    svm = ctx.svm;
    payer = ctx.payer;
    programId = deployProgramToLitesvm(svm, { exampleName: 'my-example' });
  });

  it('should do something', async () => {
    const ix = new TransactionInstruction({
      keys: [
        { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      ],
      programId,
      data: Buffer.from([0]),
    });

    const result = await sendTransaction(svm, payer, [ix]);
    expect(result.constructor.name).toBe('TransactionMetadata');
  });
});
```

### Critical litesvm Rules

#### Rule A: Always build the correct example before testing
`build.zig` outputs per-example `.so` files to `zig-out/lib/{example_name}.so`. `deployProgramToLitesvm` automatically runs `zig build -Dexample={name}` for you, but if you ever test a manually compiled `.so`, make sure it matches the example.

#### Rule B: Jest must run with `maxWorkers: 1`
litesvm returns `BigInt` values in account data, which crash Jest's worker IPC serialization. This is already configured in `jest.config.js`.

#### Rule C: Pre-create PDAs that start at 0 lamports
Unlike surfpool, litesvm does **not** auto-create zero-lamport accounts referenced in transactions. If your instruction references a PDA that doesn't exist yet, pre-create it:

```typescript
setAccount(svm, pdaPubkey, {
  data: new Uint8Array(0),
  executable: false,
  lamports: 0n,
  owner: SystemProgram.programId,
  space: 0n,
});
```

#### Rule D: Closed accounts are deleted
After a CPI closes an account (balance goes to 0), litesvm deletes the account. `getAccount(svm, pubkey)` returns `undefined`:

```typescript
const lamports = getAccount(svm, escrow)?.lamports ?? 0n;
```

#### Rule E: Failed transactions throw
The `sendTransaction` adapter in `client/src/litesvm.ts` detects `FailedTransactionMetadata` and throws. Use `rejects.toThrow()` for failure cases:

```typescript
await expect(sendTransaction(svm, payer, [badIx])).rejects.toThrow();
```

#### Rule F: SPL Token tests need `withDefaultPrograms()`
If your test uses SPL Token, load the token program first:

```typescript
const svm = new LiteSVM();
svm.withDefaultPrograms(); // loads Token program
```

### Account Role Mapping (for manual kit instructions)

If you construct `@solana/kit` instructions manually, the `role` field maps as:

| `role` | `isSigner` | `isWritable` |
|--------|------------|--------------|
| 0 | false | false |
| 1 | false | true |
| 2 | true | false |
| 3 | true | true |

## Project File Map

| Path | What it is | When to read/edit |
|------|------------|-------------------|
| `sdk/zignocchio.zig` | Main SDK entrypoint | Read first to understand the public API |
| `sdk/guard.zig` | Security assertion helpers | Read before writing instruction handlers; extend if adding new guards |
| `sdk/schema.zig` | `AccountSchema` comptime interface | Read when you need typed account data |
| `sdk/system.zig` | System Program CPI wrappers | Read when doing lamport transfers or account creation |
| `sdk/token/` | SPL Token Program CPI wrappers | Read when doing anything with tokens |
| `sdk/idioms.zig` | Common patterns | Read before inventing your own helper |
| `sdk/anti_patterns.md` | Vulnerability checklist | **Read before EVERY instruction handler** |
| `examples/hello/lib.zig` | Minimal entrypoint | Starting point for simple programs |
| `examples/counter/lib.zig` | Account data access | Starting point for stateful programs |
| `examples/transfer-sol/` | System Program CPI | Starting point for SOL transfers |
| `examples/vault/` | PDA + System CPI | Starting point for PDA-based programs |
| `examples/pda-storage/` | PDA validation + storage | Starting point for user-scoped PDAs |
| `examples/token-vault/` | SPL Token CPI + PDA signing | Starting point for token programs |
| `examples/escrow/` | Multi-instruction flow | Most complex reference example |
| `client/src/litesvm.ts` | litesvm test adapter | Read when writing litesvm tests |
| `tests_litesvm/` | litesvm integration tests | Add new tests here |
| `build.zig` | Per-example build outputs | Modify if build artifacts change |
| `docs/` | PRD, architecture, specs | Read for context, not API details |

## When to Ask for Help

Stop and ask the human before proceeding if you encounter:
- A new syscall needs to be added to `sdk/syscalls.zig`
- The `build.zig` build logic needs structural changes
- You need to add a new external dependency (we are **zero-dependency**)
- A test passes in isolation but fails in the full suite
- You are unsure whether a security pattern is correct
- You need to change the litesvm adapter (`client/src/litesvm.ts`) fundamentally

## Questions?

Read the doc comments in `sdk/*.zig` files. They are the authoritative source of truth. For test patterns, copy the nearest `tests_litesvm/*.litesvm.test.ts`.
