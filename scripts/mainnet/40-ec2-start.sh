#!/usr/bin/env bash
# Step 4 (EC2, no NEAR): install the mainnet service, add its HTTPS site to Caddy (backup first, validated before
# reload), start it and check /health. The testnet service and site are not touched.
#   bash scripts/mainnet/40-ec2-start.sh
. "$(dirname "$0")/common.sh"
HOST="${API#https://}"
ssh gremlo-ec2 "HOST='$HOST' bash -s" <<'REMOTE'
set -euo pipefail
sudo cp /opt/gremlo-mainnet/deploy/vm/gremlo-api-mainnet.service /etc/systemd/system/
if ! sudo grep -q "^$HOST {" /etc/caddy/Caddyfile; then
  sudo cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
  printf '\n%s {\n\tencode gzip\n\treverse_proxy 127.0.0.1:8788 {\n\t\theader_up -Fly-Client-IP\n\t\theader_up X-Real-IP {remote_host}\n\t}\n}\n' "$HOST" | sudo tee -a /etc/caddy/Caddyfile >/dev/null
  sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
fi
sudo systemctl daemon-reload
sudo systemctl enable --now gremlo-api-mainnet >/dev/null 2>&1
sudo systemctl restart gremlo-api-mainnet
sudo systemctl reload caddy
sleep 4
systemctl is-active gremlo-api-mainnet
curl -s --max-time 10 http://127.0.0.1:8788/health; echo
sudo journalctl -u gremlo-api-mainnet -n 5 --no-pager | tail -5
REMOTE
echo "public: $(curl -s --max-time 30 "$API/health")"
