#!/usr/bin/env bash
# Step 5 (the operator pays ~0.01 NEAR storage, mostly refunded): register your pet on the mainnet API. You sign
# "Register my pet. Pet: <name> Payout: <account>" with your wallet key (keychain); World ID is off, invite-only.
#   OWNER=you.near PET=mochi [PAYOUT=you.near] bash scripts/mainnet/50-register-pet.sh    (add CONFIRM_MAINNET=yes to send)
. "$(dirname "$0")/lib.sh"
need OWNER; need PET
PAYOUT="${PAYOUT:-$OWNER}"
MSG="$(printf 'Register my pet.\nPet: %s\nPayout: %s' "$PET" "$PAYOUT")"
NONCE="$(openssl rand -base64 32)"
echo "You sign (no NEAR moves): $MSG"
if [ "$NETWORK" = mainnet ] && [ "${CONFIRM_MAINNET:-}" != yes ]; then echo "(dry run: re-run with CONFIRM_MAINNET=yes)"; exit 0; fi
S="$(sign "$OWNER" "$MSG" "$NONCE")"
[ -n "$S" ] || { echo "signing failed: is $OWNER's key in the keychain? (near account import-account ...)" >&2; exit 1; }
BODY="$(S="$S" N="$NONCE" T="$PET" O="$OWNER" P="$PAYOUT" python3 -I -c 'import json,os; e=os.environ; s=json.loads(e["S"]); print(json.dumps({"name": e["T"], "owner": e["O"], "payout": e["P"], "signature": s["signature"], "publicKey": s["publicKey"], "nonce": e["N"]}))')"
curl -s --max-time 120 -X POST "$API/pets/register" -H 'Content-Type: application/json' -d "$BODY"; echo
