#!/usr/bin/env bash
# Step 7 (NEAR: the budget you choose): a small real campaign from BRAND, then its line text to the mainnet API.
#   BRAND=you.near LINE="Your line here" [BUDGET_NEAR=0.2 RATE_NEAR=0.003 HOURS=24] bash scripts/mainnet/70-campaign.sh
. "$(dirname "$0")/lib.sh"
need BRAND; need LINE
BUDGET_NEAR="${BUDGET_NEAR:-0.02}"; RATE_NEAR="${RATE_NEAR:-0.003}"; HOURS="${HOURS:-24}"
RATE="$(python3 -I -c 'import sys; from decimal import Decimal; print(int(Decimal(sys.argv[1]) * 10**24))' "$RATE_NEAR")"
END="$(( $(date +%s) + HOURS * 3600 ))"
HASH="$(cd "$REPO_DIR/apps/server" && L="$LINE" node --input-type=module -e 'import { keccak256, toHex } from "viem"; console.log(keccak256(toHex(process.env.L)).slice(2))')"
run "creates a campaign with $BUDGET_NEAR NEAR from $BRAND (rate $RATE_NEAR NEAR a view, ends in ${HOURS}h; unspent NEAR is refunded after the end)" \
  near contract call-function as-transaction "$VAULT" create_campaign json-args "{\"line_hash\":\"$HASH\",\"rate\":\"$RATE\",\"end_time\":$END}" \
  prepaid-gas '30 Tgas' attached-deposit "$BUDGET_NEAR NEAR" sign-as "$BRAND" network-config "$NETWORK" sign-with-keychain send
if [ "$NETWORK" = testnet ] || [ "${CONFIRM_MAINNET:-}" = yes ]; then
  ID="$(view "$VAULT" campaign_count '{}')"
  echo "campaign #$ID: $(view "$VAULT" get_campaign "{\"id\":$ID}")"
  BODY="$(I="$ID" L="$LINE" H="0x$HASH" python3 -I -c 'import json,os; print(json.dumps({"campaignId": os.environ["I"], "line": os.environ["L"], "lineHash": os.environ["H"]}))')"
  curl -s --max-time 60 -X POST "$API/campaigns" -H 'Content-Type: application/json' -d "$BODY"; echo
  echo "active: $(curl -s --max-time 30 "$API/campaigns/active")"
fi
