#!/usr/bin/env bash
# Helpers for the step scripts: read-only RPC views, and NEP-413 signing with the near CLI (key from the macOS keychain).
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
RPC="${RPC:-$([ "$NETWORK" = mainnet ] && echo https://rpc.mainnet.fastnear.com || echo https://test.rpc.fastnear.com)}"

# view <account> <method> <json args>  -> the JSON the method returned (read-only, costs nothing)
view() {
  local args; args="$(printf '%s' "$3" | base64 | tr -d '\n')"
  curl -s --max-time 30 "$RPC" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"query\",\"params\":{\"request_type\":\"call_function\",\"finality\":\"final\",\"account_id\":\"$1\",\"method_name\":\"$2\",\"args_base64\":\"$args\"}}" |
    python3 -I -c 'import sys,json; r=json.load(sys.stdin); res=r.get("result",{}); print(bytes(res["result"]).decode() if "result" in res else json.dumps(r.get("error") or res))'
}

# sign <account> <message> <nonce base64>  -> {"accountId","publicKey","signature"} (NEP-413, recipient = the vault)
sign() {
  near message sign-nep413 utf8 "$2" nonce "$3" recipient "$VAULT" sign-as "$1" sign-with-keychain network-config "$NETWORK" 2>/dev/null |
    sed -n '/^{/,/^}/p'
}
