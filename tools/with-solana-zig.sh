#!/usr/bin/env bash
set -euo pipefail

ZIG_BIN="${SOLANA_ZIG:-${ZIG:-zig}}"
exec "$ZIG_BIN" "$@"
