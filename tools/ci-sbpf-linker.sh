#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if command -v brew >/dev/null 2>&1; then
  BREW_LLVM_LIB="$(brew --prefix llvm 2>/dev/null || true)/lib"
  if [[ -d "$BREW_LLVM_LIB" ]]; then
    export DYLD_FALLBACK_LIBRARY_PATH="$BREW_LLVM_LIB${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
  fi
fi

for candidate in \
  /opt/homebrew/opt/llvm/lib \
  /usr/local/opt/llvm/lib \
  /usr/lib/llvm-18/lib \
  /usr/lib/llvm-19/lib \
  /usr/lib/llvm-20/lib \
  /usr/lib64/llvm/lib
  do
  if [[ -d "$candidate" ]]; then
    LLVM_LIB_DIR="$candidate"
    break
  fi
done
LLVM_LIB_DIR="${LLVM_LIB_DIR:-}"

COMMON_BUILD_ARGS=(-Dbackend=sbpf-linker)
if [[ -n "$LLVM_LIB_DIR" ]]; then
  COMMON_BUILD_ARGS+=("-Dsbpf-llvm-lib-dir=$LLVM_LIB_DIR")
fi

examples=(
  hello
  counter
  transfer-sol
  pda-storage
  vault
  token-vault
  escrow
  noop
  logonly
)

for example in "${examples[@]}"; do
  echo "==> Building $example with sbpf-linker"
  zig build -Dexample="$example" "${COMMON_BUILD_ARGS[@]}"
done

echo "==> Running Zig unit tests"
zig build test

echo "==> Running example litesvm tests"
npm run test:examples:litesvm

echo "==> Running client tests"
npm run test:client

echo "==> Running Rust mollusk tests"
(cd tests_rust && cargo test)

if command -v surfpool >/dev/null 2>&1; then
  echo "==> Running surfpool example tests"
  npm run test:examples:surfpool
else
  echo "==> Skipping surfpool example tests (surfpool not found in PATH)"
fi
