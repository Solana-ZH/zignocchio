# CU Summary

> Current mainline build path: direct SBF via the `solana-zig` fork.
> The `*-lazy` variants below are **experimental benchmarking paths**, not the default SDK style.
> Always compare numbers **within the same harness and scenario**.

## 1. Current repository A/B: regular vs lazy variants

These measurements compare the normal example handlers against the experimental
Pinocchio-style lazy-entrypoint variants added for apples-to-apples testing.

## 1.1 Mollusk

Measured with `tests_rust/bin/cu_probe.rs` against `zig-out/lib/*.so`.

| example | scenario | regular | lazy | delta | notes |
|---|---|---:|---:|---:|---|
| hello | execute | 105 | 108 | +3 | log-dominated; lazy overhead is not amortized |
| counter | increment | 970 | 952 | -18 | improved after removing `collectAccountInfos` fallback |
| transfer-sol | transfer | 1,612 | 1,584 | -28 | small win; System Program CPI still dominates |
| transfer-owned | transfer | 54 | 27 | -27 | pure hot-path benchmark; now matches Pinocchio |
| pda-storage | init | 4,473 | 6,324 | +1,851 | still loses under Mollusk |
| pda-storage | update | 2,678 | 4,152 | +1,474 | still loses under Mollusk |
| vault | deposit | 9,478 | 10,139 | +661 | improved from earlier lazy attempt, still worse in Mollusk |
| escrow | make | 7,317 | 7,266 | -51 | slight win |
| escrow | accept | 3,597 | 5,065 | +1,468 | lazy path still worse here |
| noop | execute | 2 | 6 | +4 | tiny program; fixed lazy overhead dominates |
| logonly | execute | 105 | 108 | +3 | log syscall dominates |

Commands used:

```bash
for ex in \
  hello hello-lazy \
  counter counter-lazy \
  vault vault-lazy \
  transfer-sol transfer-sol-lazy \
  transfer-owned transfer-owned-lazy \
  pda-storage pda-storage-lazy \
  escrow escrow-lazy \
  noop noop-lazy \
  logonly logonly-lazy
 do
  cargo run --manifest-path tests_rust/Cargo.toml --bin cu_probe -- \
    --example "$ex" --artifact "zig-out/lib/$ex.so"
 done
```

## 1.2 Agave `program-test`

Measured from `--nocapture` logs in `tests_agave`.

| example | scenario | regular | lazy | delta | notes |
|---|---|---:|---:|---:|---|
| hello | execute | 105 | 108 | +3 | no meaningful account traversal to save |
| counter | increment | 970 | 952 | -18 | same directional win as Mollusk |
| transfer-sol | transfer | 1,666 | 1,638 | -28 | small but stable win |
| transfer-owned | transfer | 54 | 27 | -27 | same as Mollusk |
| pda-storage | init | 4,527 | 4,878 | +351 | much closer than Mollusk |
| pda-storage | update | 2,678 | 2,652 | -26 | now slightly better |
| vault | deposit | 9,532 | 5,693 | -3,839 | large win under Agave |
| escrow | make | 10,371 | 8,820 | -1,551 | clear win |
| escrow | accept | 5,076 | 6,532 | +1,456 | still worse |
| token-vault | initialize | 9,653 | 8,304 | -1,349 | meaningful CPI-heavy win |
| token-vault | deposit | 7,473 | 6,074 | -1,399 | meaningful CPI-heavy win |
| token-vault | withdraw | 7,863 | 6,466 | -1,397 | meaningful CPI-heavy win |
| noop | execute | 2 | 6 | +4 | tiny program penalty |
| logonly | execute | 105 | 108 | +3 | log-dominated |

Representative commands used:

```bash
cd tests_agave
BPF_OUT_DIR=../zig-out/lib cargo test \
  --test hello_agave --test hello_lazy_agave \
  --test counter_agave --test counter_lazy_agave \
  --test transfer_sol_agave --test transfer_sol_lazy_agave \
  --test transfer_owned_agave --test transfer_owned_lazy_agave \
  --test pda_storage_agave --test pda_storage_lazy_agave \
  --test vault_agave --test vault_lazy_agave \
  --test escrow_agave --test escrow_lazy_agave \
  --test token_vault_agave --test token_vault_lazy_agave \
  --test noop_agave --test noop_lazy_agave \
  --test logonly_agave --test logonly_lazy_agave \
  -- --nocapture
```

## 1.3 What this A/B says

### Clear wins for lazy/raw path

- `transfer-owned`: **54 -> 27**
- `counter`: **970 -> 952**
- `transfer-sol`: modest but stable **-28 CU**
- `token-vault`: consistent **~1.3k-1.4k CU** wins under Agave
- `vault` deposit: large Agave win after rewriting the handler to stay on the lazy path
- `escrow make`: modest-to-strong win depending on runtime

### Clear non-wins

- `hello`
- `logonly`
- `noop`

These examples are too small or too syscall-dominated; lazy entrypoint overhead is not amortized.

### Still mixed / needs more work

- `pda-storage`: close under Agave, still clearly worse under Mollusk
- `escrow accept`: still worse in both harnesses
- `vault`: strong Agave improvement, but still worse than regular under Mollusk

### Main interpretation

The data now supports a stronger statement than before:

- **Zig is not the limiting factor.**
- **Code shape is the limiting factor.**
- When the handler really stays on a thin lazy/raw path, Zig can match Pinocchio-class CU.
- When the lazy variant falls back into old abstractions, the win shrinks or disappears.

## 2. Historical apples-to-apples runtime comparisons (`solana-program-rosetta`)

These numbers remain the most useful cross-language reference points because the workloads were intentionally matched across implementations.

| workload | Rust official | Zig fork direct-SBF | Zig `sbpf-linker` | Rust Pinocchio | notes |
|---|---:|---:|---:|---:|---|
| helloworld | 105 | 105 | 103 | n/a | `sbpf-linker` log output was suspiciously empty |
| transfer-lamports | 493 | 37 | 58 | 27 | best clean Zig-vs-Pinocchio microbenchmark before in-repo lazy benchmark |
| pubkey | 14 | 15 | 187 | n/a | Zig fork tracks Rust closely; `sbpf-linker` regressed badly |
| cpi | 3,753 | 2,967 | failed | 2,771 | `sbpf-linker` hit `Access violation in input section` |

## 3. Practical conclusions

### 3.1 Current repo mainline vs experimental fast path

- The normal direct-SBF path is stable across:
  - LiteSVM
  - client adapter tests
  - Mollusk
  - Agave `program-test`
  - surfpool
- The lazy variants are now useful as a **measurement tool** and as a prototype for future SDK fast paths.
- The best-case benchmark (`transfer-owned-lazy`) now reaches **27 CU**, matching the current Pinocchio reference.

### 3.2 What still needs investigation

- Why `vault-lazy` is strongly better in Agave but still worse in Mollusk.
- Why `escrow make` improved but `escrow accept` regressed.
- Whether `pda-storage-lazy` can be pushed below regular under Mollusk without sacrificing Agave behavior.

## 4. Interpretation cautions

- Do **not** compare CU across different harnesses as if they were identical.
- Treat the `*-lazy` examples as experimental benchmark variants, not as the default ergonomics story.
- `Pinocchio` comparisons are only meaningful when the instruction semantics are truly aligned.
- Some historical `sbpf-linker` results were affected by runtime incompatibilities and should only be read as archive data.
