#!/usr/bin/env bash
# Step 2 (NEAR): the admin account $ROOT from your funded account, then $VAULT and $OPERATOR under it.
# Keys for ROOT and VAULT go to your macOS keychain; OPERATOR gets the public key made on the EC2 box (step 1).
#   FUNDER=you.near OPERATOR_PUBLIC_KEY=ed25519:... bash scripts/mainnet/20-accounts.sh     (add CONFIRM_MAINNET=yes to send)
. "$(dirname "$0")/common.sh"
need FUNDER; need OPERATOR_PUBLIC_KEY
run "creates $ROOT, funded with 4 NEAR from $FUNDER (it pays for the two below)" \
  near account create-account fund-myself "$ROOT" '4 NEAR' autogenerate-new-keypair save-to-keychain sign-as "$FUNDER" network-config "$NETWORK" sign-with-keychain send
run "creates $VAULT with 2.4 NEAR (about 1.9 NEAR of it pays the contract's storage)" \
  near account create-account fund-myself "$VAULT" '2.4 NEAR' autogenerate-new-keypair save-to-keychain sign-as "$ROOT" network-config "$NETWORK" sign-with-keychain send
run "creates $OPERATOR with 1 NEAR (gas, and the 0.01 NEAR storage deposit per pet it registers)" \
  near account create-account fund-myself "$OPERATOR" '1 NEAR' use-manually-provided-public-key "$OPERATOR_PUBLIC_KEY" sign-as "$ROOT" network-config "$NETWORK" sign-with-keychain send
