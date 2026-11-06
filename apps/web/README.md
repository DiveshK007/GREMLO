# apps/web

Two pages for the demo, plus a landing page.

- `/pet` — Get your pet: connect wallet, name the pet, World ID QR, register. A 409 from the server shows the "You already have a pet" screen (the denied path).
- `/brand` — Fund a campaign: the pet suggests 3 lines (0G), the brand picks one, pays `createCampaign` on 0G Galileo from their browser wallet, gets a receipt. A lookup box shows budget / spent / left and a "Close and refund" button once the campaign has ended and the 1-hour settle window has passed.

## Run

```bash
cd apps/web
cp .env.example .env.local   # public values only
npm install
npm run dev                  # http://localhost:3000
```

Needs a browser wallet (Core or MetaMask). The page adds/switches to 0G Galileo (16602) itself.

## What the server must provide

All server calls are in `lib/api.ts`. Change that one file if a route differs.

| Route | Body | Returns |
|---|---|---|
| `GET /world/sign?action=register-pet` | — | `{ sig, nonce, created_at, expires_at }` from `signRequest` |
| `POST /pets/register` | `{ name, petKey, ownerAddress, payoutAddress, worldProof }` (`worldProof` = IDKit `completion.result`) | `{ ok, txHash?, name? }`; **409** if the nullifier was used |
| `POST /campaigns/lines` | `{ brief }` | `{ lines: [{ text, requestId }] }` (3 lines, real 0G request IDs) |
| `POST /settle/:id` | — | `{ txHash, count, amount, settled[], error? }`: pays queued impressions onchain (amount in wei) |
| `POST /campaigns` | `{ campaignId, line, lineHash, brand, txHash }` | anything 2xx. Server should check `keccak256(line) == lineHash` against the onchain campaign before showing it |

The server also needs CORS for `http://localhost:3000`.

## Honesty rules this page follows

- No fake lines: if `/campaigns/lines` fails, it says so and the brand writes their own.
- Payment is a real transaction from the brand's wallet; the receipt links to chainscan.
- If the server fails to save the line text after payment, the page says that instead of pretending.
