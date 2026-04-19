# Backend Comparison Report

> Historical note: this report captures the earlier `sbpf-linker` vs `fork-sbf` experiment.
> The current repository build path is direct-SBF via the `solana-zig` fork; keep this file as archived benchmark context, not current build instructions.

- stock Zig backend: `sbpf-linker`
- fork Zig binary: `/Users/davirian/dev/active/solana-zig-bootstrap/out/host/bin/zig`
- compared metrics: `.so` size, wall-clock build time, representative runtime CU

## Build Output Comparison

| example | sbpf-linker size | fork-sbf size | Δ size (fork - sbpf) | smaller artifact | sbpf-linker build | fork-sbf build | Δ time | faster build |
|---|---:|---:|---:|---|---:|---:|---:|---|
| hello | 1,192 | 1,408 | +216 | sbpf-linker | 0.53s | 0.34s | -0.19s | fork-sbf |
| counter | 3,432 | 3,352 | -80 | fork-sbf | 0.43s | 0.84s | +0.41s | sbpf-linker |
| transfer-sol | 4,376 | 3,760 | -616 | fork-sbf | 0.36s | 0.28s | -0.08s | fork-sbf |
| pda-storage | 7,992 | 5,920 | -2,072 | fork-sbf | 0.31s | 0.25s | -0.06s | fork-sbf |
| vault | 10,984 | 8,024 | -2,960 | fork-sbf | 0.37s | 0.24s | -0.13s | fork-sbf |
| token-vault | 18,136 | 10,720 | -7,416 | fork-sbf | 0.43s | 0.28s | -0.15s | fork-sbf |
| escrow | 15,640 | 9,752 | -5,888 | fork-sbf | 0.33s | 0.32s | -0.00s | fork-sbf |
| noop | 304 | 1,128 | +824 | sbpf-linker | 0.27s | 0.22s | -0.05s | fork-sbf |
| logonly | 1,184 | 1,408 | +224 | sbpf-linker | 0.23s | 0.20s | -0.03s | fork-sbf |

## Runtime CU Comparison

Measured with `mollusk-svm`'s `compute_units_consumed` on representative happy-path scenarios.
These numbers are useful as a backend-to-backend proxy, but they are not a promise about every validator/runtime version.

| example | scenario | sbpf-linker CU | fork-sbf CU | Δ CU (fork - sbpf) | lower CU |
|---|---|---:|---:|---:|---|
| hello | hello | 107 | n/a | n/a | n/a |
| counter | increment | 970 | n/a | n/a | n/a |
| transfer-sol | transfer | 3,013 | n/a | n/a | n/a |
| pda-storage | init | 4,683 | n/a | n/a | n/a |
| pda-storage | update | 2,737 | n/a | n/a | n/a |
| vault | deposit | 9,621 | n/a | n/a | n/a |
| token-vault | _none_ | n/a | n/a | n/a | no runtime CU harness |
| escrow | accept | 3,709 | n/a | n/a | n/a |
| escrow | make | 7,818 | n/a | n/a | n/a |
| escrow | refund | 3,230 | n/a | n/a | n/a |
| noop | _none_ | n/a | n/a | n/a | no runtime CU harness |
| logonly | _none_ | n/a | n/a | n/a | no runtime CU harness |

### Runtime notes

- `hello` — fork-sbf: thread 'main' (165619396) panicked at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18:
called `Result::unwrap()` on an `Err` value: RelativeJumpOutOfBounds(3)
stack backtrace:
   0: __rustc::rust_begin_unwind
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/std/src/panicking.rs:689:5
   1: core::panicking::panic_fmt
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/panicking.rs:80:14
   2: core::result::unwrap_failed
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/result.rs:1867:5
   3: core::result::Result<T,E>::unwrap
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs:1233:23
   4: mollusk_svm::program::ProgramCache::add_program
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18
   5: mollusk_svm::Mollusk::add_program_with_loader_and_elf
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/lib.rs:843:28
   6: cu_probe::load_mollusk
             at ./tests_rust/bin/cu_probe.rs:42:13
   7: cu_probe::probe_hello
             at ./tests_rust/bin/cu_probe.rs:59:19
   8: cu_probe::main
             at ./tests_rust/bin/cu_probe.rs:412:20
   9: core::ops::function::FnOnce::call_once
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
- `counter` — fork-sbf: thread 'main' (165619927) panicked at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18:
called `Result::unwrap()` on an `Err` value: RelativeJumpOutOfBounds(48)
stack backtrace:
   0: __rustc::rust_begin_unwind
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/std/src/panicking.rs:689:5
   1: core::panicking::panic_fmt
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/panicking.rs:80:14
   2: core::result::unwrap_failed
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/result.rs:1867:5
   3: core::result::Result<T,E>::unwrap
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs:1233:23
   4: mollusk_svm::program::ProgramCache::add_program
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18
   5: mollusk_svm::Mollusk::add_program_with_loader_and_elf
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/lib.rs:843:28
   6: cu_probe::load_mollusk
             at ./tests_rust/bin/cu_probe.rs:42:13
   7: cu_probe::probe_counter
             at ./tests_rust/bin/cu_probe.rs:75:19
   8: cu_probe::main
             at ./tests_rust/bin/cu_probe.rs:413:22
   9: core::ops::function::FnOnce::call_once
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
- `transfer-sol` — fork-sbf: thread 'main' (165620343) panicked at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18:
called `Result::unwrap()` on an `Err` value: RelativeJumpOutOfBounds(50)
stack backtrace:
   0: __rustc::rust_begin_unwind
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/std/src/panicking.rs:689:5
   1: core::panicking::panic_fmt
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/panicking.rs:80:14
   2: core::result::unwrap_failed
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/result.rs:1867:5
   3: core::result::Result<T,E>::unwrap
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs:1233:23
   4: mollusk_svm::program::ProgramCache::add_program
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18
   5: mollusk_svm::Mollusk::add_program_with_loader_and_elf
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/lib.rs:843:28
   6: cu_probe::load_mollusk
             at ./tests_rust/bin/cu_probe.rs:42:13
   7: cu_probe::probe_transfer_sol
             at ./tests_rust/bin/cu_probe.rs:144:19
   8: cu_probe::main
             at ./tests_rust/bin/cu_probe.rs:415:27
   9: core::ops::function::FnOnce::call_once
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
- `pda-storage` — fork-sbf: thread 'main' (165620731) panicked at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18:
called `Result::unwrap()` on an `Err` value: RelativeJumpOutOfBounds(51)
stack backtrace:
   0: __rustc::rust_begin_unwind
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/std/src/panicking.rs:689:5
   1: core::panicking::panic_fmt
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/panicking.rs:80:14
   2: core::result::unwrap_failed
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/result.rs:1867:5
   3: core::result::Result<T,E>::unwrap
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs:1233:23
   4: mollusk_svm::program::ProgramCache::add_program
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18
   5: mollusk_svm::Mollusk::add_program_with_loader_and_elf
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/lib.rs:843:28
   6: cu_probe::load_mollusk
             at ./tests_rust/bin/cu_probe.rs:42:13
   7: cu_probe::probe_pda_storage
             at ./tests_rust/bin/cu_probe.rs:179:19
   8: cu_probe::main
             at ./tests_rust/bin/cu_probe.rs:416:26
   9: core::ops::function::FnOnce::call_once
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
- `vault` — fork-sbf: thread 'main' (165621158) panicked at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18:
called `Result::unwrap()` on an `Err` value: RelativeJumpOutOfBounds(52)
stack backtrace:
   0: __rustc::rust_begin_unwind
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/std/src/panicking.rs:689:5
   1: core::panicking::panic_fmt
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/panicking.rs:80:14
   2: core::result::unwrap_failed
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/result.rs:1867:5
   3: core::result::Result<T,E>::unwrap
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs:1233:23
   4: mollusk_svm::program::ProgramCache::add_program
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18
   5: mollusk_svm::Mollusk::add_program_with_loader_and_elf
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/lib.rs:843:28
   6: cu_probe::load_mollusk
             at ./tests_rust/bin/cu_probe.rs:42:13
   7: cu_probe::probe_vault
             at ./tests_rust/bin/cu_probe.rs:99:19
   8: cu_probe::main
             at ./tests_rust/bin/cu_probe.rs:414:20
   9: core::ops::function::FnOnce::call_once
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
- `token-vault` — sbpf-linker: no runtime CU harness | fork-sbf: no runtime CU harness
- `escrow` — fork-sbf: thread 'main' (165621847) panicked at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18:
called `Result::unwrap()` on an `Err` value: RelativeJumpOutOfBounds(51)
stack backtrace:
   0: __rustc::rust_begin_unwind
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/std/src/panicking.rs:689:5
   1: core::panicking::panic_fmt
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/panicking.rs:80:14
   2: core::result::unwrap_failed
             at /rustc/01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf/library/core/src/result.rs:1867:5
   3: core::result::Result<T,E>::unwrap
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs:1233:23
   4: mollusk_svm::program::ProgramCache::add_program
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/program.rs:164:18
   5: mollusk_svm::Mollusk::add_program_with_loader_and_elf
             at /Users/davirian/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/mollusk-svm-0.12.1-agave-4.0/src/lib.rs:843:28
   6: cu_probe::load_mollusk
             at ./tests_rust/bin/cu_probe.rs:42:13
   7: cu_probe::probe_escrow
             at ./tests_rust/bin/cu_probe.rs:256:19
   8: cu_probe::main
             at ./tests_rust/bin/cu_probe.rs:417:21
   9: core::ops::function::FnOnce::call_once
             at /Users/davirian/.rustup/toolchains/1.93.1-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
- `noop` — sbpf-linker: no runtime CU harness | fork-sbf: no runtime CU harness
- `logonly` — sbpf-linker: no runtime CU harness | fork-sbf: no runtime CU harness

## Summary

- total `.so` size (`sbpf-linker`): 63,240 bytes
- total `.so` size (`fork-sbf`): 45,472 bytes
- smaller artifact wins: `sbpf-linker` 3, `fork-sbf` 6, ties 0
- average build time (`sbpf-linker`): 0.36s
- average build time (`fork-sbf`): 0.33s
- faster build wins: `sbpf-linker` 1, `fork-sbf` 8, ties 0
- lower runtime CU wins (scenario rows with data): `sbpf-linker` 0, `fork-sbf` 0, ties 0

Artifacts copied to:
- `/Users/davirian/dev/active/zignocchio/.backend-compare/sbpf-linker`
- `/Users/davirian/dev/active/zignocchio/.backend-compare/fork-sbf`
