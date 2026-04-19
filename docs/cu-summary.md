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
| pda-storage | init | 4,473 | 5,104 | +631 | much better than earlier lazy attempt, still worse under Mollusk |
| pda-storage | update | 2,678 | 4,149 | +1,471 | still loses under Mollusk |
| vault | deposit | 9,478 | 8,460 | -1,018 | after hot-path log stripping, lazy now beats regular in Mollusk |
| escrow | make | 7,317 | 6,180 | -1,137 | win after moving more of the CPI path onto lazy/raw helpers |
| escrow | accept | 3,597 | 3,170 | -427 | current version stores bump in state and re-validates with cheap `createProgramAddress(...)` |
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
| pda-storage | init | 4,527 | 3,658 | -869 | now clearly better under Agave |
| pda-storage | update | 2,678 | 2,649 | -29 | slightly better |
| vault | deposit | 9,532 | 4,014 | -5,518 | after hot-path log stripping, lazy is now dramatically lower in targeted Agave runs |
| escrow | make | 10,371 | 9,234 | -1,137 | still a win, though less dramatic once cheap PDA verify is restored |
| escrow | accept | 5,076 | 3,137 | -1,939 | `bump` stored in state + cheap `createProgramAddress(...)` verify still stays well below regular |
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
- `pda-storage` init: now a clear Agave win and much improved in Mollusk
- `token-vault`: consistent **~1.3k-1.4k CU** wins under Agave
- `vault` deposit: now wins in both harnesses after moving the hot path onto lazy/raw helpers and stripping benchmark-only success logs
- `escrow make`: clear win in both harnesses
- `escrow accept`: now also wins in both harnesses; the current version stores `bump` in account state and uses cheap `createProgramAddress(...)` verification instead of re-running `findProgramAddress(...)`

### Clear non-wins

- `hello`
- `logonly`
- `noop`

These examples are too small or too syscall-dominated; lazy entrypoint overhead is not amortized.

### Still mixed / needs more work

- `pda-storage` update: still clearly worse under Mollusk even though Agave is now slightly better
- `pda-storage` init: much better than before, but still above regular under Mollusk
- `escrow`: there is now an explicit trade-off between the absolute fastest accept path and the hardened `bump`-in-state + cheap-PDA-verify path; the hardened path still wins, but costs more than the no-reverify benchmark extreme

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

- Whether `pda-storage-lazy` can be pushed below regular under Mollusk without sacrificing its now-better Agave behavior.
- Whether `escrow-lazy` should keep the current hardened `bump`-in-state + cheap-PDA-verify path as the benchmark default, or also document the even-faster no-reverify variant as a lower-bound microbenchmark.
- Whether the remaining benchmark-only success logs in make/refund-style lazy variants should be stripped the same way as the hottest accept/deposit paths.

## 4. Interpretation cautions

- Do **not** compare CU across different harnesses as if they were identical.
- Treat the `*-lazy` examples as experimental benchmark variants, not as the default ergonomics story.
- `Pinocchio` comparisons are only meaningful when the instruction semantics are truly aligned.
- Some historical `sbpf-linker` results were affected by runtime incompatibilities and should only be read as archive data.
