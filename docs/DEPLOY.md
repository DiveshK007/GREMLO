# Deploying Gremlo

Three pieces: the API (Fly.io), the web app (Vercel), the Mac app (signed .dmg). The vault is `vault.gremlo.testnet` on NEAR testnet.
Secrets live only in each host's secret store. Never commit them, never put them in the image.
Nothing here has been deployed yet; `fly.toml` and `apps/web/vercel.json` are ready for when it is.

## 1. API on Fly.io (Mumbai region)

The Dockerfile builds from the repo root because the server imports `packages/brain`.

```bash
fly auth login
(cd apps/server && fly launch --no-deploy --copy-config --name <your-app-name>)  # keeps fly.toml; set `app` to your name
fly volumes create gremlo_data --size 1 --region bom -a <your-app-name>             # the JSON store (STORE_PATH=/data/data.json)
fly secrets set -a <your-app-name> \
  NEAR_NETWORK=testnet NEAR_CONTRACT_ID=vault.gremlo.testnet NEAR_RPC_URL=... \
  NEAR_OPERATOR_ACCOUNT_ID=operator.gremlo.testnet NEAR_OPERATOR_PRIVATE_KEY=... \
  NEAR_AI_BASE_URL=... NEAR_AI_API_KEY=... NEAR_AI_MODEL_SMART=... NEAR_AI_MODEL_CHEAP=... \
  COMPUTE_FEE_SMART_YOCTO=... COMPUTE_FEE_CHEAP_YOCTO=... \
  WORLD_APP_ID=... RP_ID=... RP_SIGNING_KEY=... \
  WEB_ORIGIN=https://<your-vercel-domain>
  # optional: PURSE_PARENT (only once the purse factory is deployed), GALLERY_REVIEW_TOKEN,
  # RESEND_API_KEY + MAIL_FROM (brand emails), ARKIV + ARKIV_KEY + ARKIV_ACCESS_KEY
fly deploy . -c apps/server/fly.toml --dockerfile apps/server/Dockerfile                # from the repo root
curl https://<your-app-name>.fly.dev/health                                             # 200 with "ok": true
```

The Fly health check polls `/health`, which answers 503 with plain reasons when the settlement worker stalls,
the operator account is under 0.5 NEAR, or views expired unpaid. Point an uptime monitor at the same URL.

Production settings baked into the image: `HOST=0.0.0.0`, `REQUIRE_SIGNED=1` (every view, think and click must be signed by a paired Mac),
`TRUST_PROXY=1` (rate limits use Fly's client IP), `STORE_PATH=/data/data.json`. The server refuses to listen publicly without `REQUIRE_SIGNED=1`.

Copy the existing store once if you want history: `fly ssh sftp shell` then `put data.json /data/data.json` (stop the old server first).

Limits that matter in production: one machine only (the store is a single file; move to Postgres before scaling out, see PLAN_V2 A2),
and the operator key is a Fly secret (encrypted at rest). Move it to a KMS or multisig before mainnet (PLAN_V2 E4).

## 2. Web on Vercel

`apps/web/vercel.json` sets the framework and `npm ci`. Node 22 comes from `engines` in `package.json`.

```bash
cd apps/web
vercel link            # root directory: apps/web
vercel env add NEXT_PUBLIC_SERVER_URL production        # https://<your-app-name>.fly.dev
vercel env add NEXT_PUBLIC_WEB_URL production           # https://<your-vercel-domain>
vercel env add NEXT_PUBLIC_NEAR_NETWORK production      # testnet
vercel env add NEXT_PUBLIC_NEAR_CONTRACT_ID production  # vault.gremlo.testnet
vercel env add NEXT_PUBLIC_NEAR_RPC_URL production
vercel env add NEXT_PUBLIC_WORLD_APP_ID production
vercel env add NEXT_PUBLIC_WORLD_RP_ID production
vercel env add NEXT_PUBLIC_WORLD_ENV production         # staging until World production is configured
vercel env add NEXT_PUBLIC_WORLD_PRESET production
vercel --prod
```

Then set `WEB_ORIGIN` on Fly to the Vercel URL (CORS) and redeploy the API.
After deploying, `E2E_BASE_URL=https://<your-vercel-domain> npm run e2e` runs the page checks against it.

## 3. Mac app

Point it at production with `GREMLO_SERVER=https://<your-app-name>.fly.dev GREMLO_WEB=https://<your-vercel-domain>`.
Each user then pairs their Mac once: Gremlo menu → Settings → Pair this Mac with my pet (signs with the pet owner's wallet).
Signed, notarised .dmg + Sparkle auto-update need an Apple Developer account; see PLAN_V2 phase G.

## Arkiv (optional)

Get an access key at hub.arkiv.network/access-keys and testnet tGLM for the `ARKIV_KEY` account at hub.arkiv.network/faucet.
With both set, each saved campaign publishes a `gremlo.campaign` card and each settlement a `gremlo.receipt`, all expiring with the campaign.
Without them Arkiv is simply off; nothing else changes.

## Brand emails (optional)

Brands can leave an email when they fund a campaign. With `RESEND_API_KEY` and `MAIL_FROM` (a sender on a domain verified in Resend)
set, the worker emails each level of budget alert once (50, 80, 100% spent) and a weekly report (views, verified humans, clicks,
spend, best hook). Addresses stay in the server store; they are never served back or published. Without the keys mail is off.

## The pet's purse (optional, not deployed)

A pet with a purse pays for each thought from its own account, signed on the Mac with a key that can only call
`pay_inference`. Deploy the factory and create a purse with the steps in `contracts-accounts/README.md`, then set
`PURSE_PARENT` on Fly. Without it every pet pays from its vault budget, as now.

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

## Mac app: signed, notarized dmg

`scripts/release-mac.sh` builds a universal `Gremlo.app` (pets and hook script inside), wraps it in a dmg, and with your Apple Developer account signs, notarizes and staples it. You need:

1. An Apple Developer Program membership and a "Developer ID Application" certificate in your keychain. `security find-identity -v -p codesigning` shows its name.
2. A notarytool profile, made once: `xcrun notarytool store-credentials gremlo --apple-id you@example.com --team-id TEAMID --password <app-specific password>`.
3. `SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=gremlo VERSION=0.2.0 ./scripts/release-mac.sh`

Output: `apps/mac/dist/Gremlo-<version>.dmg`. Without `SIGN_ID` the script signs ad hoc, so the app runs only on the Mac that built it. CI runs it unsigned to prove the bundle builds. There is no auto-update yet; ship a new dmg per version.
