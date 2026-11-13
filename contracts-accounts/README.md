# Readable pet accounts (optional)

`gremlo.near` runs the **factory**. Only a parent account can create its sub-accounts, so the factory creates
`<pet>.gremlo.near` at hatching and deploys the **purse** to it.

- The owner's wallet holds the pet account's full-access key (withdrawals, caps, providers, closing).
- The Mac holds only a function-call key limited to `pay_inference`, with a 0.25 NEAR gas allowance. A
  function-call key can't transfer funds, so every spend goes through the purse.
- The purse pays only allow-listed inference providers, within a per-call cap and a daily cap, keeps a 0.5 NEAR
  reserve, and logs each payment with its request id. The model can ask for a payment; it can never sign one.
- A taken name refunds the deposit and suggests `<name>-2`. No auctions, no paid names.
- Product copy never names the chain ("purse", "earned", "paid for thinking"); the account id shows only in
  Settings, Advanced.

    ./build.sh      # purse, then the factory with the purse embedded (res/)
    cargo test      # caps, allow-list, owner-only, the Mac key's single method, separate keys

## Turning it on (testnet)

The app side is wired: with `PURSE_PARENT` set, the server treats a pet whose purse fits (owned by the pet's owner,
allowed to pay the operator) as a purse pet. It asks the Mac to pay after each thought, and counts a payment only
once the chain shows the purse paid exactly that thought. Pets without a purse keep using the vault's compute budget.
Not deployed yet. These commands use the official `near` CLI (near-cli-rs) and weren't run from this repo.

```bash
# 1. build (already in res/), then deploy the factory to the parent account and initialise it in the same tx
./build.sh
near contract deploy gremlo.testnet use-file res/gremlo_factory.wasm \
  with-init-call new json-args '{"providers":["operator.gremlo.testnet"],"per_call":"500000000000000000000","daily":"10000000000000000000000"}' \
  prepaid-gas '30 Tgas' attached-deposit '0 NEAR' network-config testnet sign-with-keychain send
#    per_call must be at least the server's smart fee (COMPUTE_FEE_SMART_YOCTO), or paid thinking sleeps

# 2. the owner creates the pet's purse: their own full-access key, plus the key from the Mac
#    (Settings → Phone and Mac → The pet's purse → Copy). 2 NEAR covers storage and the 0.5 NEAR reserve.
near contract call-function as-transaction gremlo.testnet create_pet \
  json-args '{"name":"<pet>","owner":"owner.gremlo.testnet","owner_key":"ed25519:<owner public key>","mac_key":"ed25519:<from the Mac>"}' \
  prepaid-gas '100 Tgas' attached-deposit '2 NEAR' sign-as owner.gremlo.testnet network-config testnet sign-with-keychain send

# 3. the owner points the pet's earnings at the purse, and keeps nothing back in the vault's budget
near contract call-function as-transaction vault.gremlo.testnet set_payout json-args '{"pet_id":"<pet>","payout":"<pet>.gremlo.testnet"}' \
  prepaid-gas '30 Tgas' attached-deposit '0 NEAR' sign-as owner.gremlo.testnet network-config testnet sign-with-keychain send
near contract call-function as-transaction vault.gremlo.testnet set_compute_share json-args '{"pet_id":"<pet>","bps":0}' \
  prepaid-gas '30 Tgas' attached-deposit '0 NEAR' sign-as owner.gremlo.testnet network-config testnet sign-with-keychain send

# 4. server: PURSE_PARENT=gremlo.testnet in apps/server/.env, then restart it
```

After that, `/me` shows "The pet's purse", Settings on the Mac shows "Pays from <pet>.gremlo.testnet", and each
thought's charge links to the purse's `pay_inference` transaction.
