#!/usr/bin/env bash
# Step 1 (EC2, no NEAR): a pinned checkout in /opt/gremlo-mainnet, its data dir, and the operator key made ON THE BOX,
# written only into root-only /etc/gremlo/mainnet.env. Prints the operator's PUBLIC key for step 2.
#   OWNER=you.near REV=<commit> bash scripts/mainnet/10-ec2-prepare.sh        (uses the ssh alias gremlo-ec2)
. "$(dirname "$0")/common.sh"
need OWNER; need REV
ssh gremlo-ec2 "OWNER='$OWNER' REV='$REV' NETWORK='$NETWORK' ROOT='$ROOT' bash -s" <<'REMOTE'
set -euo pipefail
sudo test -d /opt/gremlo-mainnet || sudo git clone --quiet https://github.com/DiveshK007/GREMLO.git /opt/gremlo-mainnet
sudo git -C /opt/gremlo-mainnet fetch --quiet origin
sudo git -C /opt/gremlo-mainnet checkout --quiet "$REV"
(cd /opt/gremlo-mainnet/apps/server && sudo npm ci --silent --no-audit --no-fund)
sudo install -d -o gremlo -g gremlo -m 700 /data/gremlo-mainnet
if ! sudo test -s /etc/gremlo/mainnet.env; then
  sudo install -m 600 /dev/null /etc/gremlo/mainnet.env
  # the private key goes from node straight into the root-only file; this session only ever sees the public key
  (cd /opt/gremlo-mainnet/apps/server && node --input-type=module -e '
    import { KeyPair } from "near-api-js";
    const k = KeyPair.fromRandom("ed25519");
    console.log(`NEAR_OPERATOR_PRIVATE_KEY=${k.toString()}`);
    console.error(`NEAR_OPERATOR_PUBLIC_KEY=${k.getPublicKey().toString()}`);' 2>/tmp/gremlo-operator.pub) | sudo tee -a /etc/gremlo/mainnet.env >/dev/null
  {
    echo "NEAR_NETWORK=$NETWORK"; echo "NEAR_CONTRACT_ID=vault.$ROOT"; echo "NEAR_OPERATOR_ACCOUNT_ID=operator.$ROOT"
    echo "REGISTER_OWNERS=$OWNER"; echo "WEB_ORIGIN=https://gremlo.vercel.app"
    # the same NEAR AI key and fee tiers as the testnet API, copied file to file without being shown
    sudo grep -E '^(NEAR_AI_[A-Z_]+|COMPUTE_FEE_[A-Z_]+)=' /etc/gremlo/api.env
  } | sudo tee -a /etc/gremlo/mainnet.env >/dev/null
  sudo cp /tmp/gremlo-operator.pub /etc/gremlo/mainnet.pub && rm -f /tmp/gremlo-operator.pub
fi
echo "env keys: $(sudo cut -d= -f1 /etc/gremlo/mainnet.env | tr '\n' ' ')"
echo "checkout: $(git -C /opt/gremlo-mainnet rev-parse --short HEAD)"
sudo cat /etc/gremlo/mainnet.pub
REMOTE
