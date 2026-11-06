# apps/server

Node + viem. Talks to `CampaignVault` as the operator.

```
cp .env.example .env   # fill values; local anvil values are in contracts/.env.local
npm install
npm start              # :8787
npm test               # settlement batching math
```

Amounts are wei as decimal strings. `seeded: true` means the data comes from local anvil test accounts, not real 0G tokens, and must be labelled as seeded on screen.

## Routes

`GET /world/sign?action=register-pet` -> `{ sig, nonce, created_at, expires_at }`, the RP signature the client passes to IDKit as `rp_context`. Signed with `RP_SIGNING_KEY`, which never leaves the server. Unknown actions get 400.

`POST /pets/register` `{ name?, petKey, ownerAddress, payoutAddress, worldProof }`. `worldProof` is the IDKit v4 result (`completion.result`), passed through unchanged. The server forwards it to `POST https://developer.world.org/api/v4/verify/{RP_ID}` and checks `success`, `environment` and `action`. If those pass, it calls `registerPet` on the vault, and only after that succeeds does it store the nullifier.
-> `{ name, petKey, owner, payout, verified, registerTx, seeded }`. 400 for a missing or non-v4 proof, 403 `World proof rejected: <code>` if the portal says no, 409 `already has a pet` for a reused nullifier, 502 if the portal or chain is down. A failed `registerPet` keeps no nullifier, so the human can retry.

`POST /impressions` `{ impressions: [{ petKey, campaignId, count }] }` -> `{ accepted, pending }`. `petKey` may also be the pet name. Counts accumulate until settled.

`POST /settle/:campaignId` -> `{ campaignId, settled: [{ petKey, count, amount, txHash }], pending, error?, seeded }`. Never pays more than the campaign has left; the rest stays pending.

`GET /campaigns/active` -> the campaign the pet shows (first live one that can still pay for an impression), or `null`:
```json
{ "campaignId": "1", "line": "Ship faster with Acme CI", "brand": "Acme", "ratePerImpression": "1000" }
```
The chain stores only a hash of the line and the brand's address. `line` and `brand` are looked up in `lines` (by hash) and `brands` (by address) in `data.json`. If there's no match, `line` is `null` and `brand` is the address.

`GET /pets/:name` (name or pet key):
```json
{ "name": "mochi.notchi.eth", "mood": "asleep", "walletBalance": "1250000", "computeBalance": null,
  "impressionsToday": 42, "lastThoughts": [], "lastMeal": null, "seeded": true }
```
`walletBalance` is the onchain balance of the pet's payout address. `impressionsToday` counts impressions accepted since 00:00 UTC. The brain does not report to the server yet, so `computeBalance` is `null`, `lastThoughts` is empty, `lastMeal` is `null` and `mood` is `asleep`. None of these are made up.

Once the brain reports, each `lastThoughts` entry looks like `{ "action": "work", "requestId": "<0G x_0g_trace.request_id>", "at": 1793970566 }`. `action` is one of the brain's `ACTIONS`, verbatim: `wake`, `work`, `wave`, `wait`, `celebrate`, `sad`, `go_home`, `sleep`.

Impressions are client-reported and unsigned in v1. World's one-human-one-pet rule is the defence.
