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

`POST /pets/register` `{ name?, petKey, ownerAddress, payoutAddress, worldProof: { nullifier_hash, ... } }`
-> `{ name, petKey, owner, payout, verified, registerTx, seeded }`. 403 if the World proof fails (always, unless `WORLD_DEV_BYPASS=1`), 409 if the nullifier or pet is already used.

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

Impressions are client-reported and unsigned in v1. World's one-human-one-pet rule is the defence.
