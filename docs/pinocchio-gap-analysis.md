# Pinocchio Gap Analysis

> Question: **Is Zignocchio now a full Zig implementation of Anza's Pinocchio?**
>
> Short answer: **not yet**.
>
> More precise answer: **Zignocchio already tracks Pinocchio closely in the most important runtime-facing performance ideas — zero-copy account access, lazy entrypoint parsing, duplicate-account deferral, and hot-path CU optimization — but it does not yet match Pinocchio as a complete SDK + ecosystem shape.**

This document turns that conclusion into an actionable comparison.

## Scope

This comparison is based on the current Zignocchio repository plus the Pinocchio core crate and companion crates available in the local Cargo registry, especially:

- `pinocchio`
- `pinocchio-log`
- `pinocchio-system`
- `pinocchio-token`
- `pinocchio-associated-token-account`
- `pinocchio-token-2022`
- `pinocchio-memo`

The goal is not to ask whether Zig can match Pinocchio's performance — current benchmarks already show that it can on selected hot paths — but to ask:

1. Which Pinocchio design ideas are already implemented in Zignocchio?
2. Which are only partially implemented?
3. Which are still missing?
4. What should be built next if we want to credibly call Zignocchio a Zig-side Pinocchio equivalent?

---

## Executive summary

### What is already strongly aligned

Zignocchio is already clearly on the same design line as Pinocchio in these areas:

- **Zero-copy entrypoint parsing**
- **Lazy/cursor-based entrypoint API**
- **Duplicate-account deferral via `MaybeAccount`-style handling**
- **Thin raw account access for CU-critical handlers**
- **PDA and CPI helpers sufficient for low-level program construction**
- **Benchmark-driven hot-path optimization**

### What is only partially aligned

Zignocchio has corresponding functionality, but not yet the same shape or maturity, in these areas:

- **System / Token / ATA / Memo / Token-2022 helper layers**
- **Fast CPI ergonomics as a first-class SDK style**
- **Logging ergonomics**
- **Default recommended fast-path programming model**
- **Custom entrypoint composition story**

### What is still clearly missing

These are the most obvious gaps versus Pinocchio as a complete SDK:

- **Formal `sysvars` module family** (`rent`, `clock`, `instructions`, `fees`)
- **`no_allocator`-style mode**
- **Formal panic-handler strategy / composition layer**
- **A clearer split between thin core and higher-level helper layers**

---

## Status matrix

Legend:

- **Aligned**: core capability and design intent are already present
- **Partial**: equivalent capability exists, but the API shape / completeness / default usage differs materially
- **Missing**: Pinocchio has a first-class concept that Zignocchio does not yet expose as a formal layer

## 1. Entrypoint and input parsing

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Standard zero-copy entrypoint | `program_entrypoint!`, `process_entrypoint` | `sdk/entrypoint.zig`, `createEntrypoint*` | Aligned | Both directly parse the SVM input buffer into program id / accounts / instruction data without eager copies. |
| Configurable max accounts | macro parameter / const generic flow | `createEntrypointWithMaxAccounts` | Aligned | Same optimization purpose: reduce stack cost and limit eager account materialization. |
| Public low-level entrypoint parsing API | `process_entrypoint` | `deserialize` + entrypoint wrappers | Partial | Zignocchio has the underlying pieces, but the "official custom fast-path entrypoint recipe" is less explicit. |

### Assessment

This area is already close. Zignocchio is clearly following the same low-level design philosophy.

---

## 2. Lazy entrypoint / cursor model

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Lazy entrypoint declaration | `lazy_program_entrypoint!` | `sdk.createLazyEntrypoint(...)` | Aligned | Same role in the system. |
| Instruction context wrapper | `InstructionContext` | `sdk.lazy.EntryContext` | Aligned | Same conceptual object. |
| Remaining-account counter | `remaining()` | `remaining()` | Aligned | Direct equivalent. |
| Checked next-account read | `next_account()` | `nextAccount()` | Aligned | Same semantics. |
| Unchecked next-account read | `next_account_unchecked()` | `nextAccountUnchecked()` | Aligned | Same semantics and purpose. |
| Read instruction data from cursor | `instruction_data_unchecked()` | `instructionDataUnchecked()` | Aligned | Direct equivalent. |
| Read program id from cursor | `program_id_unchecked()` | `programIdUnchecked()` | Aligned | Direct equivalent. |
| Deferred duplicate handling | `MaybeAccount::{Account,Duplicated}` | `sdk.lazy.MaybeAccount` | Aligned | One of the strongest direct correspondences. |

### Assessment

This is the strongest Pinocchio-to-Zignocchio alignment today.

---

## 3. Account model and borrow access

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Thin runtime-facing account view | `AccountView` / `RuntimeAccount` | `sdk.types.Account`, `sdk.AccountInfo`, `sdk.LazyAccount` | Aligned | Zignocchio uses its own Zig-side layout types, but the design target is the same. |
| Zero-copy data/lamports access | account view accessors | `borrowDataUnchecked`, `borrowMutDataUnchecked`, lamport borrows | Aligned | The raw hot path is there. |
| Duplicate-account late resolution | `MaybeAccount::Duplicated` | `MaybeAccount.Duplicated` | Aligned | Important performance property is preserved. |
| Minimal default abstraction cost | thin default account view style | regular path still often uses higher-level helpers | Partial | Zignocchio can reach the same shape, but the fastest style is not always the default ergonomic path. |

### Assessment

The capability is present. The remaining gap is more about **default SDK style** than about missing primitives.

---

## 4. PDA support

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Find PDA | `find_program_address` pattern | `sdk.findProgramAddress` | Aligned | Present and working. |
| Create PDA from known bump | `create_program_address` pattern | `sdk.createProgramAddress` | Aligned | Present and used in optimized examples. |
| Explicit PDA assertion helper | helper-level verification | `sdk.guard.assert_pda` | Partial | Exists, but not yet unified across regular + lazy fast styles. |
| Cheap bump-based reverify pattern | store bump + rederive cheaply | used in `escrow-lazy` | Partial | Proven in examples, but not yet elevated into a documented, reusable SDK pattern. |

---

## 5. CPI core

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Base CPI types | core CPI crate/types | `sdk/cpi.zig` | Aligned | The basic capability is there. |
| Signed CPI | signer-aware CPI | `invokeSigned` | Aligned | Supported. |
| Unchecked / raw fast path | thin hot-path CPI style | raw helpers in `sdk/system.zig` and `invokeSignedUnchecked` | Partial | Strong capability exists, but it is still partly an implementation technique rather than a cleanly surfaced first-class style. |
| Reusable signer abstraction | ecosystem-wide signer shape | ad hoc seed slices | Partial | Works, but less structured than Pinocchio's broader crate ecosystem. |

---

## 6. System / Token / ATA / Token-2022 / Memo helper layers

| Area | Pinocchio ecosystem | Zignocchio | Status | Notes |
|---|---|---|---|---|
| System helper crate | `pinocchio-system` | `sdk/system.zig` | Partial | Functionally strong, but not yet shaped as a thin companion layer with the same polish. |
| Token helper crate | `pinocchio-token` | `sdk/token/mod.zig` | Partial | Coverage exists, but API maturity and layering still differ. |
| ATA helper crate | `pinocchio-associated-token-account` | `sdk/token/ata.zig` | Partial | Basic coverage exists. |
| Token-2022 helper crate | `pinocchio-token-2022` | `sdk/token_2022.zig` | Partial | Coverage exists, but not yet clearly matched feature-for-feature. |
| Memo helper crate | `pinocchio-memo` | `sdk/memo.zig` | Partial | Basic functionality exists. |

### Assessment

Zignocchio already covers much of the same functional surface, but not yet with the same ecosystem clarity.

---

## 7. Sysvars

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Clock sysvar | `sysvars::clock` | no formal `sdk.sysvars.clock` | Missing | Underlying syscall support exists, but not a public module layer. |
| Rent sysvar | `sysvars::rent` | no formal `sdk.sysvars.rent` | Missing | This is especially important because many current examples still use conservative rent approximations. |
| Fees sysvar | `sysvars::fees` | no formal module | Missing | Formal API missing. |
| Instructions sysvar | `sysvars::instructions` | no formal module | Missing | Important for more advanced program patterns. |

### Assessment

This is one of the clearest and most concrete gaps.

---

## 8. Logging

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Basic log syscall wrappers | core + companion logging story | `sdk/log.zig` | Partial | Zignocchio has thin syscall wrappers, but not the same richer logger ergonomics. |
| Buffered logger / append-style formatting | `pinocchio-log` | none | Missing | No `Logger<N>`-style helper layer yet. |
| Benchmark-friendly minimal logging discipline | manual pattern | manual pattern | Partial | Demonstrated in benchmarks, but not yet formalized as a logging strategy layer. |

---

## 9. Allocator / panic / composable runtime setup

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Default bump allocator setup | `default_allocator!` | `sdk/allocator.zig` | Partial | Bump allocator exists, but not as part of a polished entrypoint composition story. |
| No-allocation mode | `no_allocator!` | none | Missing | Important if we want strong parity with Pinocchio's explicit no-allocation stance. |
| Default panic handler setup | `default_panic_handler!` | none | Missing | No first-class equivalent layer. |
| `no_std`-style panic handler option | `nostd_panic_handler!` | none | Missing | No equivalent story yet. |
| Declarative entrypoint + allocator + panic composition | macro family | manual assembly | Missing | This is a major ergonomics / architecture gap, even if performance primitives already exist. |

### Assessment

This is one of the biggest architectural gaps if the goal is a true Pinocchio-equivalent SDK.

---

## 10. Default fast-path programming model

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Thin runtime-facing code is the normal style | yes | only partly | Partial | In Zignocchio, the fastest style often lives in `*-lazy` examples rather than the main ergonomic path. |
| High-level helpers avoid pulling code away from fast path | usually | mixed | Partial | `guard` / `schema` / `idioms` are useful, but they can also move code away from the thinnest possible hot path. |
| Benchmark-backed fast style already proven | yes | yes | Aligned | The important proof is already there. |

### Assessment

Zignocchio has proven that it **can** hit Pinocchio-class hot paths. The remaining task is to make that path feel more native and official.

---

## 11. Core package philosophy

| Area | Pinocchio | Zignocchio | Status | Notes |
|---|---|---|---|---|
| Very thin core crate | yes | not fully | Different by design | Zignocchio core currently includes more high-level teaching/safety helpers. |
| Companion crates carry much of the ergonomic surface | yes | not yet clearly | Partial | Zignocchio is still more monolithic. |
| Explicit focus on minimal opinionated abstraction in core | strong | mixed | Partial | Zignocchio mixes low-level runtime-facing code with higher-level guard/schema/idiom layers. |

### Assessment

This is not purely a gap; it is also a **product decision**. Zignocchio may intentionally want to remain a somewhat higher-level SDK.

---

## Practical conclusion

## What we can say today

It is fair to say:

> **Zignocchio already follows Pinocchio very closely in the most important performance-critical runtime design choices.**

That is especially true for:

- lazy entrypoint parsing
- zero-copy account handling
- duplicate-account deferral
- thin hot-path account access
- benchmark-driven CU reduction

## What we cannot yet say

It is **not** yet accurate to say:

> "Zignocchio is now a complete Zig implementation of Pinocchio."

That would overstate parity, because Zignocchio still lacks:

- a formal sysvars layer
- a `no_allocator`/panic-handler composition story
- a clearly companion-style ecosystem boundary
- a fully settled "default fast path" ergonomic model

---

## Priority roadmap

## P0 — highest priority gaps

### 1. Add formal `sdk.sysvars` modules

Recommended first additions:

- `sdk/sysvars/rent.zig`
- `sdk/sysvars/clock.zig`
- `sdk/sysvars/instructions.zig`
- `sdk/sysvars/fees.zig`

Why this matters:

- It is the cleanest feature gap versus Pinocchio.
- It reduces the need for conservative rent approximations.
- It makes advanced runtime-aware patterns much easier to express.

### 2. Add explicit allocator / panic composition modes

Recommended additions:

- `no_allocator`-style mode
- default panic strategy for hosted / `std`-linked contexts
- explicit direct-SBF / `no_std` panic strategy
- clearer entrypoint composition recipes

Why this matters:

- This is a major part of Pinocchio's SDK shape.
- It clarifies what the minimal runtime contract of Zignocchio actually is.

### 3. Decide whether Zignocchio wants a thinner core

Product decision to make explicitly:

- **Option A:** keep Zignocchio as a somewhat higher-level SDK than Pinocchio
- **Option B:** split a thinner Pinocchio-like core from higher-level helper layers (`guard`, `schema`, `idioms`, etc.)

Why this matters:

- Without this decision, parity work can become inconsistent.

---

## P1 — next level of parity work

### 4. Promote the lazy/raw fast path from "experimental benchmark style" to a formal supported style

This means:

- documenting when to prefer lazy entrypoints
- minimizing unnecessary fallback to `AccountInfo`
- turning proven benchmark patterns into reusable helpers

### 5. Elevate cheap PDA verification and fast CPI patterns into documented SDK-level idioms

Examples already prove these techniques work:

- store `bump` in state
- use `createProgramAddress(...)` for cheap revalidation
- route hot CPI operations through raw helpers

These patterns should become official guidance, not just example-local optimizations.

### 6. Tighten ecosystem layering for System / Token / ATA / Token-2022 / Memo helpers

The functionality is mostly present; the remaining work is to make the structure feel more like a coherent companion ecosystem.

---

## P2 — later parity / ergonomics improvements

### 7. Add a buffered logger layer similar to `pinocchio-log`

### 8. Provide more explicit custom-entrypoint recipes and templates

### 9. Improve signer abstraction ergonomics for CPI-heavy programs

---

## Final assessment

If the question is:

> "Is Zignocchio already on the same performance-design line as Pinocchio?"

The answer is:

> **Yes. Definitely.**

If the question is:

> "Is Zignocchio already a full Zig-side Pinocchio equivalent?"

The answer is:

> **Not yet.**
>
> The remaining work is less about raw performance possibility and more about **SDK shape, sysvars coverage, allocator/panic composition, and ecosystem structure**.
