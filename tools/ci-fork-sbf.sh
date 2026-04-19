#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ZIG_BIN="${SOLANA_ZIG:-${ZIG:-zig}}"

examples=(
  hello
  hello-lazy
  counter
  counter-lazy
  transfer-sol
  transfer-sol-lazy
  transfer-owned
  transfer-owned-lazy
  pda-storage
  pda-storage-lazy
  vault
  vault-lazy
  token-vault
  token-vault-lazy
  escrow
  escrow-lazy
  noop
  noop-lazy
  logonly
  logonly-lazy
)

for example in "${examples[@]}"; do
  echo "==> Building $example with direct SBF"
  "$ZIG_BIN" build -Dexample="$example"
done

echo "==> Running Zig unit tests"
"$ZIG_BIN" build test

echo "==> Running example litesvm tests"
npm run test:examples:litesvm

echo "==> Running client tests"
npm run test:client

echo "==> Running Rust mollusk tests"
(cd tests_rust && cargo test)

echo "==> Running Agave program-test tests"
(cd tests_agave && BPF_OUT_DIR=../zig-out/lib cargo test)

if command -v surfpool >/dev/null 2>&1; then
  echo "==> Running surfpool example tests"
  npm run test:examples:surfpool
else
  echo "==> Skipping surfpool example tests (surfpool not found in PATH)"
fi
