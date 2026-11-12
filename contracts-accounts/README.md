# Readable pet accounts (optional)

`notchi.near` runs the **factory**. Only a parent account can create its sub-accounts, so the factory creates
`<pet>.notchi.near` at hatching and deploys the **purse** to it.

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

Deploy (testnet example): `near deploy notchi.testnet res/notchi_factory.wasm`, then
`near call notchi.testnet new '{"providers":["<provider>"],"per_call":"<yocto>","daily":"<yocto>"}' --accountId notchi.testnet`.
Not deployed by this repo; the live build still uses the vault's per-pet compute budget.
