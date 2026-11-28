#!/usr/bin/env bash
# Step 3 (NEAR, gas only): deploy the vault wasm to $VAULT and initialise it in the same tx (admin $ROOT, operator $OPERATOR).
#   bash scripts/mainnet/30-deploy-vault.sh      (add CONFIRM_MAINNET=yes to send)
. "$(dirname "$0")/lib.sh"
got="$(shasum -a 256 "$WASM" | cut -d' ' -f1)"
[ "$got" = "$WASM_SHA256" ] || { echo "wasm sha256 $got is not the expected $WASM_SHA256: rebuild with cargo near build non-reproducible-wasm" >&2; exit 1; }
run "deploys the vault (about 0.01 NEAR of gas; the storage is already paid by the account's balance)" \
  near contract deploy "$VAULT" use-file "$WASM" with-init-call new json-args "{\"admin\":\"$ROOT\",\"operator\":\"$OPERATOR\"}" \
  prepaid-gas '30 Tgas' attached-deposit '0 NEAR' network-config "$NETWORK" sign-with-keychain send
if [ "$NETWORK" = testnet ] || [ "${CONFIRM_MAINNET:-}" = yes ]; then
  echo "totals: $(view "$VAULT" get_totals '{}')"
  near account view-account-summary "$VAULT" network-config "$NETWORK" now 2>&1 | grep -iE "code hash|balance" | head -4
fi
