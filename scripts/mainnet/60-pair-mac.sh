#!/usr/bin/env bash
# Step 6 (no NEAR): pair this Mac's Secure Enclave key with your pet on the mainnet API. The Mac must already point at
# the mainnet API (launchctl setenv GREMLO_SERVER ...; reopen Gremlo) and be 1.1.3 or later (gremlo status shows the key).
#   OWNER=you.near PET=mochi bash scripts/mainnet/60-pair-mac.sh     (add CONFIRM_MAINNET=yes to send)
. "$(dirname "$0")/lib.sh"
need OWNER; need PET
CLI=/Applications/Gremlo.app/Contents/MacOS/gremlo-cli
# DEVICE (an X9.63 P-256 public key, base64url) overrides the Mac's own key: the testnet rehearsal pairs a test key
DEVICE="${DEVICE:-$("$CLI" status --json | python3 -I -c 'import sys,json; d=json.load(sys.stdin); print((d.get("data") or d).get("device",""))')}"
[ -n "$DEVICE" ] || { echo "no device key from gremlo status: update Gremlo to 1.1.3 or later" >&2; exit 1; }
KEYID="$(python3 -I -c 'import sys,base64,hashlib; k=sys.argv[1]; print(hashlib.sha256(base64.urlsafe_b64decode(k + "=" * (-len(k) % 4))).hexdigest()[:16])' "$DEVICE")"
MSG="$(printf 'Pair this device to my pet.\nPet: %s\nDevice: %s' "$PET" "$KEYID")"
echo "You sign (no NEAR moves): $MSG"
if [ "$NETWORK" = mainnet ] && [ "${CONFIRM_MAINNET:-}" != yes ]; then echo "(dry run: re-run with CONFIRM_MAINNET=yes)"; exit 0; fi
NONCE="$(openssl rand -base64 32)"
S="$(sign "$OWNER" "$MSG" "$NONCE")"
[ -n "$S" ] || { echo "signing failed: is $OWNER's key in the keychain?" >&2; exit 1; }
BODY="$(S="$S" N="$NONCE" K="$DEVICE" python3 -I -c 'import json,os; s=json.loads(os.environ["S"]); print(json.dumps({"key": os.environ["K"], "signature": s["signature"], "publicKey": s["publicKey"], "nonce": os.environ["N"]}))')"
curl -s --max-time 60 -X POST "$API/pets/$PET/device" -H 'Content-Type: application/json' -d "$BODY"; echo
