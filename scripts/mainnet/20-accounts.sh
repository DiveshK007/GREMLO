#!/usr/bin/env bash
# Step 2 (NEAR): the admin account $ROOT from your funded account, then $VAULT and $OPERATOR under it.
# Keys for ROOT and VAULT go to your macOS keychain; OPERATOR gets the public key made on the EC2 box (step 1).
#   FUNDER=you.near OPERATOR_PUBLIC_KEY=ed25519:... bash scripts/mainnet/20-accounts.sh     (add CONFIRM_MAINNET=yes to send)
. "$(dirname "$0")/common.sh"
need FUNDER; need OPERATOR_PUBLIC_KEY
# the admin is your funded account itself unless ROOT names a new one
if [ "$ROOT" != "$FUNDER" ]; then
  run "creates $ROOT, funded with ${ROOT_NEAR:-2.3} NEAR from $FUNDER (it pays for the two below)" \
    near account create-account fund-myself "$ROOT" "${ROOT_NEAR:-2.3} NEAR" autogenerate-new-keypair save-to-keychain sign-as "$FUNDER" network-config "$NETWORK" sign-with-keychain send
fi
run "creates $VAULT with ${VAULT_NEAR:-2.0} NEAR (about 1.9 NEAR of it is the contract's storage, locked in the account, not spent)" \
  near account create-account fund-myself "$VAULT" "${VAULT_NEAR:-2.0} NEAR" autogenerate-new-keypair save-to-keychain sign-as "$ROOT" network-config "$NETWORK" sign-with-keychain send
run "creates $OPERATOR with ${OPERATOR_NEAR:-0.15} NEAR (gas, and the 0.01 NEAR storage deposit per pet it registers)" \
  near account create-account fund-myself "$OPERATOR" "${OPERATOR_NEAR:-0.15} NEAR" use-manually-provided-public-key "$OPERATOR_PUBLIC_KEY" sign-as "$ROOT" network-config "$NETWORK" sign-with-keychain send
