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

`GET /campaigns/active`
```json
{ "chainId": 31337, "campaigns": [{ "id": "1", "brand": "0x..", "line": null, "lineHash": "0x..",
  "rate": "1000000000000000", "budget": "...", "spent": "...", "remaining": "...",
  "endTime": 1794061885, "createdTx": "0x..", "seeded": true }] }
```
`line` is the ad text, looked up from `lines` in `data.json` by hash (the chain only stores the hash); `null` if unknown.

`GET /pets/:name` (name or pet key)
```json
{ "name": "mochi", "petKey": "0x..", "owner": "0x..", "payout": "0x..", "verified": true,
  "payoutBalance": "...", "earned": "...", "impressionsSettled": "7",
  "settlements": [{ "campaignId": "1", "count": "7", "amount": "...", "txHash": "0x..", "blockNumber": "4" }],
  "pending": { "1": 2 }, "seeded": true }
```

Impressions are client-reported and unsigned in v1. World's one-human-one-pet rule is the defence.
