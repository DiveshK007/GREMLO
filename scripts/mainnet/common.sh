#!/usr/bin/env bash
# Shared by scripts/mainnet/*.sh. On mainnet, `run` only prints the command and what it costs, unless
# CONFIRM_MAINNET=yes; on testnet it runs. Self-check: bash scripts/mainnet/common.sh --selftest
set -euo pipefail
NETWORK="${NETWORK:-mainnet}"
case "$NETWORK" in mainnet | testnet) ;; *) echo "NETWORK must be mainnet or testnet" >&2; exit 1 ;; esac
ROOT="${ROOT:-gremlo.near}"            # the admin; the vault and the operator are its sub-accounts
VAULT="vault.$ROOT"
OPERATOR="operator.$ROOT"
API="${API:-https://mainnet.16-4-100-95.sslip.io}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WASM="$REPO_DIR/contracts-near/target/near/campaign_vault.wasm"
WASM_SHA256="47b3dc61deceda91aa1620047f5832000a3a1f9dfd56f9f827fe2d541e279f22"  # cargo near build non-reproducible-wasm, 28 Nov

# run "<what it costs>" command args...
run() {
  local cost="$1"; shift
  printf '\n# %s\n' "$cost"
  printf '%q ' "$@"; echo
  if [ "$NETWORK" = mainnet ] && [ "${CONFIRM_MAINNET:-}" != yes ]; then
    echo "(dry run: nothing sent. Re-run with CONFIRM_MAINNET=yes to send it.)"
    return 0
  fi
  "$@"
}

need() { [ -n "${!1:-}" ] || { echo "set $1 (see docs/MAINNET_RUNBOOK.md)" >&2; exit 1; }; }

if [ "${1:-}" = --selftest ]; then
  out="$(NETWORK=mainnet CONFIRM_MAINNET= run "costs nothing" false)"   # would fail if it ran
  case "$out" in *"dry run"*) echo "ok: mainnet without CONFIRM_MAINNET only prints" ;; *) echo "FAIL"; exit 1 ;; esac
  CONFIRM_MAINNET=yes run "costs nothing" true >/dev/null && echo "ok: CONFIRM_MAINNET=yes runs it"
fi
