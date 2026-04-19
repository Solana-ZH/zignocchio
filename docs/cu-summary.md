# CU Summary

> Current mainline build path: direct SBF via the `solana-zig` fork.
> Harnesses differ, so compare numbers **within the same harness and scenario**.

## 1. Current repository examples (direct-SBF, current mainline)

### 1.1 Mollusk CU probes

Measured with `tests_rust/bin/cu_probe.rs` against the current `zig-out/lib/*.so` artifacts.

| example | scenario | CU | harness |
|---|---|---:|---|
| hello | hello | 105 | mollusk |
| counter | increment | 970 | mollusk |
| transfer-sol | transfer | 2,929 | mollusk |
| pda-storage | init | 4,473 | mollusk |
| pda-storage | update | 2,678 | mollusk |
| vault | deposit | 9,480 | mollusk |
| escrow | make | 7,317 | mollusk |
| escrow | accept | 3,597 | mollusk |
| escrow | refund | 3,176 | mollusk |

Command used:

```bash
for ex in hello counter transfer-sol pda-storage vault escrow; do
  cargo run --manifest-path tests_rust/Cargo.toml --bin cu_probe -- \
    --example "$ex" --artifact "zig-out/lib/$ex.so"
done
```

### 1.2 Agave `program-test` representative CU

Used for examples that do not yet have a dedicated Mollusk CU probe, or where Agave behavior is the more interesting compatibility signal.

| example | scenario | CU | harness |
|---|---|---:|---|
| token-vault | initialize | 9,651 | agave |
| token-vault | deposit | 7,475 | agave |
| token-vault | withdraw | 7,857 | agave |
| noop | execute | 2 | agave |
| logonly | execute | 105 | agave |

Command used:

```bash
cd tests_agave
BPF_OUT_DIR=../zig-out/lib cargo test \
  --test token_vault_agave \
  --test noop_agave \
  --test logonly_agave \
  -- --nocapture
```

## 2. Historical apples-to-apples runtime comparisons (`solana-program-rosetta`)

These numbers are the most useful cross-language reference points because the scenarios are intentionally matched across implementations.

| workload | Rust official | Zig fork direct-SBF | Zig `sbpf-linker` | Rust Pinocchio | notes |
|---|---:|---:|---:|---:|---|
| helloworld | 105 | 105 | 103 | n/a | `sbpf-linker` log output was suspiciously empty |
| transfer-lamports | 493 | 37 | 58 | 27 | best clean Zig-vs-Pinocchio microbenchmark |
| pubkey | 14 | 15 | 187 | n/a | Zig fork tracks Rust closely; `sbpf-linker` regressed badly |
| cpi | 3,753 | 2,967 | failed | 2,771 | `sbpf-linker` hit `Access violation in input section` |

## 3. Practical conclusions

### 3.1 What the current repo numbers say

- The direct-SBF path is now stable across:
  - LiteSVM
  - client adapter tests
  - Mollusk
  - Agave `program-test`
  - surfpool
- Representative example CU is already quite reasonable for the current SDK shape.
- Complex examples (`vault`, `token-vault`, `escrow`) are now measurable under at least one runtime harness.

### 3.2 What the historical cross-language numbers say

- Direct-SBF Zig is clearly the better Zig path versus the old `sbpf-linker` route.
- Pinocchio still wins on the best comparable microbenchmarks we ran.
- The remaining gap is real, but it is **not** “orders of magnitude” in the best apples-to-apples cases:
  - `transfer-lamports`: Zig fork **37** vs Pinocchio **27**
  - `cpi`: Zig fork **2,967** vs Pinocchio **2,771**
- Direct-SBF Zig already beats the “official Rust baseline” on some workloads we tested, which suggests the remaining gap is mostly about **SDK/code shape and backend maturity**, not a fundamental language limitation.

## 4. Interpretation cautions

- Do **not** compare CU across different harnesses as if they were identical.
- Some historical `sbpf-linker` results were affected by runtime incompatibilities and should only be read as archive data.
- `Pinocchio` comparisons are only meaningful on workloads where the program logic is truly aligned.
