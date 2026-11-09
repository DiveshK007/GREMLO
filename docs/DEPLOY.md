# Deploying Notchi

Three pieces: the API (Fly.io), the web app (Vercel), the Mac app (signed .dmg). The contract stays on 0G Galileo until audited.
Secrets live only in each host's secret store. Never commit them, never put them in the image.

## 1. API on Fly.io (Mumbai region)

The Dockerfile builds from the repo root because the server imports `packages/brain`.

```bash
fly auth login
cd apps/server
fly launch --no-deploy --copy-config --name <your-app-name>   # keep fly.toml; set `app` to your name
fly volumes create notchi_data --size 1 --region bom             # the JSON store lives here (STORE_PATH=/data/data.json)
fly secrets set \
  RP_ID=... RP_SIGNING_KEY=... WORLD_APP_ID=... \
  ZG_API_KEY=... ZG_API_BASE=... ZG_MODEL_SMART=... ZG_MODEL_CHEAP=... \
  ZG_CHAIN_RPC=... ZG_CHAIN_ID=16602 ZG_VAULT_ADDRESS=... ZG_VAULT_DEPLOY_BLOCK=... ZG_OPERATOR_KEY=... \
  MOOD_THRIVING_WEI=... MOOD_STABLE_WEI=... MOOD_HUNGRY_WEI=... \
  WEB_ORIGIN=https://<your-vercel-domain> \
  ARKIV_ACCESS_KEY=... ARKIV_KEY=...        # optional: public campaign cards + receipts on Arkiv (Rabdi testnet); key needs tGLM
  RESEND_API_KEY=... MAIL_FROM=...          # optional: brand budget alerts (50/80/100%) and weekly reports by email
  PET_WALLET_MNEMONIC=... ZG_ROUTER_ACCOUNT=0x...  # optional: pets pay for their own 0G brain (see below)
fly deploy --dockerfile Dockerfile --build-context ../..          # or from the repo root: fly deploy -c apps/server/fly.toml
curl https://<your-app-name>.fly.dev/health                       # {"ok":true}
```

Production settings baked into the image: `HOST=0.0.0.0`, `REQUIRE_SIGNED=1` (every view, think and click must be signed by a paired Mac),
`TRUST_PROXY=1` (rate limits use Fly's client IP), `STORE_PATH=/data/data.json`. The server refuses to listen publicly without `REQUIRE_SIGNED=1`.

Copy the existing store once if you want history: `fly ssh sftp shell` then `put data.json /data/data.json` (stop the old server first).

Limits that matter in production: one machine only (the store is a single file; move to Postgres before scaling out, see PLAN_V2 A2),
and the operator key is a Fly secret (encrypted at rest). Move it to a KMS or multisig before mainnet (PLAN_V2 E4).

## 2. Web on Vercel

```bash
cd apps/web
vercel link            # root directory: apps/web, framework: Next.js
vercel env add NEXT_PUBLIC_SERVER_URL production      # https://<your-app-name>.fly.dev
vercel env add NEXT_PUBLIC_VAULT_ADDRESS production
vercel env add NEXT_PUBLIC_CHAIN_ID production         # 16602
vercel env add NEXT_PUBLIC_CHAIN_RPC production
vercel env add NEXT_PUBLIC_EXPLORER production
vercel env add NEXT_PUBLIC_WORLD_APP_ID production
vercel env add NEXT_PUBLIC_WORLD_RP_ID production
vercel env add NEXT_PUBLIC_WORLD_ENV production         # staging until World production is configured
vercel env add NEXT_PUBLIC_WORLD_PRESET production
vercel --prod
```

Then set `WEB_ORIGIN` on Fly to the Vercel URL (CORS) and redeploy the API.

## 3. Mac app

Point it at production with `NOTCHI_SERVER=https://<your-app-name>.fly.dev NOTCHI_WEB=https://<your-vercel-domain>`.
Each user then pairs their Mac once: Notchi menu → Settings → Pair this Mac with my pet (signs with the pet owner's wallet).
Signed, notarised .dmg + Sparkle auto-update need an Apple Developer account; see PLAN_V2 phase G.

## Arkiv (optional)

Get an access key at hub.arkiv.network/access-keys and testnet tGLM for the `ARKIV_KEY` account at hub.arkiv.network/faucet.
With both set, each saved campaign publishes a `notchi.campaign` card and each settlement a `notchi.receipt`, all expiring with the campaign.
Without them Arkiv is simply off; nothing else changes.

## Brand emails (optional)

Brands can leave an email when they fund a campaign. With `RESEND_API_KEY` and `MAIL_FROM` (a sender on a domain verified in Resend)
set, the worker emails each level of budget alert once (50, 80, 100% spent) and a weekly report (views, verified humans, clicks,
spend, best hook). Addresses stay in the server store; they are never served back or published. Without the keys mail is off.

## Pets that pay for their own brain (optional)

The loop: brand pays the pet -> the pet's own wallet -> deposit into the 0G Router's Payment Layer -> the pet's next
think is charged against that credit at the cost the Router reports. It only closes on testnet if the brain uses the
testnet Router, because campaigns pay in Galileo testnet 0G:

  ZG_API_BASE=https://router-api-testnet.integratenetwork.work/v1
  ZG_API_KEY=sk-...            # created at pc.testnet.0g.ai by the ZG_ROUTER_ACCOUNT wallet
  ZG_MODEL=qwen3-omni-flash    # the model the testnet Router serves (GET /v1/models)
  ZG_ROUTER_ACCOUNT=0x...      # that wallet's address; deposits are made for it via depositFor
  PET_WALLET_MNEMONIC="..."    # a fresh 12-word phrase used only for pet wallets; each pet gets one index
  FEED_DAILY_CAP=0.05          # 0G per pet per day the worker may deposit without asking (owner can change it)
  FEED_RESERVE=0.002           # left in each pet wallet for gas

The owner opts in on /me ("Let it pay for its brain"), which points the pet's payout at its wallet. Every deposit is
decided by a fixed rule (reserve, daily cap); above the cap the owner signs with their wallet and proves with World ID.
Create a World action `approve-spend` (unlimited verifications) next to `register-pet`. The owner can withdraw the
pet wallet at any time. The pet's credit is Notchi's bookkeeping of its share of the router account, kept from the
deposit tx hashes and the per-call `total_cost` the Router returns; the router account balance itself is onchain.

## Holdback and fraud rules

Views wait `HOLDBACK_HOURS` (24 in the Docker image, 0 locally) before they can be paid. Then fixed rules void what
looks like a farm (more than 3 pets from one network in an hour) or a script (a pet seen in more than 20 hours of a
day). Voided views are never charged; brands see the count and reason. When a campaign ends, held views are reviewed
at once, because the contract pays for only one more hour.

## 4. Checks after deploying

- `GET /health` is ok; `GET /stats` returns numbers from the chain.
- A new campaign funded on the web app shows on a paired Mac within 10 s.
- An unsigned `POST /impressions` from curl gets 401.
- The worker logs `worker: settled campaign N` within 10 minutes of queued views.
